package main

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/segmentio/kafka-go"
)

func TestStats_ConcurrentSafety(t *testing.T) {
	var s stats
	const goroutines = 1000

	var wg sync.WaitGroup
	wg.Add(goroutines * 3)

	// Concurrent incIn
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			s.incIn()
		}()
	}

	// Concurrent incOut
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			s.incOut(1)
		}()
	}

	// Concurrent incErr
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			s.incErr()
		}()
	}

	wg.Wait()

	if got := s.messagesIn.Load(); got != goroutines {
		t.Errorf("messagesIn = %d, want %d", got, goroutines)
	}
	if got := s.messagesOut.Load(); got != goroutines {
		t.Errorf("messagesOut = %d, want %d", got, goroutines)
	}
	if got := s.errors.Load(); got != goroutines {
		t.Errorf("errors = %d, want %d", got, goroutines)
	}

	// Verify lastMessageAt was set
	lma := s.lastMessageAt.Load()
	if lma == nil {
		t.Error("lastMessageAt should not be nil after incIn")
	} else {
		ts := lma.(time.Time)
		if ts.IsZero() {
			t.Error("lastMessageAt should not be zero after incIn")
		}
	}
}

// mockMessageWriter is a no-op messageWriter used in webhook handler tests.
type mockMessageWriter struct{}

func (mockMessageWriter) WriteMessages(_ context.Context, _ ...kafka.Message) error { return nil }
func (mockMessageWriter) Close() error                                              { return nil }

// recordingWriter captures forwarded messages for assertion.
type recordingWriter struct {
	mu       sync.Mutex
	messages []kafka.Message
}

func (w *recordingWriter) WriteMessages(_ context.Context, msgs ...kafka.Message) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.messages = append(w.messages, msgs...)
	return nil
}
func (w *recordingWriter) Close() error { return nil }

func (w *recordingWriter) len() int {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.messages)
}

func (w *recordingWriter) first() kafka.Message {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.messages[0]
}

func TestWebhook_Authentication(t *testing.T) {
	bridge := newTestBridge()
	bridge.cfg.EMQX.Token = "secret"
	bridge.telemetryWriter = mockMessageWriter{}
	bridge.alarmWriter = mockMessageWriter{}

	payload := `{"clientid":"c1","topic":"inv/SN001/telemetry","payload":"{}"}`

	t.Run("missing token is rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(payload))
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rr.Code)
		}
	})

	t.Run("wrong token is rejected", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(payload))
		req.Header.Set("Authorization", "Bearer wrong")
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code != http.StatusUnauthorized {
			t.Errorf("status = %d, want 401", rr.Code)
		}
	})

	t.Run("bearer token accepted", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(payload))
		req.Header.Set("Authorization", "Bearer secret")
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code == http.StatusUnauthorized {
			t.Errorf("valid bearer token rejected with 401")
		}
	})

	t.Run("raw token accepted", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(payload))
		req.Header.Set("Authorization", "secret")
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code == http.StatusUnauthorized {
			t.Errorf("valid raw token rejected with 401")
		}
	})
}

func TestWebhook_MethodNotAllowed(t *testing.T) {
	bridge := newTestBridge()
	bridge.telemetryWriter = mockMessageWriter{}
	bridge.alarmWriter = mockMessageWriter{}

	req := httptest.NewRequest(http.MethodGet, "/webhook", nil)
	rr := httptest.NewRecorder()
	bridge.handleWebhook(rr, req)
	if rr.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want 405", rr.Code)
	}
}

func TestWebhook_InvalidJSON(t *testing.T) {
	bridge := newTestBridge()
	bridge.telemetryWriter = mockMessageWriter{}
	bridge.alarmWriter = mockMessageWriter{}

	req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader("{not json"))
	rr := httptest.NewRecorder()
	bridge.handleWebhook(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", rr.Code)
	}
}

func TestWebhook_InvalidTopic(t *testing.T) {
	bridge := newTestBridge()
	bridge.telemetryWriter = mockMessageWriter{}
	bridge.alarmWriter = mockMessageWriter{}

	// Topic without an SN part
	req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(`{"topic":"inv"}`))
	rr := httptest.NewRecorder()
	bridge.handleWebhook(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", rr.Code)
	}
}

func TestWebhook_KafkaError(t *testing.T) {
	bridge := newTestBridge()
	bridge.telemetryWriter = &brokenKafkaWriter{}
	bridge.alarmWriter = mockMessageWriter{}

	req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(`{"clientid":"c1","topic":"inv/SN001/telemetry","payload":"{}"}`))
	rr := httptest.NewRecorder()
	bridge.handleWebhook(rr, req)
	if rr.Code != http.StatusBadGateway {
		t.Errorf("status = %d, want 502", rr.Code)
	}
}

func TestWebhook_RoutesAlarmTopicToAlarmWriter(t *testing.T) {
	telemetryWriter := &recordingWriter{}
	alarmWriter := &recordingWriter{}
	bridge := newTestBridge()
	bridge.telemetryWriter = telemetryWriter
	bridge.alarmWriter = alarmWriter

	t.Run("telemetry message goes to telemetry writer", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(`{"clientid":"c1","topic":"inv/SN001/telemetry","payload":"{\"a\":1}","qos":1}`))
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code != http.StatusNoContent {
			t.Fatalf("status = %d, want 204", rr.Code)
		}
		if telemetryWriter.len() != 1 || alarmWriter.len() != 0 {
			t.Fatalf("telemetry routed wrong: tele=%d alarm=%d", telemetryWriter.len(), alarmWriter.len())
		}
		msg := telemetryWriter.first()
		if string(msg.Key) != "SN001" {
			t.Errorf("key = %s, want SN001", msg.Key)
		}
	})

	t.Run("alarm message goes to alarm writer", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(`{"clientid":"c1","topic":"inv/SN001/alarm","payload":"{\"level\":\"critical\"}"}`))
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code != http.StatusNoContent {
			t.Fatalf("status = %d, want 204", rr.Code)
		}
		if alarmWriter.len() != 1 || telemetryWriter.len() != 1 {
			t.Fatalf("alarm routed wrong: tele=%d alarm=%d", telemetryWriter.len(), alarmWriter.len())
		}
	})

	t.Run("nested data/alarm topic also routes to alarm writer", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(`{"clientid":"c1","topic":"inv/SN001/data/alarm","payload":"{}"}`))
		rr := httptest.NewRecorder()
		bridge.handleWebhook(rr, req)
		if rr.Code != http.StatusNoContent {
			t.Fatalf("status = %d, want 204", rr.Code)
		}
		if alarmWriter.len() != 2 {
			t.Errorf("alarm count = %d, want 2", alarmWriter.len())
		}
	})
}

func TestWebhook_MaxBodySize(t *testing.T) {
	bridge := newTestBridge()
	bridge.telemetryWriter = mockMessageWriter{}
	bridge.alarmWriter = mockMessageWriter{}

	t.Run("oversized body returns 413", func(t *testing.T) {
		// Build a valid JSON body that exceeds 1MB (valid JSON so the decoder
		// reads enough bytes to trigger MaxBytesReader rather than failing on
		// a syntax error first).
		padding := bytes.Repeat([]byte("a"), 1<<20+1)
		body := append([]byte(`{"payload":"`), padding...)
		body = append(body, '"', '}')
		req := httptest.NewRequest(http.MethodPost, "/webhook", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rr := httptest.NewRecorder()

		bridge.handleWebhook(rr, req)

		if rr.Code != http.StatusRequestEntityTooLarge {
			t.Errorf("status = %d, want %d", rr.Code, http.StatusRequestEntityTooLarge)
		}
		if !strings.Contains(rr.Body.String(), "too large") {
			t.Errorf("body = %q, want substring 'too large'", rr.Body.String())
		}
	})

	t.Run("normal body does not return 413", func(t *testing.T) {
		payload := `{"clientid":"c1","username":"u1","topic":"device/SN001/telemetry","payload":"{}","qos":0,"ts":1700000000}`
		req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(payload))
		req.Header.Set("Content-Type", "application/json")
		rr := httptest.NewRecorder()

		bridge.handleWebhook(rr, req)

		if rr.Code == http.StatusRequestEntityTooLarge {
			t.Errorf("normal request should not be rejected with 413, got %d", rr.Code)
		}
	})
}
