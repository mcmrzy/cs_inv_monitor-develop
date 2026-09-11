package main

import (
	"bytes"
	"errors"
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

// 上传暂存目录（.staging）中的文件尚未通过校验，不得对外提供下载。
func TestOpenFirmwareFileRejectsStagingDir(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, firmwareStagingDir), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, firmwareStagingDir, "upload_1.bin"), []byte("x"), 0600); err != nil {
		t.Fatal(err)
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()

	if _, err := openFirmwareFile(root, "/"+firmwareStagingDir+"/upload_1.bin"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expected staging file to be hidden, got %v", err)
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

// 安装包上传体积可达上百 MB，默认的 2 MiB JSON 上限必须对它放行，
// 同时仍然约束住其他路径（避免上传口被用来绕过全局限额）。
func TestRequestBodyLimitAllowsAppPackageUpload(t *testing.T) {
	gin.SetMode(gin.TestMode)

	const (
		oversized = 3 << 20 // 大于默认 2 MiB、小于上传上限
	)
	tests := []struct {
		name       string
		path       string
		bodySize   int
		wantStatus int
	}{
		{"固件上传放行", "/api/v1/ota/firmware", oversized, http.StatusNoContent},
		{"安装包上传放行", "/api/v1/ota/app/versions", oversized, http.StatusNoContent},
		{"普通接口仍受限", "/api/v1/ota/packages", oversized, http.StatusRequestEntityTooLarge},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			router := gin.New()
			router.Use(requestBodyLimit())
			router.POST(tc.path, func(c *gin.Context) { c.Status(http.StatusNoContent) })

			req := httptest.NewRequest(http.MethodPost, tc.path, bytes.NewReader(make([]byte, tc.bodySize)))
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, req)
			if recorder.Code != tc.wantStatus {
				t.Fatalf("%s = %d, want %d", tc.path, recorder.Code, tc.wantStatus)
			}
		})
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
