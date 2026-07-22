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
