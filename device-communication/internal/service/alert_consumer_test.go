package service

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"inv-device-server/internal/config"
	"inv-device-server/internal/model"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMain(m *testing.M) {
	_ = logger.Init(&config.LogConfig{Level: "error", Filename: "stdout"})
	code := m.Run()
	logger.Sync()
	os.Exit(code)
}

func TestToInt(t *testing.T) {
	tests := []struct {
		name     string
		value    interface{}
		expected int
		ok       bool
	}{
		{"float64", float64(42.0), 42, true},
		{"float64 decimal truncated", float64(42.9), 42, true},
		{"int", 42, 42, true},
		{"int64", int64(42), 42, true},
		{"json number", json.Number("42"), 42, true},
		{"string invalid", "abc", 0, false},
		{"bool", true, 0, false},
		{"nil", nil, 0, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := toInt(tt.value)
			assert.Equal(t, tt.ok, ok)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestGetKeys(t *testing.T) {
	m := map[string]interface{}{
		"a": 1,
		"b": 2,
		"c": 3,
	}
	keys := getKeys(m)
	assert.Len(t, keys, 3)
	assert.Contains(t, keys, "a")
	assert.Contains(t, keys, "b")
	assert.Contains(t, keys, "c")
}

func TestParseAlarmV1(t *testing.T) {
	alarm, matched, err := parseAlarmV1("SN001", map[string]interface{}{
		"t": float64(1783676930), "v": float64(1),
		"data": map[string]interface{}{
			"source": float64(1), "code": float64(8),
			"level": float64(2), "state": float64(1),
		},
	})
	assert.True(t, matched)
	assert.NoError(t, err)
	assert.Equal(t, 1, alarm.Source)
	assert.Equal(t, 8, alarm.Code)
	assert.Equal(t, "fault", alarm.Level)
	assert.Equal(t, 1, *alarm.State)
	assert.Equal(t, int64(1783676930), alarm.Timestamp)
}

func TestParseAlarmV1Recovery(t *testing.T) {
	alarm, matched, err := parseAlarmV1("SN001", map[string]interface{}{
		"v": float64(1), "data": map[string]interface{}{
			"source": float64(0), "code": float64(3),
			"level": float64(1), "state": float64(0),
		},
	})
	assert.True(t, matched)
	assert.NoError(t, err)
	assert.Equal(t, 0, *alarm.State)
	assert.Equal(t, 3, alarm.Code)
}

func TestAlertConsumer_PostInternalAlarm(t *testing.T) {
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, http.MethodPost, r.Method)
		assert.Equal(t, "/api/v1/internal/device-alarm", r.URL.Path)
		assert.Equal(t, "application/json", r.Header.Get("Content-Type"))
		assert.Equal(t, "test-key", r.Header.Get("X-Internal-Key"))

		body, _ := io.ReadAll(r.Body)
		defer r.Body.Close()

		var request internalAlarmEnvelopeRequest
		err := json.Unmarshal(body, &request)
		assert.NoError(t, err)
		assert.Equal(t, "SN001", request.SN)
		assert.Equal(t, "alarm", request.Topic)
		assert.False(t, request.ReceivedAt.IsZero())
		var envelope map[string]interface{}
		require.NoError(t, json.Unmarshal(request.Envelope, &envelope))
		assert.Equal(t, float64(1), envelope["v"])

		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		nil, nil, handler.URL, "test-key",
	)

	alarm := &model.AlarmData{
		SN:      "SN001",
		Code:    1001,
		Level:   "warning",
		Message: "test alarm",
	}
	err := consumer.postInternalAlarm(alarm)
	assert.NoError(t, err)
}

func TestAlertConsumer_PostInternalAlarm_EmptyAPIServer(t *testing.T) {
	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		nil, nil, "", "",
	)

	alarm := &model.AlarmData{SN: "SN001"}
	err := consumer.postInternalAlarm(alarm)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "API server URL is empty")
}

func TestAlertConsumer_PostInternalAlarm_APIError(t *testing.T) {
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer handler.Close()

	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		nil, nil, handler.URL, "",
	)

	alarm := &model.AlarmData{SN: "SN001"}
	err := consumer.postInternalAlarm(alarm)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "500")
}

func TestNewAlertConsumer(t *testing.T) {
	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		redis.NewClient(&redis.Options{}), nil, "http://api", "key",
	)
	assert.NotNil(t, consumer)
	assert.NotNil(t, consumer.consumer)
}

func TestAlertConsumer_FailedDeliveryDoesNotCommitOrFetchPastMessage(t *testing.T) {
	requestSeen := make(chan struct{}, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		select {
		case requestSeen <- struct{}{}:
		default:
		}
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	reader := &scriptedKafkaReader{messages: []kafka.Message{{
		Topic: "alerts", Partition: 0, Offset: 1,
		Value: []byte(`{"sn":"SN001","msg_type":"alarm","received_at":"2026-07-14T12:00:00Z","payload":{"t":1784030400,"v":1,"data":{"source":1,"code":8,"level":2,"state":1}}}`),
	}, {
		Topic: "alerts", Partition: 0, Offset: 2,
		Value: []byte(`{"sn":"SN001","payload":null}`),
	}}}
	consumer := NewAlertConsumer([]string{"unused"}, "alerts", "group", nil, nil, server.URL, "key")
	consumer.consumer = reader
	ctx, cancel := context.WithCancel(context.Background())
	consumer.Start(ctx)
	select {
	case <-requestSeen:
	case <-time.After(time.Second):
		t.Fatal("alert delivery was not attempted")
	}
	cancel()
	time.Sleep(20 * time.Millisecond)
	fetches, events := reader.snapshot()
	assert.Equal(t, 1, fetches)
	assert.Equal(t, []string{"fetch:1"}, events)
}

func TestAlertConsumer_SuccessfulDeliveryCommitsThenFetchesNext(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	reader := &scriptedKafkaReader{messages: []kafka.Message{{
		Topic: "alerts", Partition: 0, Offset: 10,
		Value: []byte(`{"sn":"SN001","received_at":"2026-07-14T12:00:00Z","payload":{"t":1784030400,"v":1,"data":{"source":1,"code":8,"level":2,"state":1}}}`),
	}, {
		Topic: "alerts", Partition: 0, Offset: 11,
		Value: []byte(`{"sn":"SN001","received_at":"2026-07-14T12:03:00Z","payload":{"t":1784030580,"v":1,"data":{"source":1,"code":8,"level":2,"state":0}}}`),
	}}}
	reader.onCommitSuccess = func(message kafka.Message) {
		if message.Offset == 11 {
			cancel()
		}
	}
	consumer := NewAlertConsumer([]string{"unused"}, "alerts", "group", nil, nil, server.URL, "key")
	consumer.consumer = reader
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "alert-test", reader, consumer.processAlert, time.Millisecond, nil)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("alert consumer did not finish")
	}
	_, events := reader.snapshot()
	assert.Equal(t, int32(2), requests.Load())
	assert.Equal(t, []string{"fetch:10", "commit:10", "fetch:11", "commit:11"}, events)
}

func TestAlertConsumer_HTTP4xxAuditedBeforeCommit(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	reader := &scriptedKafkaReader{messages: []kafka.Message{{
		Topic: "alerts", Partition: 0, Offset: 60,
		Value: []byte(`{"sn":"SN001","received_at":"2026-07-14T12:00:00Z","payload":{"t":1784030400,"v":1,"data":{"source":1,"code":8,"level":2,"state":1}}}`),
	}}}
	reader.onCommitSuccess = func(kafka.Message) { cancel() }
	store := &fakeIngestErrorStore{}
	consumer := NewAlertConsumer([]string{"unused"}, "alerts", "group", nil, store, server.URL, "key")
	consumer.consumer = reader
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "alert-test", reader, consumer.processAlert, time.Millisecond, nil)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("alert consumer did not finish")
	}

	_, events := reader.snapshot()
	assert.Equal(t, []string{"fetch:60", "commit:60"}, events)
	store.mu.Lock()
	require.Len(t, store.records, 1)
	assert.Equal(t, "DOWNSTREAM_HTTP_4XX", store.records[0].code)
	assert.Equal(t, "SN001", store.records[0].sn)
	store.mu.Unlock()
}

func TestAlertConsumer_AuditFailureRetainsOffset(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	reader := &scriptedKafkaReader{messages: []kafka.Message{{
		Topic: "alerts", Partition: 0, Offset: 70, Value: []byte("not-json"),
	}, {
		Topic: "alerts", Partition: 0, Offset: 71, Value: []byte(`{"sn":"SN001","payload":null}`),
	}}}
	store := &fakeIngestErrorStore{err: assert.AnError, called: make(chan struct{}, 1)}
	consumer := NewAlertConsumer([]string{"unused"}, "alerts", "group", nil, store, "http://api", "key")
	consumer.consumer = reader
	done := make(chan struct{})
	go func() {
		defer close(done)
		runOrderedKafkaConsumer(ctx, "alert-test", reader, consumer.processAlert, time.Second, nil)
	}()
	select {
	case <-store.called:
	case <-time.After(time.Second):
		t.Fatal("alert ingest error audit was not attempted")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("alert consumer did not stop")
	}

	fetches, events := reader.snapshot()
	assert.Equal(t, 1, fetches)
	assert.Equal(t, []string{"fetch:70"}, events)
}
