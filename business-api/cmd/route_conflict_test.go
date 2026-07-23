package main

import (
	"testing"

	"inv-api-server/internal/config"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

// TestSetupRouterNoConflict verifies that all route registrations succeed
// without Gin wildcard-vs-static panics.
func TestSetupRouterNoConflict(t *testing.T) {
	gin.SetMode(gin.TestMode)

	cfg := &config.Config{
		Server: config.ServerConfig{Port: 8080, Mode: "test"},
		CORS:   config.CORSConfig{AllowedOrigins: []string{"http://localhost:5173"}},
		Backends: config.BackendsConfig{
			InternalKey: "test-key",
		},
	}

	// setupRouter with nil deps – we only care that route registration
	// doesn't panic. Handlers are never invoked.
	require.NotPanics(t, func() {
		_ = setupRouter(cfg, &RouterDeps{})
	}, "setupRouter panicked – likely a Gin wildcard-vs-static route conflict")
}
