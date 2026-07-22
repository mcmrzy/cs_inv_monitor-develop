package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

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
