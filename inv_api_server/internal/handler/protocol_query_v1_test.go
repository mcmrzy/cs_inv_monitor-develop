package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func alarmEventDetailRouter(h *InternalHandler, role int) *gin.Engine {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1001))
		c.Set("role", role)
		c.Next()
	})
	r.GET("/alarm-events/:id", h.GetAlarmEventDetail)
	return r
}

func validAlarmEventRow() pgx.Row {
	return stubRow{scan: func(dest ...any) error {
		now := time.Date(2026, 7, 14, 10, 0, 0, 0, time.UTC)
		*dest[0].(*int64) = 41
		*dest[1].(*string) = "INV001"
		*dest[2].(*sql.NullInt64) = sql.NullInt64{Int64: 7, Valid: true}
		*dest[3].(*int16) = 1
		*dest[4].(*string) = "8"
		*dest[5].(*int16) = 2
		*dest[6].(*string) = "active"
		*dest[7].(*string) = "alarm"
		*dest[8].(*time.Time) = now
		*dest[9].(*int64) = now.Unix()
		*dest[10].(*sql.NullTime) = sql.NullTime{Time: now, Valid: true}
		*dest[11].(*sql.NullTime) = sql.NullTime{}
		*dest[12].(*time.Time) = now.Add(2 * time.Second)
		*dest[13].(*[]byte) = []byte(`{"t":1784023200,"v":1,"data":{"source":1,"code":8,"level":2,"state":1}}`)
		*dest[14].(*string) = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		*dest[15].(*time.Time) = now.Add(2 * time.Second)
		return nil
	}}
}

func TestGetAlarmEventDetailReturnsTraceAndNamedMissingSnapshot(t *testing.T) {
	store := &fakeProtocolV1Store{allowAccess: true}
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.protocolV1 = store
	h.db = &stubHandlerDB{rows: []pgx.Row{
		validAlarmEventRow(),
		stubRow{scan: func(dest ...any) error {
			*dest[0].(*[]byte) = []byte(`[{"id":91,"device_sn":"INV001","alarm_event_id":41,"snapshot_type":"before","raw_snapshot":{"missing":true,"reason":"device_latest_state_not_found"},"captured_at":"2026-07-14T10:00:01Z"}]`)
			return nil
		}},
	}}

	w := httptest.NewRecorder()
	alarmEventDetailRouter(h, 3).ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/alarm-events/41", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	var body struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if _, leaked := body.Data["raw_data"]; leaked {
		t.Fatal("raw_data must not be returned by the detail API")
	}
	if body.Data["device_sn"] != "INV001" || body.Data["raw_envelope"] == nil {
		t.Fatalf("event trace fields missing: %#v", body.Data)
	}
	snapshots, ok := body.Data["snapshots"].([]any)
	if !ok || len(snapshots) != 1 {
		t.Fatalf("unexpected snapshots: %#v", body.Data["snapshots"])
	}
	rawSnapshot := snapshots[0].(map[string]any)["raw_snapshot"].(map[string]any)
	if rawSnapshot["missing"] != true || rawSnapshot["reason"] != "device_latest_state_not_found" {
		t.Fatalf("missing diagnostic was not preserved: %#v", rawSnapshot)
	}
	if store.accessChecks != 1 {
		t.Fatalf("access checks=%d, want 1", store.accessChecks)
	}
}

func TestGetAlarmEventDetailNotFound(t *testing.T) {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.db = &stubHandlerDB{rows: []pgx.Row{
		stubRow{scan: func(...any) error { return pgx.ErrNoRows }},
	}}
	w := httptest.NewRecorder()
	alarmEventDetailRouter(h, 0).ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/alarm-events/999", nil))
	if w.Code != http.StatusNotFound {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestGetAlarmEventDetailRejectsCrossTenantBeforeSnapshots(t *testing.T) {
	store := &fakeProtocolV1Store{allowAccess: false}
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	h.protocolV1 = store
	h.db = &stubHandlerDB{rows: []pgx.Row{validAlarmEventRow()}}
	w := httptest.NewRecorder()
	alarmEventDetailRouter(h, 3).ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/alarm-events/41", nil))
	if w.Code != http.StatusForbidden {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	if len(h.db.(*stubHandlerDB).rows) != 0 {
		t.Fatal("unexpected database calls after authorization failure")
	}
}

func TestGetAlarmEventDetailDoesNotHideDatabaseOrJSONErrors(t *testing.T) {
	tests := []struct {
		name string
		rows []pgx.Row
	}{
		{
			name: "event database error",
			rows: []pgx.Row{stubRow{scan: func(...any) error { return errors.New("database unavailable") }}},
		},
		{
			name: "snapshot database error",
			rows: []pgx.Row{validAlarmEventRow(), stubRow{scan: func(...any) error { return errors.New("snapshot query failed") }}},
		},
		{
			name: "malformed snapshot JSON",
			rows: []pgx.Row{validAlarmEventRow(), stubRow{scan: func(dest ...any) error {
				*dest[0].(*[]byte) = []byte(`{"not":"an array"}`)
				return nil
			}}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
			h.protocolV1 = &fakeProtocolV1Store{allowAccess: true}
			h.db = &stubHandlerDB{rows: tt.rows}
			w := httptest.NewRecorder()
			alarmEventDetailRouter(h, 0).ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/alarm-events/41", nil))
			if w.Code != http.StatusInternalServerError {
				t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
			}
		})
	}
}

func TestGetAlarmEventDetailRejectsInvalidID(t *testing.T) {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	w := httptest.NewRecorder()
	alarmEventDetailRouter(h, 0).ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/alarm-events/not-a-number", nil))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
