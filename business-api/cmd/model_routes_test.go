package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"inv-api-server/internal/handler"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

type permissionCall struct {
	userID   int64
	resource string
	action   string
}

type recordingPermissionChecker struct {
	allow bool
	calls []permissionCall
}

func (c *recordingPermissionChecker) CheckPermission(userID int64, resource, action string) bool {
	c.calls = append(c.calls, permissionCall{userID: userID, resource: resource, action: action})
	return c.allow
}

func TestRegisterModelRoutesIncludesFrontendContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	registerModelRoutes(router.Group("/api/v1"), &handler.ModelHandler{}, &recordingPermissionChecker{allow: true})

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

func TestRegisterModelRoutesEnforcesGovernancePermissions(t *testing.T) {
	tests := []struct {
		method string
		path   string
		action string
	}{
		{http.MethodPost, "/api/v1/models", "create"},
		{http.MethodPut, "/api/v1/models/1", "edit"},
		{http.MethodDelete, "/api/v1/models/1", "delete"},
		{http.MethodPost, "/api/v1/models/1/fields", "edit"},
		{http.MethodPut, "/api/v1/models/1/fields/2", "edit"},
		{http.MethodDelete, "/api/v1/models/1/fields/2", "edit"},
		{http.MethodPut, "/api/v1/models/1/fields-batch", "edit"},
		{http.MethodGet, "/api/v1/models/1/protocols", "protocol_view"},
		{http.MethodPost, "/api/v1/models/1/protocols", "protocol_publish"},
		{http.MethodPut, "/api/v1/models/1/protocols/2", "protocol_publish"},
		{http.MethodDelete, "/api/v1/models/1/protocols/2", "protocol_publish"},
		{http.MethodGet, "/api/v1/field-catalog", "view"},
		{http.MethodPost, "/api/v1/field-catalog", "dictionary"},
		{http.MethodGet, "/api/v1/models/1/field-capabilities", "view"},
		{http.MethodPut, "/api/v1/models/1/field-capabilities", "edit"},
		{http.MethodPut, "/api/v1/models/1/field-capabilities/output_power", "edit"},
		{http.MethodGet, "/api/v1/models/1/commands-v2", "view"},
		{http.MethodPost, "/api/v1/models/1/commands-v2", "edit"},
		{http.MethodPut, "/api/v1/models/1/commands-v2/restart", "edit"},
		{http.MethodGet, "/api/v1/models/1/protocol-schema", "protocol_view"},
		{http.MethodGet, "/api/v1/protocol-versions", "protocol_view"},
		{http.MethodPost, "/api/v1/protocol-versions", "protocol_publish"},
		{http.MethodPost, "/api/v1/protocol-versions/1/release", "protocol_publish"},
		{http.MethodPut, "/api/v1/models/1/protocol-version", "edit"},
		{http.MethodGet, "/api/v1/models/1/migration-report", "view"},
		{http.MethodGet, "/api/v1/models/1/data-preview", "view"},
		{http.MethodPost, "/api/v1/models/1/validate", "edit"},
		{http.MethodPost, "/api/v1/models/1/activate", "edit"},
	}

	for _, tt := range tests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			gin.SetMode(gin.TestMode)
			checker := &recordingPermissionChecker{}
			router := gin.New()
			group := router.Group("/api/v1").Use(func(c *gin.Context) {
				c.Set("user_id", int64(42))
				c.Next()
			})
			registerModelRoutes(group, &handler.ModelHandler{}, checker)

			request := httptest.NewRequest(tt.method, tt.path, nil)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)

			require.Equal(t, http.StatusForbidden, response.Code)
			require.Equal(t, []permissionCall{{userID: 42, resource: "models", action: tt.action}}, checker.calls)
		})
	}
}
