package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoad_ExpandsEnvVars(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
server:
  port: ${GW_PORT:-8080}
  mode: release
jwt:
  secret: "${JWT_SECRET}"
backends:
  api_server: "${API_SERVER_URL:-http://localhost:8080}"
  device_server: "${DEVICE_SERVER_URL:-http://localhost:8081}"
redis:
  host: "${REDIS_HOST:-localhost}"
  port: ${REDIS_PORT:-6379}
  password: "${REDIS_PASSWORD:-}"
  db: 0
rbac:
  enabled: true
  cache_ttl_sec: 300
`
	if err := os.WriteFile(cfgPath, []byte(yamlContent), 0644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("JWT_SECRET", "test-secret-123")
	t.Setenv("API_SERVER_URL", "http://api:9090")
	t.Setenv("REDIS_HOST", "myredis")
	t.Setenv("REDIS_PORT", "6380")

	cfg, err := Load(cfgPath)
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}

	if cfg.JWT.Secret != "test-secret-123" {
		t.Errorf("JWT.Secret = %q, want %q", cfg.JWT.Secret, "test-secret-123")
	}
	if cfg.Backends.APIServer != "http://api:9090" {
		t.Errorf("Backends.APIServer = %q, want %q", cfg.Backends.APIServer, "http://api:9090")
	}
	if cfg.Redis.Host != "myredis" {
		t.Errorf("Redis.Host = %q, want %q", cfg.Redis.Host, "myredis")
	}
	if cfg.Redis.Port != 6380 {
		t.Errorf("Redis.Port = %d, want %d", cfg.Redis.Port, 6380)
	}
}

func TestLoad_DefaultValues(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
server:
  port: 9999
jwt:
  secret: "default-secret"
backends:
  api_server: "http://a:1"
  device_server: "http://b:2"
redis:
  host: localhost
  port: 6379
`
	if err := os.WriteFile(cfgPath, []byte(yamlContent), 0644); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(cfgPath)
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}

	if cfg.Server.Port != 9999 {
		t.Errorf("Server.Port = %d, want 9999", cfg.Server.Port)
	}
	if cfg.RBAC.CacheTTLSec != 300 {
		t.Errorf("RBAC.CacheTTLSec = %d, want 300 (default)", cfg.RBAC.CacheTTLSec)
	}
}

func TestLoad_MissingFile(t *testing.T) {
	_, err := Load("/nonexistent/config.yaml")
	if err == nil {
		t.Error("expected error for missing file, got nil")
	}
}
