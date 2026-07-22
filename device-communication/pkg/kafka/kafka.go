package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/segmentio/kafka-go"
)

type Producer struct {
	writers map[string]*kafka.Writer
	mu      sync.RWMutex
	brokers []string
}

func NewProducer(brokers []string) *Producer {
	return &Producer{
		writers: make(map[string]*kafka.Writer),
		brokers: brokers,
	}
}

func (p *Producer) GetWriter(topic string) *kafka.Writer {
	p.mu.RLock()
	w, ok := p.writers[topic]
	p.mu.RUnlock()

	if ok {
		return w
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	w = &kafka.Writer{
		Addr:         kafka.TCP(p.brokers...),
		Topic:        topic,
		Balancer:     &kafka.LeastBytes{},
		BatchTimeout: 10 * time.Millisecond,
		BatchSize:    100,
		Async:        true,
		ErrorLogger:  log.Default(),
	}

	p.writers[topic] = w
	return w
}

func (p *Producer) SendMessage(ctx context.Context, topic string, key string, value interface{}) error {
	payload, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("marshal message: %w", err)
	}

	w := p.GetWriter(topic)
	return w.WriteMessages(ctx, kafka.Message{
		Key:   []byte(key),
		Value: payload,
		Time:  time.Now().UTC(),
	})
}

func (p *Producer) SendBatch(ctx context.Context, topic string, messages []kafka.Message) error {
	w := p.GetWriter(topic)
	return w.WriteMessages(ctx, messages...)
}

func (p *Producer) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	var lastErr error
	for topic, w := range p.writers {
		if err := w.Close(); err != nil {
			lastErr = err
		}
		delete(p.writers, topic)
	}
	return lastErr
}

type Consumer struct {
	reader  messageReader
	handler func(context.Context, []byte) error
}

type messageReader interface {
	FetchMessage(context.Context) (kafka.Message, error)
	CommitMessages(context.Context, ...kafka.Message) error
	Close() error
}

func NewConsumer(brokers []string, topic string, groupID string) *Consumer {
	return &Consumer{
		reader: kafka.NewReader(kafka.ReaderConfig{
			Brokers:  brokers,
			Topic:    topic,
			GroupID:  groupID,
			MinBytes: 10e3,
			MaxBytes: 10e6,
		}),
	}
}

func (c *Consumer) SetHandler(handler func(context.Context, []byte) error) {
	c.handler = handler
}

func (c *Consumer) Start(ctx context.Context) error {
	if c.handler == nil {
		return fmt.Errorf("no handler set")
	}

	defer c.reader.Close()
	for ctx.Err() == nil {
		m, err := c.reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			log.Printf("kafka consumer fetch failed, retrying: %v", err)
			if !waitRetry(ctx, 250*time.Millisecond) {
				return nil
			}
			continue
		}

		attempt := 0
		for {
			attempt++
			if err := c.handler(ctx, m.Value); err == nil {
				break
			} else {
				log.Printf("kafka handler failed; retaining topic=%s partition=%d offset=%d attempt=%d: %v",
					m.Topic, m.Partition, m.Offset, attempt, err)
			}
			if !waitRetry(ctx, consumerBackoff(attempt)) {
				return nil
			}
		}

		commitAttempt := 0
		for {
			commitAttempt++
			if err := c.reader.CommitMessages(ctx, m); err == nil {
				break
			} else {
				log.Printf("kafka commit failed; blocking next message topic=%s partition=%d offset=%d attempt=%d: %v",
					m.Topic, m.Partition, m.Offset, commitAttempt, err)
			}
			if !waitRetry(ctx, consumerBackoff(commitAttempt)) {
				return nil
			}
		}
	}
	return nil
}

func (c *Consumer) Close() error {
	return c.reader.Close()
}

func consumerBackoff(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	shift := attempt - 1
	if shift > 4 {
		shift = 4
	}
	return 250 * time.Millisecond * time.Duration(1<<shift)
}

func waitRetry(ctx context.Context, delay time.Duration) bool {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
