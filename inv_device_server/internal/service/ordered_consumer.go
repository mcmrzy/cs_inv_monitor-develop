package service

import (
	"context"
	"time"

	"inv-device-server/pkg/logger"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// kafkaMessageReader is the subset of kafka.Reader used by the ordered
// consumers. Keeping it as an interface makes offset behaviour testable
// without a Kafka broker.
type kafkaMessageReader interface {
	FetchMessage(context.Context) (kafka.Message, error)
	CommitMessages(context.Context, ...kafka.Message) error
	Close() error
}

// runOrderedKafkaConsumer never fetches the next record until the current
// record has been processed and its offset has been committed. This is
// deliberately conservative: it preserves partition ordering and prevents a
// later commit from acknowledging an earlier failed record. A future
// partition-aware dispatcher may add cross-partition concurrency while
// retaining the same invariant.
func runOrderedKafkaConsumer(
	ctx context.Context,
	name string,
	reader kafkaMessageReader,
	process func(context.Context, kafka.Message) error,
	retryBase time.Duration,
) {
	if retryBase <= 0 {
		retryBase = 250 * time.Millisecond
	}
	defer func() {
		if err := reader.Close(); err != nil && ctx.Err() == nil {
			logger.Warn("Kafka consumer close failed", zap.String("consumer", name), zap.Error(err))
		}
	}()

	logger.Info("Ordered Kafka consumer started", zap.String("consumer", name))
	for ctx.Err() == nil {
		message, err := reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			logger.Error("Kafka fetch failed",
				zap.String("consumer", name),
				zap.Error(err))
			if !waitConsumerRetry(ctx, retryBase) {
				break
			}
			continue
		}

		attempt := 0
		for {
			attempt++
			if err := process(ctx, message); err == nil {
				break
			} else {
				logger.Error("Kafka message processing failed; offset retained for retry",
					zap.String("consumer", name),
					zap.String("topic", message.Topic),
					zap.Int("partition", message.Partition),
					zap.Int64("offset", message.Offset),
					zap.Int("attempt", attempt),
					zap.Error(err))
			}
			if !waitConsumerRetry(ctx, retryBackoff(retryBase, attempt)) {
				return
			}
		}

		commitAttempt := 0
		for {
			commitAttempt++
			if err := reader.CommitMessages(ctx, message); err == nil {
				break
			} else {
				logger.Error("Kafka offset commit failed; next record remains blocked",
					zap.String("consumer", name),
					zap.String("topic", message.Topic),
					zap.Int("partition", message.Partition),
					zap.Int64("offset", message.Offset),
					zap.Int("attempt", commitAttempt),
					zap.Error(err))
			}
			if !waitConsumerRetry(ctx, retryBackoff(retryBase, commitAttempt)) {
				return
			}
		}
	}
	logger.Info("Ordered Kafka consumer stopped", zap.String("consumer", name))
}

func retryBackoff(base time.Duration, attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	shift := attempt - 1
	if shift > 4 {
		shift = 4
	}
	delay := base * time.Duration(1<<shift)
	if delay > 5*time.Second {
		return 5 * time.Second
	}
	return delay
}

func waitConsumerRetry(ctx context.Context, delay time.Duration) bool {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
