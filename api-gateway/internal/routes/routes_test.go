package routes

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func newTestConfig() Config {
	return Config{
		APIServer:      "http://localhost:8081",
		DeviceServer:   "http://localhost:8082",
		JWTSecret:      "test-secret",
		GlobalRate:     100,
		GlobalBurst:    20,
		AllowedOrigins: []string{"*"},
	}
}

// ===================== Setup =====================

func TestSetup_ReturnsEngine(t *testing.T) {
	engine := Setup(newTestConfig())
	require.NotNil(t, engine)
	assert.IsType(t, &gin.Engine{}, engine)
}

func TestSetup_RedirectTrailingSlashDisabled(t *testing.T) {
	engine := Setup(newTestConfig())
	assert.False(t, engine.RedirectTrailingSlash)
}

// ===================== Route Registration =====================

func TestRouteRegistration_RouteCount(t *testing.T) {
	engine := Setup(newTestConfig())
	routes := engine.Routes()

	// Count routes by group type
	var publicCount, userCount, adminCount int
	for _, r := range routes {
		switch {
		case isPublicRoute(r.Path):
			publicCount++
		case isAdminRoute(r.Path):
			adminCount++
		case isUserRoute(r.Path):
			userCount++
		}
	}

	// Public routes should include auth endpoints + captcha + uploads + firmware + ws + timezones
	assert.GreaterOrEqual(t, publicCount, 10, "should have at least 10 public routes")
	// User routes should include stations, devices, alarms, models, dashboard, ota, etc.
	assert.GreaterOrEqual(t, userCount, 15, "should have at least 15 user routes")
	// Admin routes
	assert.GreaterOrEqual(t, adminCount, 5, "should have at least 5 admin routes")
}

func TestRouteRegistration_PublicAuthRoutes(t *testing.T) {
	engine := Setup(newTestConfig())

	expectedPaths := []string{
		"/api/v1/auth/login",
		"/api/v1/auth/register",
		"/api/v1/auth/send-code",
		"/api/v1/auth/reset-password",
		"/api/v1/auth/email-register",
		"/api/v1/auth/email-login",
		"/api/v1/auth/send-email-code",
		"/api/v1/auth/refresh",
		"/api/v1/auth/context",
	}
	for _, path := range expectedPaths {
		assertRouteExists(t, engine, path, "public auth route missing")
	}
}

func TestRouteRegistration_UserAuthRoutes(t *testing.T) {
	engine := Setup(newTestConfig())

	expectedPaths := []string{
		"/api/v1/auth/logout",
		"/api/v1/auth/change-password",
		"/api/v1/auth/profile",
	}
	for _, path := range expectedPaths {
		assertRouteExists(t, engine, path, "user auth route missing")
	}
}

func TestRouteRegistration_UserResourceRoutes(t *testing.T) {
	engine := Setup(newTestConfig())

	// Routes registered with wildcard suffix
	expectedPaths := []string{
		"/api/v1/stations",
		"/api/v1/devices",
		"/api/v1/alarms",
		"/api/v1/alerts",
		"/api/v1/notifications",
		"/api/v1/alert-rules",
		"/api/v1/models",
		"/api/v1/field-catalog",
		"/api/v1/protocol-versions",
		"/api/v1/dashboard",
		"/api/v1/ota/*action",
		"/api/v1/firmwares",
		"/api/v1/work-orders",
	}
	for _, path := range expectedPaths {
		assertRouteExists(t, engine, path, "user resource route missing")
	}
}

func TestRouteRegistration_AdminRoutes(t *testing.T) {
	engine := Setup(newTestConfig())

	expectedPaths := []string{
		"/api/v1/admin/route-groups",
		"/api/v1/users",
		"/api/v1/admin/models",
		"/api/v1/admin/models/*action",
		"/api/v1/admin/users",
		"/api/v1/admin/permissions",
		"/api/v1/admin/logs",
		"/api/v1/admin/system-health",
		"/api/v1/admin/system-config",
		"/api/v1/admin/tenants",
		"/api/v1/admin/metrics",
	}
	for _, path := range expectedPaths {
		assertRouteExists(t, engine, path, "admin route missing")
	}
}

func TestRouteRegistration_GatewayEndpoints(t *testing.T) {
	engine := Setup(newTestConfig())

	assertRouteExists(t, engine, "/health", "health endpoint missing")
	assertRouteExists(t, engine, "/metrics", "metrics endpoint missing")
	assertRouteExists(t, engine, "/api/docs", "api docs endpoint missing")
}

func TestRouteRegistration_DeviceRoutes(t *testing.T) {
	engine := Setup(newTestConfig())

	// Device routes use wildcard suffix in Gin
	assertRouteExists(t, engine, "/api/v1/device/*action", "device route missing")
	assertRouteExists(t, engine, "/api/v1/stats/*action", "stats route missing")
}

// ===================== Health Endpoint =====================

func TestHealthEndpoint(t *testing.T) {
	engine := Setup(newTestConfig())

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)

	var body map[string]interface{}
	err := json.Unmarshal(rec.Body.Bytes(), &body)
	require.NoError(t, err)
	assert.Equal(t, "ok", body["status"])
	assert.Equal(t, "api-gateway", body["service"])
	assert.NotEmpty(t, body["time"])
}

// ===================== API Docs Endpoint =====================

func TestAPIDocsEndpoint(t *testing.T) {
	engine := Setup(newTestConfig())

	req := httptest.NewRequest(http.MethodGet, "/api/docs", nil)
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)

	var doc APIDoc
	err := json.Unmarshal(rec.Body.Bytes(), &doc)
	require.NoError(t, err)
	assert.Equal(t, "INV-MQTT API Gateway", doc.Title)
	assert.Equal(t, "2.0.0", doc.Version)
	assert.NotEmpty(t, doc.Endpoints)
}

// ===================== 404 Fallback =====================

func TestFallback_404(t *testing.T) {
	engine := Setup(newTestConfig())

	req := httptest.NewRequest(http.MethodGet, "/nonexistent/path", nil)
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusNotFound, rec.Code)

	var body map[string]interface{}
	err := json.Unmarshal(rec.Body.Bytes(), &body)
	require.NoError(t, err)
	assert.Equal(t, float64(404), body["code"])
	assert.Equal(t, "/nonexistent/path", body["path"])
}

// ===================== Route Groups Endpoint =====================

func TestRouteGroupsEndpoint(t *testing.T) {
	// Test buildRouteGroups directly (endpoint requires admin JWT)
	groups := buildRouteGroups()

	require.Contains(t, groups, "groups")
	assert.Len(t, groups["groups"], 3)

	groupNames := make(map[string]bool)
	for _, g := range groups["groups"] {
		groupNames[g.Name] = true
		assert.NotEmpty(t, g.Label)
		assert.NotEmpty(t, g.Routes)
	}
	assert.True(t, groupNames["public"])
	assert.True(t, groupNames["user"])
	assert.True(t, groupNames["admin"])
}

// ===================== Helpers =====================

func assertRouteExists(t *testing.T, engine *gin.Engine, path, msg string) {
	t.Helper()
	for _, r := range engine.Routes() {
		if r.Path == path {
			return
		}
	}
	t.Errorf("%s: route %s not found", msg, path)
}

func isPublicRoute(path string) bool {
	publicPrefixes := []string{
		"/api/v1/auth/login",
		"/api/v1/auth/register",
		"/api/v1/auth/send-code",
		"/api/v1/auth/reset-password",
		"/api/v1/auth/email-register",
		"/api/v1/auth/email-login",
		"/api/v1/auth/send-email-code",
		"/api/v1/timezones",
		"/api/v1/captcha",
		"/uploads",
		"/firmware",
		"/ws",
	}
	for _, p := range publicPrefixes {
		if path == p || (len(path) > len(p) && path[:len(p)] == p) {
			return true
		}
	}
	return false
}

func isUserRoute(path string) bool {
	userPrefixes := []string{
		"/api/v1/stations",
		"/api/v1/devices",
		"/api/v1/alarms",
		"/api/v1/alerts",
		"/api/v1/notifications",
		"/api/v1/alert-rules",
		"/api/v1/models",
		"/api/v1/dashboard",
		"/api/v1/ota",
		"/api/v1/firmwares",
		"/api/v1/work-orders",
		"/api/v1/device",
		"/api/v1/stats",
		"/api/v1/parallel",
	}
	for _, p := range userPrefixes {
		if path == p || (len(path) > len(p) && path[:len(p)] == p) {
			return true
		}
	}
	return false
}

func isAdminRoute(path string) bool {
	adminPrefixes := []string{
		"/api/v1/admin",
		"/api/v1/users",
		"/api/v1/internal",
	}
	for _, p := range adminPrefixes {
		if path == p || (len(path) > len(p) && path[:len(p)] == p) {
			return true
		}
	}
	return false
}
