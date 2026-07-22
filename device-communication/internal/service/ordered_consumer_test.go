package service

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type orderedScriptedReader struct {
	mu              sync.Mutex
	messages        []kafka.Message
	fetchIndex      int
	commitFailures  int
	events          []string
	onCommitSuccess func(kafka.Message)
}

type orderedErrorRecord struct {
	sn, topic, code, detail string
	payload                 []byte
}

type orderedFakeErrorStore struct {
	mu      sync.Mutex
	err     error
	records []orderedErrorRecord
	called  chan struct{}
}

func (s *orderedFakeErrorStore) SaveIngestError(_ context.Context, sn, topic string, payload []byte, code, detail string) error {
	s.mu.Lock()
	s.records = append(s.records, orderedErrorRecord{
		sn: sn, topic: topic, payload: append([]byte(nil), payload...), code: code, detail: detail,
	})
	err := s.err
	called := s.called
	s.mu.Unlock()
	if called != nil {
		select {
		case called <- struct{}{}:
		default:
		}
	}
	return err
}

func (r *orderedScriptedReader) FetchMessage(ctx context.Context) (kafka.Message, error) {
	r.mu.Lock()
	if r.fetchIndex < len(r.messages) {
		message := r.messages[r.fetchIndex]
		r.fetchIndex++
		r.events = append(r.events, fmt.Sprintf("fetch:%d", message.Offset))
		r.mu.Unlock()
		return message, nil
	}
	r.mu.Unlock()
	<-ctx.Done()
	return kafka.Message{}, ctx.Err()
}

func (r *orderedScriptedReader) CommitMessages(_ context.Context, messages ...kafka.Message) error {
	r.mu.Lock()
	message := messages[0]
	r.events = append(r.events, fmt.Sprintf("commit:%d", message.Offset))
	if r.commitFailures > 0 {
		r.commitFailures--
		r.mu.Unlock()
		return errors.New("commit unavailable")
	}
	callback := r.onCommitSuccess
	r.mu.Unlock()
	if callback != nil {
		callback(message)
	}
	return nil
}

func (r *orderedScriptedReader) Close() error { return nil }

func (r *orderedScriptedReader) snapshot() (int, []string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.fetchIndex, append([]string(nil), r.events...)
}

func TestOrderedConsumer_FailureRetainsOffsetAndBlocksLaterMessage(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	reader := &orderedScriptedReader{messages: []kafka.Message{
		{Topic: "events", Partition: 0, Offset: 10},
		{Topic: "events", Partition: 0, Offset: 11},
	}}
	processed := make(chan struct{}, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "test", reader, func(context.Context, kafka.Message) error {
			select {
			case processed <- struct{}{}:
			default:
			}
			return errors.New("downstream unavailable")
		}, time.Second, nil)
	}()

	select {
	case <-processed:
	case <-time.After(time.Second):
		t.Fatal("message was not processed")
	}
	fetches, events := reader.snapshot()
	assert.Equal(t, 1, fetches)
	assert.Equal(t, []string{"fetch:10"}, events)
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("consumer did not stop")
	}
}

func TestOrderedConsumer_RetriesSameMessageThenCommitsBeforeNextFetch(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	reader := &orderedScriptedReader{messages: []kafka.Message{
		{Topic: "events", Partition: 0, Offset: 20},
		{Topic: "events", Partition: 0, Offset: 21},
	}}
	reader.onCommitSuccess = func(message kafka.Message) {
		if message.Offset == 21 {
			cancel()
		}
	}
	var mu sync.Mutex
	attempts := map[int64]int{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "test", reader, func(_ context.Context, message kafka.Message) error {
			mu.Lock()
			defer mu.Unlock()
			attempts[message.Offset]++
			reader.mu.Lock()
			reader.events = append(reader.events, fmt.Sprintf("process:%d", message.Offset))
			reader.mu.Unlock()
			if message.Offset == 20 && attempts[message.Offset] == 1 {
				return errors.New("temporary failure")
			}
			return nil
		}, time.Millisecond, nil)
	}()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("consumer did not finish")
	}
	_, events := reader.snapshot()
	require.Equal(t, []string{
		"fetch:20", "process:20", "process:20", "commit:20",
		"fetch:21", "process:21", "commit:21",
	}, events)
}

func TestOrderedConsumer_CommitFailureBlocksNextFetchAndDoesNotReprocess(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	reader := &orderedScriptedReader{
		messages:       []kafka.Message{{Topic: "events", Partition: 1, Offset: 30}},
		commitFailures: 1,
	}
	reader.onCommitSuccess = func(kafka.Message) { cancel() }
	processCount := 0
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "test", reader, func(context.Context, kafka.Message) error {
			processCount++
			return nil
		}, time.Millisecond, nil)
	}()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("consumer did not finish")
	}
	_, events := reader.snapshot()
	assert.Equal(t, 1, processCount)
	assert.Equal(t, []string{"fetch:30", "commit:30", "commit:30"}, events)
}

func TestProtocolParser_PermanentErrorIsAuditedBeforeCommitAndNextFetch(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	reader := &orderedScriptedReader{messages: []kafka.Message{
		{Topic: "telemetry", Partition: 0, Offset: 40, Value: []byte("not-json")},
		{Topic: "telemetry", Partition: 0, Offset: 41, Value: []byte(`{"sn":"SN001","msg_type":"unused","payload":null}`)},
	}}
	reader.onCommitSuccess = func(message kafka.Message) {
		if message.Offset == 41 {
			cancel()
		}
	}
	store := &orderedFakeErrorStore{}
	parser := &ProtocolParser{consumer: reader, ingestErrors: store}
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "protocol-test", reader, parser.processKafkaMessage, time.Millisecond, nil)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("protocol consumer did not finish")
	}

	_, events := reader.snapshot()
	assert.Equal(t, []string{"fetch:40", "commit:40", "fetch:41", "commit:41"}, events)
	store.mu.Lock()
	require.Len(t, store.records, 1)
	assert.Equal(t, "INVALID_BRIDGE_JSON", store.records[0].code)
	assert.Equal(t, []byte("not-json"), store.records[0].payload)
	store.mu.Unlock()
}

func TestProtocolParser_AuditFailureRetainsOffset(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	reader := &orderedScriptedReader{messages: []kafka.Message{
		{Topic: "telemetry", Partition: 0, Offset: 50, Value: []byte("not-json")},
		{Topic: "telemetry", Partition: 0, Offset: 51, Value: []byte(`{"sn":"SN001","payload":null}`)},
	}}
	store := &orderedFakeErrorStore{err: errors.New("database unavailable"), called: make(chan struct{}, 1)}
	parser := &ProtocolParser{consumer: reader, ingestErrors: store}
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "protocol-test", reader, parser.processKafkaMessage, time.Second, nil)
	}()
	select {
	case <-store.called:
	case <-time.After(time.Second):
		t.Fatal("ingest error audit was not attempted")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("protocol consumer did not stop")
	}

	fetches, events := reader.snapshot()
	assert.Equal(t, 1, fetches)
	assert.Equal(t, []string{"fetch:50"}, events)
}
