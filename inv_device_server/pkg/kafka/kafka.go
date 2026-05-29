package kafka

import (
	"context"
	"encoding/json"
	"fmt"
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
		Time:  time.Now(),
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
	reader  *kafka.Reader
	handler func(context.Context, []byte) error
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

	for {
		select {
		case <-ctx.Done():
			return c.reader.Close()
		default:
			m, err := c.reader.FetchMessage(ctx)
			if err != nil {
				return fmt.Errorf("fetch message: %w", err)
			}

			if err := c.handler(ctx, m.Value); err != nil {
				continue
			}

			if err := c.reader.CommitMessages(ctx, m); err != nil {
			}
		}
	}
}

func (c *Consumer) Close() error {
	return c.reader.Close()
}
