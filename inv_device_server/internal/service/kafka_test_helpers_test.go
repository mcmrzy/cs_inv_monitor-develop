package service

import (
	"context"
	"fmt"
	"io"
	"sync"

	"github.com/segmentio/kafka-go"
)

// scriptedKafkaReader is a test double for kafkaMessageReader.
//
// Messages are served from a fixed slice.  FetchMessage does NOT advance the
// cursor; only CommitMessages advances it, mimicking Kafka's at-least-once
// semantics where an uncommitted message is re-delivered on the next fetch.
// When the cursor reaches the end of the slice, FetchMessage returns io.EOF.
//
// The events field records a chronological log of "fetch:<offset>" and
// "commit:<offset>" entries for test assertions.
type scriptedKafkaReader struct {
	mu              sync.Mutex
	messages        []kafka.Message
	cursor          int
	events          []string
	fetchCount      int
	onCommitSuccess func(kafka.Message)
}

func (r *scriptedKafkaReader) FetchMessage(_ context.Context) (kafka.Message, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.cursor >= len(r.messages) {
		return kafka.Message{}, io.EOF
	}
	msg := r.messages[r.cursor]
	r.fetchCount++
	r.events = append(r.events, fmt.Sprintf("fetch:%d", msg.Offset))
	return msg, nil
}

func (r *scriptedKafkaReader) CommitMessages(_ context.Context, msgs ...kafka.Message) error {
	r.mu.Lock()
	for _, msg := range msgs {
		r.events = append(r.events, fmt.Sprintf("commit:%d", msg.Offset))
		if r.cursor < len(r.messages) && msg.Offset == r.messages[r.cursor].Offset {
			r.cursor++
		}
	}
	callback := r.onCommitSuccess
	r.mu.Unlock()

	if callback != nil {
		for _, msg := range msgs {
			callback(msg)
		}
	}
	return nil
}

func (r *scriptedKafkaReader) Close() error { return nil }

// snapshot returns the total fetch count and a copy of the event log.
func (r *scriptedKafkaReader) snapshot() (int, []string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	events := make([]string, len(r.events))
	copy(events, r.events)
	return r.fetchCount, events
}

// ingestErrorRecord captures a single SaveIngestError call for test assertions.
type ingestErrorRecord struct {
	sn     string
	topic  string
	code   string
	detail string
}

// fakeIngestErrorStore is a test double for ingestErrorStore.
//
// If err is non-nil, SaveIngestError returns it instead of nil, simulating a
// storage failure.  The called channel (when non-nil) is signalled on every
// invocation, allowing tests to synchronise with the audit attempt.
type fakeIngestErrorStore struct {
	mu      sync.Mutex
	records []ingestErrorRecord
	err     error
	called  chan struct{}
}

func (s *fakeIngestErrorStore) SaveIngestError(_ context.Context, sn, topic string, _ []byte, code, detail string) error {
	s.mu.Lock()
	s.records = append(s.records, ingestErrorRecord{sn: sn, topic: topic, code: code, detail: detail})
	s.mu.Unlock()

	if s.called != nil {
		select {
		case s.called <- struct{}{}:
		default:
		}
	}
	return s.err
}
