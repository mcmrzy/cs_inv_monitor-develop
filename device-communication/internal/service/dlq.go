package service

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
)

// DLQEntry captures a message that exhausted all retry attempts and was
// diverted to the dead-letter queue for manual inspection or replay.
type DLQEntry struct {
	ID            string          `json:"id"`
	Consumer      string          `json:"consumer"`
	Topic         string          `json:"topic"`
	Partition     int             `json:"partition"`
	Offset        int64           `json:"offset"`
	Key           []byte          `json:"key,omitempty"`
	Value         json.RawMessage `json:"value"`
	DeviceSN      string          `json:"device_sn,omitempty"`
	ErrorCode     string          `json:"error_code"`
	ErrorDetail   string          `json:"error_detail"`
	RetryCount    int             `json:"retry_count"`
	FirstFailedAt time.Time       `json:"first_failed_at"`
	LastFailedAt  time.Time       `json:"last_failed_at"`
	SentAt        time.Time       `json:"sent_at"`
}

// DeadLetterQueue is the storage abstraction for messages that could not be
// delivered after exhausting all retry attempts.  Implementations may use
// Redis, a database table, or an in-memory buffer for testing.
type DeadLetterQueue interface {
	// Send persists a single DLQ entry.
	Send(ctx context.Context, entry *DLQEntry) error
	// Size returns the number of entries currently in the DLQ.
	Size(ctx context.Context) (int64, error)
	// List returns up to limit entries, skipping offset.
	List(ctx context.Context, limit, offset int64) ([]*DLQEntry, error)
	// Remove deletes the entry with the given ID.
	Remove(ctx context.Context, id string) error
	// Clear removes all entries from the DLQ.
	Clear(ctx context.Context) error
}

// ── RedisDLQ ──────────────────────────────────────────────────────────────

// RedisDLQ stores dead-letter entries in a Redis list.  Each entry is
// JSON-encoded and pushed to the head of the list (LPUSH), so List returns
// entries in newest-first order.
type RedisDLQ struct {
	rdb      *redis.Client
	key      string
	idCounter uint64
}

// NewRedisDLQ creates a Redis-backed DLQ using the given key prefix.
// The actual Redis key is "<prefix>:entries".
func NewRedisDLQ(rdb *redis.Client, keyPrefix string) *RedisDLQ {
	if keyPrefix == "" {
		keyPrefix = "dlq:inv-device-server"
	}
	return &RedisDLQ{
		rdb: rdb,
		key: keyPrefix + ":entries",
	}
}

func (d *RedisDLQ) nextID() string {
	n := atomic.AddUint64(&d.idCounter, 1)
	return fmt.Sprintf("dlq-%d-%d", time.Now().UnixNano(), n)
}

func (d *RedisDLQ) Send(ctx context.Context, entry *DLQEntry) error {
	if d.rdb == nil {
		return fmt.Errorf("redis client is nil")
	}
	if entry.ID == "" {
		entry.ID = d.nextID()
	}
	entry.SentAt = time.Now().UTC()
	data, err := json.Marshal(entry)
	if err != nil {
		return fmt.Errorf("marshal DLQ entry: %w", err)
	}
	return d.rdb.LPush(ctx, d.key, data).Err()
}

func (d *RedisDLQ) Size(ctx context.Context) (int64, error) {
	if d.rdb == nil {
		return 0, fmt.Errorf("redis client is nil")
	}
	return d.rdb.LLen(ctx, d.key).Result()
}

func (d *RedisDLQ) List(ctx context.Context, limit, offset int64) ([]*DLQEntry, error) {
	if d.rdb == nil {
		return nil, fmt.Errorf("redis client is nil")
	}
	if limit <= 0 {
		limit = 50
	}
	// LRANGE start stop — newest first (LPUSH order).
	results, err := d.rdb.LRange(ctx, d.key, offset, offset+limit-1).Result()
	if err != nil {
		return nil, err
	}
	entries := make([]*DLQEntry, 0, len(results))
	for _, raw := range results {
		var entry DLQEntry
		if err := json.Unmarshal([]byte(raw), &entry); err != nil {
			continue
		}
		entries = append(entries, &entry)
	}
	return entries, nil
}

func (d *RedisDLQ) Remove(ctx context.Context, id string) error {
	if d.rdb == nil {
		return fmt.Errorf("redis client is nil")
	}
	entries, err := d.rdb.LRange(ctx, d.key, 0, -1).Result()
	if err != nil {
		return err
	}
	for _, raw := range entries {
		var entry DLQEntry
		if err := json.Unmarshal([]byte(raw), &entry); err != nil {
			continue
		}
		if entry.ID == id {
			// LREM removes the first occurrence of the exact string.
			return d.rdb.LRem(ctx, d.key, 1, raw).Err()
		}
	}
	return nil
}

func (d *RedisDLQ) Clear(ctx context.Context) error {
	if d.rdb == nil {
		return fmt.Errorf("redis client is nil")
	}
	return d.rdb.Del(ctx, d.key).Err()
}

// ── InMemoryDLQ ───────────────────────────────────────────────────────────

// InMemoryDLQ is a thread-safe in-memory DLQ implementation used in tests
// and as a no-op fallback when Redis is unavailable.
type InMemoryDLQ struct {
	mu       sync.Mutex
	entries  []*DLQEntry
	idCounter uint64
}

// NewInMemoryDLQ creates a new in-memory DLQ.
func NewInMemoryDLQ() *InMemoryDLQ {
	return &InMemoryDLQ{
		entries: make([]*DLQEntry, 0),
	}
}

func (d *InMemoryDLQ) nextID() string {
	n := atomic.AddUint64(&d.idCounter, 1)
	return fmt.Sprintf("mem-dlq-%d-%d", time.Now().UnixNano(), n)
}

func (d *InMemoryDLQ) Send(_ context.Context, entry *DLQEntry) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if entry.ID == "" {
		entry.ID = d.nextID()
	}
	entry.SentAt = time.Now().UTC()
	d.entries = append(d.entries, entry)
	return nil
}

func (d *InMemoryDLQ) Size(_ context.Context) (int64, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return int64(len(d.entries)), nil
}

func (d *InMemoryDLQ) List(_ context.Context, limit, offset int64) ([]*DLQEntry, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if offset >= int64(len(d.entries)) {
		return nil, nil
	}
	if limit <= 0 {
		limit = 50
	}
	end := offset + limit
	if end > int64(len(d.entries)) {
		end = int64(len(d.entries))
	}
	result := make([]*DLQEntry, end-offset)
	copy(result, d.entries[offset:end])
	return result, nil
}

func (d *InMemoryDLQ) Remove(_ context.Context, id string) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	for i, e := range d.entries {
		if e.ID == id {
			d.entries = append(d.entries[:i], d.entries[i+1:]...)
			return nil
		}
	}
	return nil
}

func (d *InMemoryDLQ) Clear(_ context.Context) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.entries = d.entries[:0]
	return nil
}

// ── Helpers ────────────────────────────────────────────────────────────────

// buildDLQEntry constructs a DLQEntry from a Kafka message and the failure
// context.  It is shared by the retry consumer and the individual consumer
// implementations.
func buildDLQEntry(consumer string, msg kafka.Message, sn, code, detail string, retryCount int, firstFailedAt time.Time) *DLQEntry {
	return &DLQEntry{
		Consumer:      consumer,
		Topic:         msg.Topic,
		Partition:     msg.Partition,
		Offset:        msg.Offset,
		Key:           msg.Key,
		Value:         append(json.RawMessage(nil), msg.Value...),
		DeviceSN:      sn,
		ErrorCode:     code,
		ErrorDetail:   detail,
		RetryCount:    retryCount,
		FirstFailedAt: firstFailedAt,
		LastFailedAt:  time.Now().UTC(),
	}
}
