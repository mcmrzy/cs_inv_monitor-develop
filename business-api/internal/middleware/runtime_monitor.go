package middleware

import (
	"context"
	"errors"
	"regexp"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"go.uber.org/zap"
)

type RuntimeErrorRecorder interface {
	Record(context.Context, model.RuntimeErrorEvent) error
}

// Only an identifier in a known PostgreSQL diagnostic is retained. Detail,
// arbitrary messages and application values may contain credentials or user data.
var missingDBObject = regexp.MustCompile(`^(?:column|relation) "?([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)"? does not exist$`)

func classifyRuntimeError(err error) (kind, state, summary string) {
	kind, summary = "internal", "Internal server error"
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		kind, state, summary = "database", pgErr.Code, "Database operation failed"
		if state == "42703" || state == "42P01" {
			kind, summary = "missing_column", "Database column missing"
			if state == "42P01" {
				kind, summary = "missing_table", "Database table missing"
			}
			if match := missingDBObject.FindStringSubmatch(pgErr.Message); len(match) == 2 {
				summary += ": " + match[1]
			}
		}
	} else if errors.Is(err, context.DeadlineExceeded) {
		kind, summary = "timeout", "Operation timed out"
	}
	return
}

// RuntimeMonitor must wrap recovery so recovered panics are observable. Saving
// diagnostic history is bounded and never replaces or changes the API response.
func RuntimeMonitor(recorder RuntimeErrorRecorder) gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := uuid.NewString()
		c.Header("X-Request-ID", requestID)
		c.Set("request_id", requestID)
		started := time.Now()
		c.Next()
		status := c.Writer.Status()
		code := c.GetInt(response.RuntimeErrorCodeKey)
		panicked := c.GetBool("runtime_panic")
		if !panicked && status < 500 && (code < 500 || code > 599) {
			return
		}
		if status >= 500 {
			code = status
		}
		var cause error
		if last := c.Errors.Last(); last != nil {
			cause = last.Err
		}
		kind, state, summary := classifyRuntimeError(cause)
		if panicked {
			code = 500
			kind, state, summary = "panic", "", "Request panicked"
		}
		route := c.FullPath()
		if route == "" {
			route = "<unmatched>"
		}
		event := model.RuntimeErrorEvent{RequestID: requestID, Service: "business-api", Method: c.Request.Method,
			Route: route, Status: code, HTTPStatus: status, DurationMS: time.Since(started).Milliseconds(),
			Kind: kind, SQLState: state, Summary: summary, OccurredAt: time.Now().UTC()}
		logger.Error("API runtime failure", zap.String("request_id", requestID), zap.String("route", route),
			zap.String("method", event.Method), zap.Int("status", code), zap.String("kind", kind),
			zap.String("sql_state", state), zap.String("summary", summary))
		ctx, cancel := context.WithTimeout(context.WithoutCancel(c.Request.Context()), 200*time.Millisecond)
		defer cancel()
		if err := recorder.Record(ctx, event); err != nil {
			logger.Warn("Runtime error history write failed", zap.String("request_id", requestID))
		}
	}
}
