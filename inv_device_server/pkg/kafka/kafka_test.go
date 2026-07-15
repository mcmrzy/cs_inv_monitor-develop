package kafka

import (
	"context"
	"errors"
	"sync"
	"testing"

	kafkago "github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeReader struct {
	mu         sync.Mutex
	messages   []kafkago.Message
	fetches    int
	commits    []int64
	onCommit   func()
	closeCount int
}

func (r *fakeReader) FetchMessage(ctx context.Context) (kafkago.Message, error) {
	r.mu.Lock()
	if r.fetches < len(r.messages) {
		message := r.messages[r.fetches]
		r.fetches++
		r.mu.Unlock()
		return message, nil
	}
	r.mu.Unlock()
	<-ctx.Done()
	return kafkago.Message{}, ctx.Err()
}

func (r *fakeReader) CommitMessages(_ context.Context, messages ...kafkago.Message) error {
	r.mu.Lock()
	r.commits = append(r.commits, messages[0].Offset)
	callback := r.onCommit
	r.mu.Unlock()
	if callback != nil {
		callback()
	}
	return nil
}

func (r *fakeReader) Close() error {
	r.mu.Lock()
	r.closeCount++
	r.mu.Unlock()
	return nil
}

func TestConsumer_HandlerFailureDoesNotCommitOrFetchNext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	reader := &fakeReader{messages: []kafkago.Message{
		{Topic: "topic", Partition: 0, Offset: 1, Value: []byte("first")},
		{Topic: "topic", Partition: 0, Offset: 2, Value: []byte("second")},
	}}
	consumer := &Consumer{reader: reader}
	consumer.SetHandler(func(context.Context, []byte) error {
		cancel()
		return errors.New("downstream failure")
	})

	require.NoError(t, consumer.Start(ctx))
	reader.mu.Lock()
	defer reader.mu.Unlock()
	assert.Equal(t, 1, reader.fetches)
	assert.Empty(t, reader.commits)
	assert.Equal(t, 1, reader.closeCount)
}

func TestConsumer_SuccessCommitsBeforeFetchingAnotherMessage(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	reader := &fakeReader{messages: []kafkago.Message{
		{Topic: "topic", Partition: 0, Offset: 7, Value: []byte("first")},
		{Topic: "topic", Partition: 0, Offset: 8, Value: []byte("second")},
	}}
	reader.onCommit = cancel
	consumer := &Consumer{reader: reader}
	consumer.SetHandler(func(context.Context, []byte) error { return nil })

	require.NoError(t, consumer.Start(ctx))
	reader.mu.Lock()
	defer reader.mu.Unlock()
	assert.Equal(t, 1, reader.fetches)
	assert.Equal(t, []int64{7}, reader.commits)
}
