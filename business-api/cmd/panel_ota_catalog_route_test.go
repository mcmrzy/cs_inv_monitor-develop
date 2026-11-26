package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"inv-api-server/internal/config"

	"github.com/gin-gonic/gin"
)

func TestPanelOTACatalogInternalRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)
	t.Setenv("FIRMWARE_DATA_DIR", filepath.Join(os.TempDir(), "firmware_test"))
	cfg := &config.Config{
		Server:   config.ServerConfig{Port: 8080, Mode: "test"},
		CORS:     config.CORSConfig{AllowedOrigins: []string{"http://localhost:5173"}},
		Backends: config.BackendsConfig{InternalKey: "test-key"},
	}
	router := setupRouter(cfg, &RouterDeps{})
	const query = `{"type":"catalog.query","v":1,"sn":"MB00001122334455","request_id":"0123456789abcdef","epoch":7,"index":0,"target":"esp"}`
	for _, tc := range []struct {
		name, key              string
		httpCode, businessCode int
	}{
		{"missing key", "", http.StatusUnauthorized, http.StatusUnauthorized},
		{"authenticated", "test-key", http.StatusOK, http.StatusServiceUnavailable},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/api/v1/internal/ota-catalog", strings.NewReader(query))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-Internal-Key", tc.key)
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)
			var body struct {
				Code int `json:"code"`
			}
			if w.Code != tc.httpCode || json.Unmarshal(w.Body.Bytes(), &body) != nil || body.Code != tc.businessCode {
				t.Fatalf("unexpected catalog response: HTTP %d, body %s", w.Code, w.Body.String())
			}
		})
	}
}
