package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/segmentio/kafka-go"
)

// ---------------------------------------------------------------------------
// KafkaHealthProbe tests
// ---------------------------------------------------------------------------

func TestKafkaHealthProbe_ConsecutiveFailures(t *testing.T) {
	probe := newKafkaHealthProbe(3)

	// Initially connected
	if !probe.IsConnected() {
		t.Fatal("probe should be connected initially")
	}

	// 2 failures — still connected
	for i := 0; i < 2; i++ {
		probe.check(func() error { return errors.New("fail") })
	}
	if !probe.IsConnected() {
		t.Fatal("probe should still be connected after 2 failures")
	}

	// 3rd failure — crosses threshold
	probe.check(func() error { return errors.New("fail") })
	if probe.IsConnected() {
		t.Fatal("probe should be disconnected after 3 consecutive failures")
	}
}

func TestKafkaHealthProbe_RecoveryAfterFailure(t *testing.T) {
	probe := newKafkaHealthProbe(3)

	// Drive to disconnected
	for i := 0; i < 3; i++ {
		probe.check(func() error { return errors.New("fail") })
	}
	if probe.IsConnected() {
		t.Fatal("should be disconnected")
	}

	// One success should recover
	probe.check(func() error { return nil })
	if !probe.IsConnected() {
		t.Fatal("should recover after one success")
	}
}

// ---------------------------------------------------------------------------
// /health endpoint tests
// ---------------------------------------------------------------------------

func newTestBridge() *KafkaBridge {
	cfg := &Config{}
	cfg.Server.Timeout = 30
	cfg.Kafka.TelemetryTopic = "test-telemetry"
	cfg.Kafka.AlarmTopic = "test-alarms"
	bridge := &KafkaBridge{
		cfg:       cfg,
		probe:     newKafkaHealthProbe(3),
		startTime: time.Now().Add(-100 * time.Second),
	}
	bridge.stats.messagesIn.Add(1234)
	bridge.stats.messagesOut.Add(1230)
	bridge.stats.errors.Add(4)
	return bridge
}

func TestHealthEndpoint_StructuredJSON(t *testing.T) {
	bridge := newTestBridge()
	mux := http.NewServeMux()
	mux.HandleFunc("/health", bridge.handleHealth)

	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var body map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}

	requiredFields := []string{"status", "kafka", "messages_in", "messages_out", "errors", "uptime_seconds"}
	for _, f := range requiredFields {
		if _, ok := body[f]; !ok {
			t.Errorf("missing field %q in /health response", f)
		}
	}

	if body["status"] != "ok" {
		t.Errorf("status = %v, want ok", body["status"])
	}
	if body["kafka"] != "connected" {
		t.Errorf("kafka = %v, want connected", body["kafka"])
	}
}

func TestHealthEndpoint_DownStatus(t *testing.T) {
	bridge := newTestBridge()

	// Drive probe to disconnected state
	for i := 0; i < 3; i++ {
		bridge.probe.check(func() error { return errors.New("fail") })
	}
	// Mark disconnect time in the past (>90s) so status = "down"
	bridge.probe.disconnectedAt.Store(time.Now().Add(-120 * time.Second))

	mux := http.NewServeMux()
	mux.HandleFunc("/health", bridge.handleHealth)

	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 for down status, got %d", w.Code)
	}

	var body map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &body)
	if body["status"] != "down" {
		t.Errorf("status = %v, want down", body["status"])
	}
	if body["kafka"] != "disconnected" {
		t.Errorf("kafka = %v, want disconnected", body["kafka"])
	}
}

// ---------------------------------------------------------------------------
// /metrics endpoint tests
// ---------------------------------------------------------------------------

func TestMetricsEndpoint_PrometheusFormat(t *testing.T) {
	bridge := newTestBridge()
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", bridge.handleMetrics)

	req := httptest.NewRequest("GET", "/metrics", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	ct := w.Header().Get("Content-Type")
	if !strings.HasPrefix(ct, "text/plain") {
		t.Errorf("Content-Type = %s, want text/plain", ct)
	}

	body := w.Body.String()
	requiredMetrics := []string{
		"bridge_messages_received_total",
		"bridge_messages_forwarded_total",
		"bridge_errors_total",
		"bridge_kafka_connected",
	}
	for _, m := range requiredMetrics {
		if !strings.Contains(body, m) {
			t.Errorf("missing metric %q in /metrics response", m)
		}
	}

	// Verify HELP/TYPE comments exist
	if !strings.Contains(body, "# HELP bridge_messages_received_total") {
		t.Error("missing HELP for bridge_messages_received_total")
	}
	if !strings.Contains(body, "# TYPE bridge_messages_received_total counter") {
		t.Error("missing TYPE for bridge_messages_received_total")
	}
	if !strings.Contains(body, "# TYPE bridge_kafka_connected gauge") {
		t.Error("missing TYPE for bridge_kafka_connected")
	}
}

// ---------------------------------------------------------------------------
// Test helper types
// ---------------------------------------------------------------------------

// brokenKafkaWriter simulates a kafka.Writer that panics on Stats()
type brokenKafkaWriter struct{}

func (b *brokenKafkaWriter) WriteMessages(context.Context, ...kafka.Message) error {
	return errors.New("kafka unavailable")
}
func (b *brokenKafkaWriter) Close() error { return nil }
func (b *brokenKafkaWriter) Stats() kafka.WriterStats {
	panic("writer is broken")
}
