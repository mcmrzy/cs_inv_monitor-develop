package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"inv-api-server/internal/config"

	"github.com/gin-gonic/gin"
)

func TestOpenFirmwareFileRejectsTraversal(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "firmware.bin"), []byte("firmware"), 0600); err != nil {
		t.Fatal(err)
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()

	file, err := openFirmwareFile(root, "/firmware.bin")
	if err != nil {
		t.Fatalf("expected firmware file to open: %v", err)
	}
	_ = file.Close()
	if _, err := openFirmwareFile(root, "/../../outside.txt"); err == nil {
		t.Fatal("expected traversal path to be rejected")
	}
}

func TestRequestBodyLimitRejectsOversizedJSON(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(requestBodyLimit())
	router.POST("/api/v1/stations", func(c *gin.Context) { c.Status(http.StatusNoContent) })

	req := httptest.NewRequest(http.MethodPost, "/api/v1/stations", bytes.NewReader(make([]byte, (2<<20)+1)))
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, req)
	if recorder.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d", recorder.Code)
	}
}

// TestFirmwareDownloadRouteSupportsHead 覆盖 HEAD 探测（curl -I / App 的
// Content-Type 预检）：只注册 GET 时 HEAD 会落到 Gin 默认 404。
func TestFirmwareDownloadRouteSupportsHead(t *testing.T) {
	gin.SetMode(gin.TestMode)

	// setupRouter 内的 os.OpenRoot 会一直持有目录句柄，Windows 上无法清理
	// TempDir，故与 route_conflict_test.go 一致地落在 os.TempDir() 下。
	dir := filepath.Join(os.TempDir(), "firmware_head_"+t.Name())
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("FIRMWARE_DATA_DIR", dir)
	const payload = "firmware-bytes"
	if err := os.WriteFile(filepath.Join(dir, "fw.bin"), []byte(payload), 0600); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Server: config.ServerConfig{Port: 8080, Mode: "test"},
		CORS:   config.CORSConfig{AllowedOrigins: []string{"http://localhost:5173"}},
		Backends: config.BackendsConfig{
			InternalKey: "test-key",
		},
	}
	router := setupRouter(cfg, &RouterDeps{})

	for _, method := range []string{http.MethodGet, http.MethodHead} {
		req := httptest.NewRequest(method, "/firmware/fw.bin", nil)
		recorder := httptest.NewRecorder()
		router.ServeHTTP(recorder, req)

		if recorder.Code != http.StatusOK {
			t.Fatalf("%s /firmware/fw.bin = %d, want 200", method, recorder.Code)
		}
		if got := recorder.Header().Get("Content-Length"); got != "14" {
			t.Fatalf("%s Content-Length = %q, want 14", method, got)
		}
		switch method {
		case http.MethodGet:
			if recorder.Body.String() != payload {
				t.Fatalf("GET body = %q, want %q", recorder.Body.String(), payload)
			}
		case http.MethodHead:
			if recorder.Body.Len() != 0 {
				t.Fatalf("HEAD body = %q, want empty", recorder.Body.String())
			}
		}
	}
}
