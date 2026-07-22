package service

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func fastRetryConfig(maxRetries int) RetryConfig {
	return RetryConfig{
		MaxRetries:       maxRetries,
		BaseDelay:        1e6, // 1ms in nanoseconds
		MaxDelay:         5e6, // 5ms in nanoseconds
		RetryStatusCodes: map[int]bool{500: true, 502: true, 503: true, 504: true},
	}
}

func TestRetryHTTPPost_SuccessOnFirstAttempt(t *testing.T) {
	var attempts int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&attempts, 1)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	resp, err := retryHTTPPost(context.Background(), http.DefaultClient, srv.URL, []byte(`{}`), "", fastRetryConfig(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Errorf("expected status 200, got %d", resp.StatusCode)
	}
	if atomic.LoadInt32(&attempts) != 1 {
		t.Errorf("expected 1 attempt, got %d", atomic.LoadInt32(&attempts))
	}
}

func TestRetryHTTPPost_RetryOn500(t *testing.T) {
	var attempts int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt32(&attempts, 1)
		if n == 1 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	resp, err := retryHTTPPost(context.Background(), http.DefaultClient, srv.URL, []byte(`{}`), "", fastRetryConfig(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Errorf("expected status 200, got %d", resp.StatusCode)
	}
	if atomic.LoadInt32(&attempts) != 2 {
		t.Errorf("expected 2 attempts, got %d", atomic.LoadInt32(&attempts))
	}
}

func TestRetryHTTPPost_NoRetryOn400(t *testing.T) {
	var attempts int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&attempts, 1)
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer srv.Close()

	_, err := retryHTTPPost(context.Background(), http.DefaultClient, srv.URL, []byte(`{}`), "", fastRetryConfig(3))
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	var httpErr *downstreamHTTPError
	if !errors.As(err, &httpErr) {
		t.Fatalf("expected *downstreamHTTPError, got %T", err)
	}
	if httpErr.status != 400 {
		t.Errorf("expected status 400, got %d", httpErr.status)
	}
	if atomic.LoadInt32(&attempts) != 1 {
		t.Errorf("expected 1 attempt, got %d", atomic.LoadInt32(&attempts))
	}
}

func TestRetryHTTPPost_ExhaustedRetries(t *testing.T) {
	var attempts int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&attempts, 1)
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	_, err := retryHTTPPost(context.Background(), http.DefaultClient, srv.URL, []byte(`{}`), "", fastRetryConfig(2))
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if atomic.LoadInt32(&attempts) != 2 {
		t.Errorf("expected 2 attempts, got %d", atomic.LoadInt32(&attempts))
	}
}
