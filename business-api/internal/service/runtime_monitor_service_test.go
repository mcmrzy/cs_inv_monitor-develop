package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
)

type runtimeStoreStub struct {
	events    []model.RuntimeErrorEvent
	err       error
	checks    []model.SchemaColumnCheck
	schemaErr error
}

func (s runtimeStoreStub) Record(context.Context, model.RuntimeErrorEvent) error { return s.err }
func (s runtimeStoreStub) Recent(context.Context) ([]model.RuntimeErrorEvent, error) {
	return s.events, s.err
}
func (s runtimeStoreStub) SchemaColumns(context.Context) ([]model.SchemaColumnCheck, error) {
	return s.checks, s.schemaErr
}

func TestRuntimeSnapshotAggregatesAndRejectsExpiredEvents(t *testing.T) {
	now := time.Now().UTC()
	e := model.RuntimeErrorEvent{Service: "business-api", Method: "GET", Route: "/api/v1/stations/:id", Status: 500, Kind: "missing_column", Summary: "Missing column: l.ac_input_power", OccurredAt: now, RequestID: "new"}
	older := e
	older.OccurredAt = now.Add(-2 * time.Minute)
	older.RequestID = "older"
	expired := e
	expired.OccurredAt = now.Add(-25 * time.Hour)
	s := NewRuntimeMonitorService(runtimeStoreStub{events: []model.RuntimeErrorEvent{older, expired, e}, checks: []model.SchemaColumnCheck{{Table: "device_latest_state", Column: "ac_input_power", Status: "missing"}}})
	result := s.Snapshot(context.Background())
	require.Equal(t, "ok", result.ErrorsStatus)
	require.Equal(t, 2, *result.Errors5m)
	require.Equal(t, 2, *result.EventsRetained)
	require.Len(t, result.Groups, 1)
	require.Equal(t, 2, result.Groups[0].Count)
	require.Equal(t, "new", result.Groups[0].RequestID)
	require.True(t, result.Groups[0].FirstSeen.Equal(older.OccurredAt))
	require.Equal(t, "degraded", result.Schema.Status)
}

func TestRuntimeSnapshotDoesNotCallUnavailableZeroOrHealthy(t *testing.T) {
	s := NewRuntimeMonitorService(runtimeStoreStub{err: errors.New("Redis unavailable"), schemaErr: errors.New("db unavailable")})
	result := s.Snapshot(context.Background())
	require.Equal(t, "unknown", result.ErrorsStatus)
	require.Nil(t, result.Errors5m)
	require.Nil(t, result.EventsRetained)
	require.Equal(t, "unknown", result.Schema.Status)
	require.Empty(t, result.Groups)
}
