package config

import (
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoad_ExpandsEnvVars(t *testing.T) {
	tmpDir := t.TempDir()
	cfgPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
server:
  port: ${GW_PORT}
  mode: release
jwt:
  secret: "${JWT_SECRET}"
backends:
  api_server: "${API_SERVER_URL}"
  device_server: "${DEVICE_SERVER_URL}"
redis:
  host: "${REDIS_HOST}"
  port: ${REDIS_PORT}
  password: "${REDIS_PASSWORD}"
  db: 0
rbac:
  enabled: true
  cache_ttl_sec: 300
`
	if err := os.WriteFile(cfgPath, []byte(yamlContent), 0644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("GW_PORT", "9999")
	t.Setenv("JWT_SECRET", "test-secret-123")
	t.Setenv("API_SERVER_URL", "http://api:9090")
	t.Setenv("DEVICE_SERVER_URL", "http://device:8081")
	t.Setenv("REDIS_HOST", "myredis")
	t.Setenv("REDIS_PORT", "6380")
	t.Setenv("REDIS_PASSWORD", "")

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

func validConfig() *Config {
	return &Config{
		Server:    ServerConfig{Port: 8080, Mode: "release"},
		JWT:       JWTConfig{Secret: strings.Repeat("s", 32)},
		RateLimit: RateLimitConfig{Rate: 100, Burst: 200},
		Backends: BackendsConfig{
			APIServer:    "http://inv-api-server:8080",
			DeviceServer: "http://inv-device-server:8081",
		},
		Redis:    RedisConfig{Host: "redis", Port: 6379, Password: "redis-test-password"},
		Database: DatabaseConfig{Host: "postgres", Port: 5432, User: "app", Password: "db-test-password", Name: "inv_mqtt"},
		CORS:     CORSConfig{AllowedOrigins: []string{"https://console.example.com"}},
	}
}

func TestValidate_ProductionSecretsAndEndpoints(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*Config)
	}{
		{"short jwt secret", func(c *Config) { c.JWT.Secret = "short" }},
		{"empty database password", func(c *Config) { c.Database.Password = "" }},
		{"placeholder redis password", func(c *Config) { c.Redis.Password = "CHANGE_ME_NOW" }},
		{"backend credentials", func(c *Config) { c.Backends.APIServer = "http://user:pass@api:8080" }},
		{"invalid trusted proxy", func(c *Config) { c.Server.TrustedProxies = []string{"not-a-network"} }},
		{"wildcard cors", func(c *Config) { c.CORS.AllowedOrigins = []string{"*"} }},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := validConfig()
			tt.mutate(cfg)
			if err := cfg.Validate(); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}

	cfg := validConfig()
	cfg.Server.TrustedProxies = []string{"172.16.0.0/12", "127.0.0.1"}
	if err := cfg.Validate(); err != nil {
		t.Fatalf("valid production configuration rejected: %v", err)
	}
}

func TestDatabaseDSN_EscapesCredentials(t *testing.T) {
	cfg := validConfig()
	cfg.Database.User = "app@tenant"
	cfg.Database.Password = "p@ss:/?#word"

	u, err := url.Parse(cfg.DatabaseDSN())
	if err != nil {
		t.Fatalf("parse DSN: %v", err)
	}
	password, _ := u.User.Password()
	if got := u.User.Username(); got != cfg.Database.User {
		t.Fatalf("username = %q", got)
	}
	if password != cfg.Database.Password {
		t.Fatalf("password was not escaped round-trip")
	}
}
