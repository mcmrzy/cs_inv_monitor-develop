package service

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	"inv-device-server/pkg/logger"

	"go.uber.org/zap"
)

// RetryConfig holds retry behavior configuration.
type RetryConfig struct {
	MaxRetries       int
	BaseDelay        time.Duration
	MaxDelay         time.Duration
	RetryStatusCodes map[int]bool // status codes that trigger retry
}

// DefaultRetryConfig returns the standard retry configuration used across the codebase.
func DefaultRetryConfig() RetryConfig {
	return RetryConfig{
		MaxRetries: 3,
		BaseDelay:  500 * time.Millisecond,
		MaxDelay:   5 * time.Second,
		RetryStatusCodes: map[int]bool{
			500: true, // Internal Server Error
			502: true, // Bad Gateway
			503: true, // Service Unavailable
			504: true, // Gateway Timeout
		},
	}
}

// retryHTTPPost sends an HTTP POST request with retry logic using exponential backoff.
// It accepts an internal API key header which will be added if provided.
// Returns the response body and any error after exhausting retries.
//
// Non-retryable status codes (4xx) are returned immediately without retrying.
// Retryable status codes (5xx) trigger exponential backoff until MaxRetries is exhausted.
func retryHTTPPost(ctx context.Context, client *http.Client, url string, payload []byte, internalKey string, config RetryConfig) (*http.Response, error) {
	var lastErr error
	for attempt := 0; attempt < config.MaxRetries; attempt++ {
		if attempt > 0 {
			delay := min(config.BaseDelay<<uint(attempt-1), config.MaxDelay)
			select {
			case <-ctx.Done():
				return nil, fmt.Errorf("context cancelled before retry %d: %w", attempt+1, ctx.Err())
			case <-time.After(delay):
				logger.Debug("retrying POST request",
					zap.String("url", url),
					zap.Int("attempt", attempt+1),
					zap.Duration("delay", delay))
			}
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
		if err != nil {
			logger.Error("Failed to create POST request",
				zap.String("url", url),
				zap.Int("attempt", attempt+1),
				zap.Error(err))
			lastErr = err
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		if internalKey != "" {
			req.Header.Set("X-Internal-Key", internalKey)
		}

		resp, err := client.Do(req)
		if err != nil {
			logger.Warn("POST request failed, retrying",
				zap.String("url", url),
				zap.Int("attempt", attempt+1),
				zap.Error(err))
			lastErr = err
			continue
		}

		// Check if status code should trigger retry
		if config.RetryStatusCodes[resp.StatusCode] {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			logger.Warn("Received retryable status code, retrying",
				zap.String("url", url),
				zap.Int("attempt", attempt+1),
				zap.Int("status", resp.StatusCode),
				zap.String("body", string(body)))
			lastErr = fmt.Errorf("received status %d", resp.StatusCode)
			continue
		}

		// For 4xx errors, return immediately as non-retryable
		if resp.StatusCode >= 400 && resp.StatusCode < 500 {
			bodyBytes, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			return nil, &downstreamHTTPError{
				status: resp.StatusCode,
				body:   string(bodyBytes),
			}
		}

		// Success - return response for caller to handle
		return resp, nil
	}

	return nil, fmt.Errorf("POST request failed after %d attempts: %w", config.MaxRetries, lastErr)
}
