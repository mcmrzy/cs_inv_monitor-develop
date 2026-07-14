package main

import (
	"testing"

	"inv-api-server/internal/handler"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestRegisterModelRoutesIncludesFrontendContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	registerModelRoutes(router.Group("/api/v1"), &handler.ModelHandler{})

	routes := make(map[string]struct{})
	for _, route := range router.Routes() {
		routes[route.Method+" "+route.Path] = struct{}{}
	}

	expected := []string{
		"GET /api/v1/field-catalog",
		"POST /api/v1/field-catalog",
		"GET /api/v1/models/:id/field-capabilities",
		"PUT /api/v1/models/:id/field-capabilities",
		"PUT /api/v1/models/:id/field-capabilities/:fieldKey",
		"GET /api/v1/models/:id/commands-v2",
		"POST /api/v1/models/:id/commands-v2",
		"PUT /api/v1/models/:id/commands-v2/:commandCode",
		"GET /api/v1/models/:id/protocol-schema",
		"GET /api/v1/protocol-versions",
		"POST /api/v1/protocol-versions",
		"POST /api/v1/protocol-versions/:protocolId/release",
		"PUT /api/v1/models/:id/protocol-version",
		"GET /api/v1/models/:id/migration-report",
		"GET /api/v1/models/:id/data-preview",
		"POST /api/v1/models/:id/validate",
		"POST /api/v1/models/:id/activate",
	}

	for _, route := range expected {
		_, ok := routes[route]
		require.Truef(t, ok, "missing route %s", route)
	}
}
