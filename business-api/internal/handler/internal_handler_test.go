package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

// assertResponseCode checks JSON body "code" field instead of HTTP status,
// because response.Error always returns HTTP 200.
func assertResponseCode(t *testing.T, w *httptest.ResponseRecorder, wantCode int) {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("HTTP status = %d, want 200, body: %s", w.Code, w.Body.String())
	}
	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal body: %v, body: %s", err, w.Body.String())
	}
	got := int(resp["code"].(float64))
	if got != wantCode {
		t.Errorf("code = %d, want %d, body: %s", got, wantCode, w.Body.String())
	}
}

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

			assertResponseCode(t, w, tt.wantStatus)
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

			assertResponseCode(t, w, tt.wantStatus)
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

			assertResponseCode(t, w, tt.wantStatus)
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

			assertResponseCode(t, w, tt.wantStatus)
		})
	}
}
