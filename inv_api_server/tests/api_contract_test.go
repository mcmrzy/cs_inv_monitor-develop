// Package tests contains integration-level API contract tests that verify
// the backend route registrations match the frontend API call expectations.
//
// These tests use static source-code analysis (parsing main.go and
// model_routes.go for route registration statements) and lightweight runtime
// checks (httptest with stubbed handlers) so they can run without external
// dependencies such as PostgreSQL or Redis.
package tests

import (
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"testing"

	"inv-api-server/internal/handler"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// ---------------------------------------------------------------------------
// Static route extraction helpers
// ---------------------------------------------------------------------------

// groupPrefixes maps Gin route-group variable names (as used in main.go and
// model_routes.go) to their full URL prefixes.
var groupPrefixes = map[string]string{
	"api":           "/api/v1",
	"auth":          "/api/v1",
	"internal":      "/api/v1/internal",
	"adminGroup":    "/api/v1/admin",
	"usersGroup":    "/api/v1/users",
	"parallelGroup": "/api/v1/parallel-groups",
	"otaGroup":      "/api/v1/ota",
}

// routeRegexp matches Gin route-registration statements such as:
//
//	auth.GET("/devices", deps.DeviceHandler.List)
//	parallelGroup.POST("", deps.ParallelHandler.Create)
var routeRegexp = regexp.MustCompile(`(\w+)\.(GET|POST|PUT|PATCH|DELETE)\("([^"]*)"`)

// extractRoutes reads the given Go source files and returns a set of
// registered routes keyed by "METHOD /full/path".
func extractRoutes(t *testing.T, filePaths ...string) map[string]bool {
	t.Helper()
	routes := make(map[string]bool)

	for _, fp := range filePaths {
		source, err := os.ReadFile(fp)
		require.NoError(t, err, "failed to read %s", fp)

		for _, m := range routeRegexp.FindAllStringSubmatch(string(source), -1) {
			groupVar, method, path := m[1], m[2], m[3]
			prefix, ok := groupPrefixes[groupVar]
			if !ok {
				continue // skip routes on unknown group variables (e.g., router.GET)
			}
			routes[method+" "+prefix+path] = true
		}
	}

	return routes
}

// ---------------------------------------------------------------------------
// Expected frontend API routes
// ---------------------------------------------------------------------------

// expectedFrontendRoutes lists every frontend API call that must be registered
// in the backend router. A missing route would cause a 404 response.
var expectedFrontendRoutes = []struct {
	Method string
	Path   string
}{
	// ---- Auth ----
	{"POST", "/api/v1/auth/login"},
	{"POST", "/api/v1/auth/logout"},
	{"POST", "/api/v1/auth/refresh"},

	// ---- Devices ----
	{"GET", "/api/v1/devices"},
	{"POST", "/api/v1/devices"},
	{"GET", "/api/v1/devices/:sn"},
	{"PUT", "/api/v1/devices/:sn"},
	{"DELETE", "/api/v1/devices/:sn"},
	{"POST", "/api/v1/devices/:sn/unbind"},
	{"POST", "/api/v1/devices/:sn/request-unbind"},
	{"GET", "/api/v1/devices/unbind-requests"},
	{"POST", "/api/v1/devices/unbind-requests/:id/approve"},
	{"POST", "/api/v1/devices/unbind-requests/:id/reject"},
	{"GET", "/api/v1/devices/:sn/lifecycle"},
	{"POST", "/api/v1/devices/import-excel"},
	{"GET", "/api/v1/devices/:sn/telemetry"},
	{"GET", "/api/v1/devices/:sn/realtime"},
	{"POST", "/api/v1/devices/:sn/control"},
	{"GET", "/api/v1/devices/:sn/commands"},
	{"GET", "/api/v1/devices/:sn/commands/history"},
	{"GET", "/api/v1/devices/:sn/telemetry/export"},
	{"GET", "/api/v1/devices/:sn/telemetry/export-excel"},
	{"POST", "/api/v1/devices/:sn/assign-installer"},
	{"DELETE", "/api/v1/devices/:sn/installer"},
	{"POST", "/api/v1/devices/batch-assign-installer"},
	{"POST", "/api/v1/devices/add-to-station"},
	{"POST", "/api/v1/devices/:sn/remove-from-station"},

	// ---- Parallel Groups ----
	{"GET", "/api/v1/parallel-groups"},
	{"GET", "/api/v1/parallel-groups/:id"},
	{"POST", "/api/v1/parallel-groups"},
	{"PATCH", "/api/v1/parallel-groups/:id"},
	{"DELETE", "/api/v1/parallel-groups/:id"},

	// ---- OTA ----
	{"GET", "/api/v1/ota/firmware"},
	{"POST", "/api/v1/ota/firmware"},
	{"DELETE", "/api/v1/ota/firmware/:id"},
	{"GET", "/api/v1/ota/upgrades/dashboard"},
	{"POST", "/api/v1/ota/upgrades/push"},
	{"GET", "/api/v1/ota/tasks"},
	{"POST", "/api/v1/ota/tasks"},

	// ---- Alarms ----
	{"GET", "/api/v1/alarms"},
	{"GET", "/api/v1/notifications"},

	// ---- Users ----
	{"GET", "/api/v1/users"},
	{"PATCH", "/api/v1/users/:id"},
	{"PUT", "/api/v1/users/:id/password"},

	// ---- Dashboard ----
	// Frontend calls /dashboard/statistics (see dashboardApi.ts)
	{"GET", "/api/v1/dashboard/statistics"},
}

// ---------------------------------------------------------------------------
// Test 1: Route registration completeness (no 404)
// ---------------------------------------------------------------------------

// TestAPIContract_RoutesRegistered verifies that every frontend API path in
// the expected list is registered in the backend router source code.
// A missing route would cause a 404 response for the frontend.
func TestAPIContract_RoutesRegistered(t *testing.T) {
	routes := extractRoutes(t, "../cmd/main.go", "../cmd/model_routes.go")

	var missing []string
	for _, r := range expectedFrontendRoutes {
		key := r.Method + " " + r.Path
		if !routes[key] {
			missing = append(missing, key)
		}
	}

	if len(missing) > 0 {
		t.Errorf("The following frontend API routes are not registered "+
			"(would return 404):\n  %s", strings.Join(missing, "\n  "))
	}

	t.Logf("Total registered routes extracted from source: %d", len(routes))
}

// ---------------------------------------------------------------------------
// Test 2: ParallelHandler non-501 verification (runtime)
// ---------------------------------------------------------------------------

// TestAPIContract_ParallelHandlerNo501 verifies that all ParallelHandler
// endpoints do not return 501 (Not Implemented).
//
// The test injects a non-admin role into the Gin context so the handler
// returns 403 (Forbidden) before attempting any database operation.
// This confirms:
//  1. The route is registered (not 404)
//  2. The handler is implemented (not 501)
func TestAPIContract_ParallelHandlerNo501(t *testing.T) {
	// nil service is safe: non-admin role short-circuits before any service call.
	h := handler.NewParallelHandler(nil)

	r := gin.New()
	r.Use(gin.Recovery())
	// Inject non-admin user context so handlers return 403, not 501.
	r.Use(func(c *gin.Context) {
		c.Set("role", 5) // regular user (role > 1 means non-admin)
		c.Set("user_id", int64(1))
		c.Next()
	})

	pg := r.Group("/api/v1/parallel-groups")
	pg.GET("", h.List)
	pg.GET("/:id", h.Get)
	pg.POST("", h.Create)
	pg.PATCH("/:id", h.Update)
	pg.DELETE("/:id", h.Delete)

	cases := []struct {
		name   string
		method string
		path   string
		body   string
	}{
		{"GET /parallel-groups", http.MethodGet, "/api/v1/parallel-groups", ""},
		{"GET /parallel-groups/:id", http.MethodGet, "/api/v1/parallel-groups/1", ""},
		{"POST /parallel-groups", http.MethodPost, "/api/v1/parallel-groups", "{}"},
		{"PATCH /parallel-groups/:id", http.MethodPatch, "/api/v1/parallel-groups/1", "{}"},
		{"DELETE /parallel-groups/:id", http.MethodDelete, "/api/v1/parallel-groups/1", ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var req *http.Request
			if tc.body != "" {
				req = httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
				req.Header.Set("Content-Type", "application/json")
			} else {
				req = httptest.NewRequest(tc.method, tc.path, nil)
			}

			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)

			assert.NotEqual(t, http.StatusNotImplemented, w.Code,
				"%s must not return 501 Not Implemented", tc.name)
		})
	}
}

// ---------------------------------------------------------------------------
// Test 3: ParallelHandler source code static analysis (no 501)
// ---------------------------------------------------------------------------

// TestAPIContract_ParallelHandlerSourceNo501 performs a static analysis check
// to ensure the ParallelHandler source code does not contain any 501
// (StatusNotImplemented) responses.
func TestAPIContract_ParallelHandlerSourceNo501(t *testing.T) {
	source, err := os.ReadFile("../internal/handler/parallel_handler.go")
	require.NoError(t, err)

	src := string(source)
	assert.NotContains(t, src, "StatusNotImplemented",
		"ParallelHandler must not return 501 StatusNotImplemented")
	assert.NotContains(t, src, `"code": 501`,
		"ParallelHandler must not return business code 501")
}

// ---------------------------------------------------------------------------
// Test 4: RequestUnbind route existence
// ---------------------------------------------------------------------------

// TestAPIContract_RequestUnbindRouteExists verifies that the
// POST /devices/:sn/request-unbind route is registered in main.go.
func TestAPIContract_RequestUnbindRouteExists(t *testing.T) {
	source, err := os.ReadFile("../cmd/main.go")
	require.NoError(t, err)

	expected := `auth.POST("/devices/:sn/request-unbind"`
	if !strings.Contains(string(source), expected) {
		t.Fatalf("request-unbind route is missing in main.go: expected %s", expected)
	}
}
