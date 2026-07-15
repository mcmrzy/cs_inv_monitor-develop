package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type fakeProtocolV1Store struct {
	alarmRecords      []protocolV1Record
	parallelRecords   []protocolV1Record
	threePhaseRecords []protocolV1Record
	allowAccess       bool
	accessErr         error
	accessChecks      int
	alarmResult       protocolV1Result
	parallelResult    protocolV1Result
	threePhaseResult  protocolV1Result
	parallelErr       error
}

func (f *fakeProtocolV1Store) IngestAlarm(_ context.Context, record protocolV1Record, _ alarmV1Data) (protocolV1Result, error) {
	f.alarmRecords = append(f.alarmRecords, record)
	if f.alarmResult == (protocolV1Result{}) {
		return protocolV1Result{ID: 11}, nil
	}
	return f.alarmResult, nil
}

func (f *fakeProtocolV1Store) IngestParallel(_ context.Context, record protocolV1Record, _ parallelV1Data) (protocolV1Result, error) {
	f.parallelRecords = append(f.parallelRecords, record)
	if f.parallelErr != nil {
		return protocolV1Result{}, f.parallelErr
	}
	if f.parallelResult == (protocolV1Result{}) {
		return protocolV1Result{ID: 12}, nil
	}
	return f.parallelResult, nil
}

func TestParallelMemberOwnershipFailureReturnsBadRequest(t *testing.T) {
	store := &fakeProtocolV1Store{parallelErr: errProtocolParallelMember}
	r := protocolV1TestRouter(store)
	body := protocolRequest("INV001", "parallel", map[string]any{
		"enabled": true, "mode": "single_phase", "count": 1,
		"total_rated_power": 6200, "total_active_power": 10, "sync_state": "synced",
		"machines": []any{map[string]any{"id": 0, "sn": "INV001", "role": "master", "phase": nil, "power": 10, "state": 2}},
	})
	w := sendProtocolV1(t, r, "/parallel", body)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestMissingAlarmSnapshotDiagnostic(t *testing.T) {
	var value map[string]any
	if err := json.Unmarshal(missingAlarmSnapshotJSON(), &value); err != nil {
		t.Fatal(err)
	}
	if value["missing"] != true || value["reason"] != "device_latest_state_not_found" {
		t.Fatalf("unexpected diagnostic snapshot: %#v", value)
	}
}

func (f *fakeProtocolV1Store) IngestThreePhase(_ context.Context, record protocolV1Record, _ threePhaseV1Data) (protocolV1Result, error) {
	f.threePhaseRecords = append(f.threePhaseRecords, record)
	if f.threePhaseResult == (protocolV1Result{}) {
		return protocolV1Result{ID: 13}, nil
	}
	return f.threePhaseResult, nil
}

func (f *fakeProtocolV1Store) HasDeviceAccess(_ context.Context, _ int64, _ string) (bool, error) {
	f.accessChecks++
	return f.allowAccess, f.accessErr
}

func protocolV1TestRouter(store protocolV1Store) *gin.Engine {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.protocolV1 = store
	r := gin.New()
	r.POST("/alarm", h.IngestAlarmV1)
	r.POST("/parallel", h.IngestParallelV1)
	r.POST("/three-phase", h.IngestThreePhaseV1)
	return r
}

func sendProtocolV1(t *testing.T, r http.Handler, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func protocolRequest(sn, topic string, data any) map[string]any {
	return map[string]any{
		"sn":          sn,
		"topic":       topic,
		"received_at": "2026-07-14T10:00:05Z",
		"envelope": map[string]any{
			"t":    int64(1784023200),
			"v":    1,
			"data": data,
		},
	}
}

func TestProtocolV1WriteEndpointsAcceptUnifiedEnvelope(t *testing.T) {
	store := &fakeProtocolV1Store{}
	r := protocolV1TestRouter(store)

	alarm := protocolRequest("INV001", "cs_inv/INV001/alarm", map[string]any{
		"source": 1, "code": 8, "level": 2, "state": 1,
	})
	if w := sendProtocolV1(t, r, "/alarm", alarm); w.Code != http.StatusOK {
		t.Fatalf("alarm status=%d body=%s", w.Code, w.Body.String())
	}

	parallel := protocolRequest("INV001", "parallel", map[string]any{
		"enabled": true, "mode": "single_phase", "count": 1,
		"total_rated_power": 6200, "total_active_power": 1200.5, "sync_state": "synced",
		"machines": []any{map[string]any{
			"id": 0, "sn": "INV001", "role": "master", "phase": nil, "power": 1200.5, "state": 2,
		}},
	})
	if w := sendProtocolV1(t, r, "/parallel", parallel); w.Code != http.StatusOK {
		t.Fatalf("parallel status=%d body=%s", w.Code, w.Body.String())
	}

	threePhase := protocolRequest("INV001", "three_phase", map[string]any{
		"voltage": []float64{220.1, 219.9, 220.2}, "current": []float64{8.1, 8.0, 8.2},
		"active_power": []float64{1750, 1735, 1770}, "total_active_power": 5255,
		"line_voltage": []float64{381, 380.6, 381.3}, "frequency": 50.01,
		"voltage_unbalance": 0.3, "current_unbalance": 0.8,
	})
	if w := sendProtocolV1(t, r, "/three-phase", threePhase); w.Code != http.StatusOK {
		t.Fatalf("three-phase status=%d body=%s", w.Code, w.Body.String())
	}

	if len(store.alarmRecords) != 1 || len(store.parallelRecords) != 1 || len(store.threePhaseRecords) != 1 {
		t.Fatalf("unexpected writes: alarm=%d parallel=%d three_phase=%d", len(store.alarmRecords), len(store.parallelRecords), len(store.threePhaseRecords))
	}
	if got := store.alarmRecords[0]; got.Topic != "alarm" || got.Timestamp != 1784023200 || got.Version != 1 || len(got.DataHash) != 64 {
		t.Fatalf("unexpected normalized alarm record: %+v", got)
	}
	if !store.alarmRecords[0].ReceivedAt.Equal(time.Date(2026, 7, 14, 10, 0, 5, 0, time.UTC)) {
		t.Fatalf("received_at was not preserved: %s", store.alarmRecords[0].ReceivedAt)
	}
}

func TestProtocolV1WriteEndpointsRejectInvalidPayloads(t *testing.T) {
	store := &fakeProtocolV1Store{}
	r := protocolV1TestRouter(store)
	tests := []struct {
		name string
		path string
		body any
	}{
		{"missing received_at", "/alarm", map[string]any{"sn": "INV001", "topic": "alarm", "envelope": map[string]any{"t": 1, "v": 1, "data": map[string]any{"source": 1, "code": 8, "level": 2, "state": 1}}}},
		{"invalid sn characters", "/alarm", protocolRequest("INV 001", "alarm", map[string]any{"source": 1, "code": 8, "level": 2, "state": 1})},
		{"wrong topic sn", "/alarm", protocolRequest("INV001", "cs_inv/OTHER/alarm", map[string]any{"source": 1, "code": 8, "level": 2, "state": 1})},
		{"missing alarm state", "/alarm", protocolRequest("INV001", "alarm", map[string]any{"source": 1, "code": 8, "level": 2})},
		{"alarm source out of range", "/alarm", protocolRequest("INV001", "alarm", map[string]any{"source": 4, "code": 8, "level": 2, "state": 1})},
		{"parallel count mismatch", "/parallel", protocolRequest("INV001", "parallel", map[string]any{"enabled": true, "mode": "single_phase", "count": 2, "total_rated_power": 6200, "total_active_power": 1, "sync_state": "synced", "machines": []any{}})},
		{"parallel missing enabled", "/parallel", protocolRequest("INV001", "parallel", map[string]any{"mode": "standalone", "count": 0, "total_rated_power": 0, "total_active_power": 0, "sync_state": "idle", "machines": []any{}})},
		{"parallel missing machine phase", "/parallel", protocolRequest("INV001", "parallel", map[string]any{"enabled": true, "mode": "single_phase", "count": 1, "total_rated_power": 6200, "total_active_power": 10, "sync_state": "synced", "machines": []any{map[string]any{"id": 0, "sn": "INV001", "role": "master", "power": 10, "state": 2}}})},
		{"parallel ids not ascending", "/parallel", protocolRequest("INV001", "parallel", map[string]any{"enabled": true, "mode": "single_phase", "count": 2, "total_rated_power": 12400, "total_active_power": 20, "sync_state": "synced", "machines": []any{map[string]any{"id": 1, "sn": "INV002", "role": "slave", "phase": nil, "power": 10, "state": 2}, map[string]any{"id": 0, "sn": "INV001", "role": "master", "phase": nil, "power": 10, "state": 2}}})},
		{"parallel bad machine state", "/parallel", protocolRequest("INV001", "parallel", map[string]any{"enabled": true, "mode": "single_phase", "count": 1, "total_rated_power": 6200, "total_active_power": 10, "sync_state": "synced", "machines": []any{map[string]any{"id": 0, "sn": "INV001", "role": "master", "phase": nil, "power": 10, "state": 1}}})},
		{"parallel power mismatch", "/parallel", protocolRequest("INV001", "parallel", map[string]any{"enabled": true, "mode": "single_phase", "count": 1, "total_rated_power": 6200, "total_active_power": 100, "sync_state": "synced", "machines": []any{map[string]any{"id": 0, "sn": "INV001", "role": "master", "phase": nil, "power": 10, "state": 2}}})},
		{"three phase short array", "/three-phase", protocolRequest("INV001", "three_phase", map[string]any{"voltage": []float64{220, 220}, "current": []float64{1, 1, 1}, "active_power": []float64{1, 1, 1}, "total_active_power": 3, "line_voltage": []float64{380, 380, 380}, "frequency": 50, "voltage_unbalance": 0, "current_unbalance": 0})},
		{"three phase missing frequency", "/three-phase", protocolRequest("INV001", "three_phase", map[string]any{"voltage": []float64{220, 220, 220}, "current": []float64{1, 1, 1}, "active_power": []float64{1, 1, 1}, "total_active_power": 3, "line_voltage": []float64{380, 380, 380}, "voltage_unbalance": 0, "current_unbalance": 0})},
		{"three phase power mismatch", "/three-phase", protocolRequest("INV001", "three_phase", map[string]any{"voltage": []float64{220, 220, 220}, "current": []float64{1, 1, 1}, "active_power": []float64{100, 100, 100}, "total_active_power": 500, "line_voltage": []float64{380, 380, 380}, "frequency": 50, "voltage_unbalance": 0, "current_unbalance": 0})},
		{"three phase negative phase power", "/three-phase", protocolRequest("INV001", "three_phase", map[string]any{"voltage": []float64{220, 220, 220}, "current": []float64{1, 1, 1}, "active_power": []float64{-1, 2, 2}, "total_active_power": 3, "line_voltage": []float64{380, 380, 380}, "frequency": 50, "voltage_unbalance": 0, "current_unbalance": 0})},
		{"unknown envelope field", "/alarm", map[string]any{"sn": "INV001", "topic": "alarm", "received_at": "2026-07-14T10:00:05Z", "envelope": map[string]any{"t": 1, "v": 1, "extra": true, "data": map[string]any{"source": 1, "code": 8, "level": 2, "state": 1}}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := sendProtocolV1(t, r, tt.path, tt.body)
			if w.Code < 400 || w.Code >= 500 {
				t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
			}
		})
	}
	if len(store.alarmRecords)+len(store.parallelRecords)+len(store.threePhaseRecords) != 0 {
		t.Fatal("invalid payload reached persistence store")
	}
}

func TestCanonicalJSONHashIgnoresObjectOrderAndEquivalentNumbers(t *testing.T) {
	a, err := canonicalJSONHash([]byte(`{"b":1.0,"a":{"y":2,"x":3},"z":-0.0}`))
	if err != nil {
		t.Fatal(err)
	}
	b, err := canonicalJSONHash([]byte(`{"z":0,"a":{"x":3.0,"y":2.0},"b":1}`))
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatalf("canonical hashes differ: %s != %s", a, b)
	}
}

func TestProtocolQueriesRejectCrossTenantDevice(t *testing.T) {
	store := &fakeProtocolV1Store{allowAccess: false}
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.protocolV1 = store
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1001))
		c.Set("role", 3)
		c.Next()
	})
	r.GET("/devices/:sn/alarm-events", h.GetAlarmEvents)
	r.GET("/devices/:sn/parallel-state", h.GetParallelState)
	r.GET("/devices/:sn/three-phase", h.GetThreePhaseHistory)

	for _, path := range []string{
		"/devices/OTHER/alarm-events",
		"/devices/OTHER/parallel-state",
		"/devices/OTHER/three-phase",
	} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		if w.Code != http.StatusForbidden {
			t.Fatalf("path=%s status=%d body=%s", path, w.Code, w.Body.String())
		}
	}
	if store.accessChecks != 3 {
		t.Fatalf("access checks=%d, want 3", store.accessChecks)
	}
}

func TestProtocolQueryAccessDatabaseErrorIsExplicit(t *testing.T) {
	store := &fakeProtocolV1Store{accessErr: errors.New("database unavailable")}
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.protocolV1 = store
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1001))
		c.Set("role", 3)
		c.Next()
	})
	r.GET("/devices/:sn/parallel-state", h.GetParallelState)

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/devices/INV001/parallel-state", nil))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	if store.accessChecks != 1 {
		t.Fatalf("access checks=%d, want 1", store.accessChecks)
	}
}

func TestProtocolQueryRoleZeroBypassesObjectAccessCheck(t *testing.T) {
	store := &fakeProtocolV1Store{allowAccess: false}
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.protocolV1 = store
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Set("role", 0)
		c.Next()
	})
	r.GET("/access", func(c *gin.Context) {
		if h.ensureDeviceAccess(c, "INV001") {
			c.Status(http.StatusNoContent)
		}
	})

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/access", nil))
	if w.Code != http.StatusNoContent {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	if store.accessChecks != 0 {
		t.Fatalf("role 0 should bypass object lookup, checks=%d", store.accessChecks)
	}
}

func TestProtocolWriteResponseReportsDuplicateAndOutOfOrder(t *testing.T) {
	store := &fakeProtocolV1Store{alarmResult: protocolV1Result{ID: 21, Duplicate: true}}
	r := protocolV1TestRouter(store)
	body := protocolRequest("INV001", "alarm", map[string]any{"source": 1, "code": 8, "level": 2, "state": 1})
	w := sendProtocolV1(t, r, "/alarm", body)
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var payload struct {
		Data struct {
			Duplicate  bool `json:"duplicate"`
			OutOfOrder bool `json:"out_of_order"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if !payload.Data.Duplicate || payload.Data.OutOfOrder {
		t.Fatalf("unexpected result: %+v", payload.Data)
	}

	store.alarmResult = protocolV1Result{ID: 22, OutOfOrder: true}
	w = sendProtocolV1(t, r, "/alarm", body)
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Data.Duplicate || !payload.Data.OutOfOrder {
		t.Fatalf("unexpected out-of-order result: %+v", payload.Data)
	}
}

type stubRow struct {
	scan func(...any) error
}

func (r stubRow) Scan(dest ...any) error { return r.scan(dest...) }

type stubHandlerDB struct {
	rows []pgx.Row
}

func (d *stubHandlerDB) Exec(context.Context, string, ...any) (pgconn.CommandTag, error) {
	return pgconn.CommandTag{}, errors.New("unexpected Exec")
}

func (d *stubHandlerDB) Query(context.Context, string, ...any) (pgx.Rows, error) {
	return nil, errors.New("unexpected Query")
}

func (d *stubHandlerDB) QueryRow(context.Context, string, ...any) pgx.Row {
	if len(d.rows) == 0 {
		return stubRow{scan: func(...any) error { return errors.New("unexpected QueryRow") }}
	}
	row := d.rows[0]
	d.rows = d.rows[1:]
	return row
}

func parallelQueryRouter(h *InternalHandler) *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Set("role", 0)
		c.Next()
	})
	r.GET("/devices/:sn/parallel-state", h.GetParallelState)
	r.GET("/devices/:sn/three-phase", h.GetThreePhaseHistory)
	return r
}

func TestGetParallelStateReturnsDatabaseError(t *testing.T) {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.db = &stubHandlerDB{rows: []pgx.Row{
		stubRow{scan: func(...any) error { return errors.New("database unavailable") }},
	}}
	r := parallelQueryRouter(h)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/devices/INV001/parallel-state", nil))
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestGetParallelStateDisabledDTO(t *testing.T) {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	reportedAt := time.Date(2026, 7, 14, 10, 0, 0, 0, time.UTC)
	h.db = &stubHandlerDB{rows: []pgx.Row{
		stubRow{scan: func(dest ...any) error {
			*dest[0].(*int64) = 7
			return nil
		}},
		stubRow{scan: func(dest ...any) error {
			*dest[0].(*string) = "INV001"
			*dest[1].(*bool) = false
			*dest[2].(*string) = "standalone"
			*dest[3].(*int) = 0
			*dest[4].(*int64) = 0
			*dest[5].(*float64) = 0
			*dest[6].(*string) = "idle"
			*dest[7].(*[]byte) = []byte("[]")
			*dest[8].(*time.Time) = reportedAt
			return nil
		}},
	}}
	r := parallelQueryRouter(h)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/devices/INV001/parallel-state", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var payload struct {
		Data struct {
			Enabled     bool `json:"enabled"`
			HasParallel bool `json:"has_parallel"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Data.Enabled || payload.Data.HasParallel {
		t.Fatalf("disabled topology was reported active: %+v", payload.Data)
	}
}

func TestProtocolQueryRejectsInvalidRFC3339Range(t *testing.T) {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	r := parallelQueryRouter(h)
	for _, query := range []string{
		"?start_time=not-a-time",
		"?start_time=2026-07-15T00:00:00Z&end_time=2026-07-14T00:00:00Z",
	} {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/devices/INV001/three-phase"+query, nil))
		if w.Code != http.StatusBadRequest {
			t.Fatalf("query=%s status=%d body=%s", query, w.Code, w.Body.String())
		}
	}
}
