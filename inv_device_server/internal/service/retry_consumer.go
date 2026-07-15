package service

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"time"

	"inv-device-server/pkg/logger"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// DefaultMaxRetries is the default maximum number of retry attempts for a
// transient error before the message is sent to the dead-letter queue.
const DefaultMaxRetries = 5

// DefaultBaseBackoff is the base duration for the exponential backoff used
// between retry attempts.
const DefaultBaseBackoff = 500 * time.Millisecond

// isRetryableError returns true for errors that may succeed on retry
// (5xx HTTP responses, network timeouts, connection refused) and false for
// permanent errors (4xx HTTP, JSON parse failures, missing required fields).
func isRetryableError(err error) bool {
	if err == nil {
		return false
	}
	// Permanent ingest errors are never retried.
	if _, ok := asPermanentMessage(err); ok {
		return false
	}
	// 4xx HTTP errors are permanent.
	var httpErr *downstreamHTTPError
	if errors.As(err, &httpErr) && httpErr.permanent() {
		return false
	}
	return true
}

// runOrderedKafkaConsumerWithRetry consumes Kafka messages in strict partition
// order with bounded retries and dead-letter queue integration.
//
// This function extends runOrderedKafkaConsumer with:
//   - Exponential backoff via retryBackoff (instead of a fixed delay).
//   - A maximum retry count (maxRetries). After exhausting retries the
//     message is sent to the DLQ and the offset is advanced.
//   - Permanent errors are detected early and sent to the DLQ immediately
//     (no retries wasted on errors that can never succeed).
//   - Monitoring metrics are recorded for each retry, DLQ send, and
//     successful processing.
//
// If dlq is nil the function behaves like runOrderedKafkaConsumer (retries
// forever until the context is cancelled), preserving backward compatibility.
func runOrderedKafkaConsumerWithRetry(
	ctx context.Context,
	name string,
	reader kafkaMessageReader,
	handler func(context.Context, kafka.Message) error,
	maxRetries int,
	baseBackoff time.Duration,
	dlq DeadLetterQueue,
	metrics *IngestMetrics,
) {
	if maxRetries < 1 {
		maxRetries = DefaultMaxRetries
	}
	if baseBackoff <= 0 {
		baseBackoff = DefaultBaseBackoff
	}
	defer reader.Close()

	for ctx.Err() == nil {
		msg, err := reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, io.EOF) {
				return
			}
			logger.Warn("Kafka fetch failed, retrying",
				zap.String("consumer", name), zap.Error(err))
			if !waitConsumerRetry(ctx, baseBackoff) {
				return
			}
			continue
		}

		startTime := time.Now()
		firstFailedAt := time.Time{}

		// Retry the handler until it succeeds, becomes permanent, or
		// exhausts maxRetries.
		handlerSucceeded := false
		for attempt := 0; attempt <= maxRetries; attempt++ {
			if ctx.Err() != nil {
				return
			}

			if attempt > 0 {
				if metrics != nil {
					metrics.IncRetry(name)
				}
				backoff := retryBackoff(baseBackoff, attempt)
				logger.Debug("Retrying Kafka message",
					zap.String("consumer", name),
					zap.String("topic", msg.Topic),
					zap.Int("partition", msg.Partition),
					zap.Int64("offset", msg.Offset),
					zap.Int("attempt", attempt),
					zap.Duration("backoff", backoff))
				if !waitConsumerRetry(ctx, backoff) {
					return
				}
			}

			if err := handler(ctx, msg); err == nil {
				handlerSucceeded = true
				break
			} else {
				if firstFailedAt.IsZero() {
					firstFailedAt = time.Now().UTC()
				}
				logger.Warn("Kafka handler failed",
					zap.String("consumer", name),
					zap.String("topic", msg.Topic),
					zap.Int("partition", msg.Partition),
					zap.Int64("offset", msg.Offset),
					zap.Int("attempt", attempt),
					zap.Int("max_retries", maxRetries),
					zap.Bool("retryable", isRetryableError(err)),
					zap.Error(err))

				// Permanent errors go straight to the DLQ without
				// wasting retry attempts.
				if !isRetryableError(err) {
					if dlq != nil {
						sendToDLQ(ctx, dlq, metrics, name, msg, err, attempt, firstFailedAt)
					}
					handlerSucceeded = true // offset should advance
					break
				}
			}
		}

		if !handlerSucceeded && ctx.Err() == nil {
			// Retries exhausted — send to DLQ and advance offset.
			lastErr := errors.New("max retries exhausted")
			if dlq != nil {
				sendToDLQ(ctx, dlq, metrics, name, msg, lastErr, maxRetries, firstFailedAt)
			} else {
				logger.Error("Retries exhausted with no DLQ configured, message dropped",
					zap.String("consumer", name),
					zap.String("topic", msg.Topic),
					zap.Int64("offset", msg.Offset))
			}
		}

		if metrics != nil {
			metrics.IncProcessed(name)
			metrics.RecordLatency(time.Since(startTime))
		}

		if ctx.Err() != nil {
			return
		}

		// Commit the offset (advance past this message).
		for ctx.Err() == nil {
			if err := reader.CommitMessages(ctx, msg); err == nil {
				break
			} else {
				logger.Warn("Kafka commit failed, blocking next message",
					zap.String("consumer", name),
					zap.String("topic", msg.Topic),
					zap.Int("partition", msg.Partition),
					zap.Int64("offset", msg.Offset),
					zap.Error(err))
				if !waitConsumerRetry(ctx, baseBackoff) {
					return
				}
			}
		}
	}
}

// sendToDLQ sends a message to the dead-letter queue with error context.
// It extracts the device SN from the message value (if possible) and
// records the appropriate metrics.
func sendToDLQ(
	ctx context.Context,
	dlq DeadLetterQueue,
	metrics *IngestMetrics,
	consumer string,
	msg kafka.Message,
	err error,
	retryCount int,
	firstFailedAt time.Time,
) {
	code := "MAX_RETRIES_EXHAUSTED"
	detail := err.Error()

	if permanent, ok := asPermanentMessage(err); ok {
		code = permanent.code
		detail = permanent.err.Error()
		if metrics != nil {
			metrics.IncPermanentError()
		}
	} else {
		var httpErr *downstreamHTTPError
		if errors.As(err, &httpErr) {
			if httpErr.permanent() {
				code = "DOWNSTREAM_HTTP_4XX"
			} else {
				code = "DOWNSTREAM_HTTP_5XX"
			}
			detail = httpErr.Error()
		}
	}

	sn := extractSNFromMessage(msg.Value)
	entry := buildDLQEntry(consumer, msg, sn, code, detail, retryCount, firstFailedAt)

	if sendErr := dlq.Send(ctx, entry); sendErr != nil {
		logger.Error("Failed to send message to DLQ, message will be dropped",
			zap.String("consumer", consumer),
			zap.String("topic", msg.Topic),
			zap.Int64("offset", msg.Offset),
			zap.Error(sendErr))
	} else {
		logger.Warn("Message sent to DLQ after retry exhaustion",
			zap.String("consumer", consumer),
			zap.String("topic", msg.Topic),
			zap.Int64("offset", msg.Offset),
			zap.String("device_sn", sn),
			zap.String("error_code", code),
			zap.Int("retry_count", retryCount))
	}

	if metrics != nil {
		metrics.IncDLQ(consumer)
	}
}

// extractSNFromMessage attempts to extract the "sn" field from a Kafka
// message value.  Both the telemetry bridge format and the alert bridge format
// include an "sn" field at the top level of the JSON envelope.
func extractSNFromMessage(value []byte) string {
	if len(value) == 0 {
		return ""
	}
	var sn struct {
		SN string `json:"sn"`
	}
	if err := json.Unmarshal(value, &sn); err != nil {
		return ""
	}
	return sn.SN
}
