package config

import (
	"strings"
	"testing"
)

func TestValidateRejectsInsecureEmailTLS(t *testing.T) {
	cfg := Config{
		Server:   ServerConfig{Port: 8080},
		Database: DatabaseConfig{Host: "postgres", Password: "test-password"},
		JWT:      JWTConfig{Secret: "test-jwt-secret"},
		Backends: BackendsConfig{InternalKey: "test-internal-key"},
		Email:    EmailConfig{TLSInsecure: true},
	}
	err := cfg.Validate()
	if err == nil || !strings.Contains(err.Error(), "email.tls_insecure must be false") {
		t.Fatalf("expected insecure email TLS to be rejected, got %v", err)
	}
}
