package service

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"inv-device-server/internal/config"
	"inv-device-server/internal/model"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
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

		var alarm model.AlarmData
		err := json.Unmarshal(body, &alarm)
		assert.NoError(t, err)
		assert.Equal(t, "SN001", alarm.SN)

		w.WriteHeader(http.StatusOK)
	}))
	defer handler.Close()

	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		nil, handler.URL, "test-key",
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
		nil, "", "",
	)

	alarm := &model.AlarmData{SN: "SN001"}
	err := consumer.postInternalAlarm(alarm)
	assert.NoError(t, err)
}

func TestAlertConsumer_PostInternalAlarm_APIError(t *testing.T) {
	handler := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer handler.Close()

	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		nil, handler.URL, "",
	)

	alarm := &model.AlarmData{SN: "SN001"}
	err := consumer.postInternalAlarm(alarm)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "500")
}

func TestNewAlertConsumer(t *testing.T) {
	consumer := NewAlertConsumer(
		[]string{"localhost:9092"}, "topic", "group",
		redis.NewClient(&redis.Options{}), "http://api", "key",
	)
	assert.NotNil(t, consumer)
	assert.Equal(t, 5, consumer.workerCount)
	assert.NotNil(t, consumer.msgChan)
}
