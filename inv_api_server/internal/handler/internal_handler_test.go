package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func setupTestRouter() *gin.Engine {
	h := NewInternalHandler(nil, nil, nil, nil, nil, nil)
	r := gin.New()
	r.POST("/api/v1/internal/device-status", h.DeviceStatus)
	r.POST("/api/v1/internal/device-info", h.DeviceInfo)
	r.POST("/api/v1/internal/device-data", h.DeviceData)
	r.POST("/api/v1/internal/device-cmd-status", h.DeviceCmdStatus)
	r.POST("/api/v1/internal/alarm", h.DeviceAlarm)
	return r
}

func TestInternalDeviceStatus_Validation(t *testing.T) {
	r := setupTestRouter()

	tests := []struct {
		name       string
		body       interface{}
		wantStatus int
	}{
		{
			name:       "empty body",
			body:       nil,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "missing sn",
			body:       map[string]interface{}{"status": 1},
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "invalid json",
			body:       "not-json",
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var reqBody *bytes.Buffer
			if tt.body == nil {
				reqBody = bytes.NewBuffer(nil)
			} else if s, ok := tt.body.(string); ok {
				reqBody = bytes.NewBufferString(s)
			} else {
				b, _ := json.Marshal(tt.body)
				reqBody = bytes.NewBuffer(b)
			}

			req := httptest.NewRequest(http.MethodPost, "/api/v1/internal/device-status", reqBody)
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			r.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d, body: %s", w.Code, tt.wantStatus, w.Body.String())
			}
		})
	}
}

func TestInternalDeviceInfo_Validation(t *testing.T) {
	r := setupTestRouter()

	tests := []struct {
		name       string
		body       interface{}
		wantStatus int
	}{
		{
			name:       "missing sn",
			body:       map[string]interface{}{"model": "X1"},
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "empty sn",
			body:       map[string]interface{}{"sn": "", "model": "X1"},
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b, _ := json.Marshal(tt.body)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/internal/device-info", bytes.NewBuffer(b))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			r.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d, body: %s", w.Code, tt.wantStatus, w.Body.String())
			}
		})
	}
}

func TestInternalDeviceData_Validation(t *testing.T) {
	r := setupTestRouter()

	tests := []struct {
		name       string
		body       interface{}
		wantStatus int
	}{
		{
			name:       "missing sn",
			body:       map[string]interface{}{"topic": "data/realtime", "data": map[string]interface{}{"v": 1}},
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "missing topic",
			body:       map[string]interface{}{"sn": "INV001", "data": map[string]interface{}{"v": 1}},
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "missing data",
			body:       map[string]interface{}{"sn": "INV001", "topic": "data/realtime"},
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b, _ := json.Marshal(tt.body)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/internal/device-data", bytes.NewBuffer(b))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			r.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d, body: %s", w.Code, tt.wantStatus, w.Body.String())
			}
		})
	}
}

func TestInternalDeviceCmdStatus_Validation(t *testing.T) {
	r := setupTestRouter()

	tests := []struct {
		name       string
		body       interface{}
		wantStatus int
	}{
		{
			name:       "missing sn",
			body:       map[string]interface{}{"cmd": "open", "result": "ok"},
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "empty sn",
			body:       map[string]interface{}{"sn": "", "cmd": "open"},
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b, _ := json.Marshal(tt.body)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/internal/device-cmd-status", bytes.NewBuffer(b))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			r.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d, body: %s", w.Code, tt.wantStatus, w.Body.String())
			}
		})
	}
}

func TestInternalDeviceAlarm_Validation(t *testing.T) {
	r := setupTestRouter()

	tests := []struct {
		name       string
		body       interface{}
		wantStatus int
	}{
		{
			name:       "missing sn",
			body:       map[string]interface{}{"event": "fault", "source": "inverter"},
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "invalid trigger type",
			body:       map[string]interface{}{"sn": "INV001", "trigger": "not-an-object"},
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b, _ := json.Marshal(tt.body)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/internal/alarm", bytes.NewBuffer(b))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			r.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d, body: %s", w.Code, tt.wantStatus, w.Body.String())
			}
		})
	}
}