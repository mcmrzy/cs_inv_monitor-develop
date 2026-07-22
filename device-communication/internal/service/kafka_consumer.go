package service

import (
	"context"
	"errors"
	"io"
	"sync"
	"time"

	"inv-device-server/pkg/logger"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// kafkaMessageReader abstracts a Kafka reader so that service-layer consumers
// can be tested with scripted doubles instead of a live broker connection.
// *kafka.Reader satisfies this interface at runtime.
type kafkaMessageReader interface {
	FetchMessage(ctx context.Context) (kafka.Message, error)
	CommitMessages(ctx context.Context, msgs ...kafka.Message) error
	Close() error
}

// runOrderedKafkaConsumer consumes Kafka messages in strict partition order.
//
// The function blocks on each message until the handler succeeds (returns nil)
// or the context is cancelled.  A message is only committed after the handler
// succeeds, guaranteeing at-least-once delivery without re-ordering.
//
// When the handler returns a permanent error (detected via asPermanentMessage
// or downstreamHTTPError.permanent), the caller's handler is expected to have
// already isolated the message in device_ingest_errors and returned nil so
// that the offset can advance.  Non-permanent errors cause the same message
// to be retried after retryDelay until the context is cancelled.
func runOrderedKafkaConsumer(
	ctx context.Context,
	name string,
	reader kafkaMessageReader,
	handler func(context.Context, kafka.Message) error,
	retryDelay time.Duration,
	wg *sync.WaitGroup,
) {
	if wg != nil {
		wg.Add(1)
		defer wg.Done()
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
			if !waitConsumerRetry(ctx, retryDelay) {
				return
			}
			continue
		}

		// Retry the handler until it succeeds or the context is cancelled.
		for ctx.Err() == nil {
			if err := handler(ctx, msg); err == nil {
				break
			} else {
				logger.Warn("Kafka handler failed, retaining message",
					zap.String("consumer", name),
					zap.String("topic", msg.Topic),
					zap.Int("partition", msg.Partition),
					zap.Int64("offset", msg.Offset),
					zap.Error(err))
				if !waitConsumerRetry(ctx, retryDelay) {
					return
				}
			}
		}
		if ctx.Err() != nil {
			return
		}

		// Retry the commit until it succeeds or the context is cancelled.
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
				if !waitConsumerRetry(ctx, retryDelay) {
					return
				}
			}
		}
	}
}

// waitConsumerRetry sleeps for d, returning false if the context is cancelled
// before the timer fires.  It is used by the ordered consumer loop and by the
// telemetry batcher to back off between retries while remaining cancellable.
func waitConsumerRetry(ctx context.Context, d time.Duration) bool {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

// retryBackoff computes an exponential backoff duration for the given attempt
// (1-based).  The result is base << (attempt-1), capped at base<<4 to avoid
// excessively long waits.
func retryBackoff(base time.Duration, attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	shift := attempt - 1
	if shift > 4 {
		shift = 4
	}
	return base << uint(shift)
}
