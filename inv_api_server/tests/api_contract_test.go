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
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"

	"inv-api-server/internal/handler"

	"github.com/gin-gonic/gin"
	json "github.com/goccy/go-json"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
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

// ---------------------------------------------------------------------------
// Commercial channel platform contract assets
// ---------------------------------------------------------------------------

const channelOpenAPIPath = "../../contracts/openapi/channel-platform-v1.yaml"

var channelEventSchemaPaths = map[string]string{
	"authorization-cache-invalidated": "../../contracts/events/authorization-cache-invalidated.v1.schema.json",
	"asset-transfer":                  "../../contracts/events/asset-transfer.v1.schema.json",
	"audit-event":                     "../../contracts/events/audit-event.v1.schema.json",
}

func loadYAMLDocument(t *testing.T, path string) map[string]any {
	t.Helper()

	contents, err := os.ReadFile(path)
	require.NoError(t, err, "contract asset must exist: %s", filepath.ToSlash(path))

	var document map[string]any
	require.NoError(t, yaml.Unmarshal(contents, &document), "contract asset must contain valid YAML: %s", filepath.ToSlash(path))
	require.NotEmpty(t, document, "contract asset must not be empty: %s", filepath.ToSlash(path))
	return document
}

func loadJSONDocument(t *testing.T, path string) map[string]any {
	t.Helper()

	contents, err := os.ReadFile(path)
	require.NoError(t, err, "contract asset must exist: %s", filepath.ToSlash(path))

	var document map[string]any
	require.NoError(t, json.Unmarshal(contents, &document), "contract asset must contain valid JSON: %s", filepath.ToSlash(path))
	require.NotEmpty(t, document, "contract asset must not be empty: %s", filepath.ToSlash(path))
	return document
}

func requireObject(t *testing.T, value any, description string) map[string]any {
	t.Helper()
	object, ok := value.(map[string]any)
	require.True(t, ok, "%s must be an object, got %T", description, value)
	return object
}

func requireStringSlice(t *testing.T, value any, description string) []string {
	t.Helper()
	items, ok := value.([]any)
	require.True(t, ok, "%s must be an array, got %T", description, value)

	result := make([]string, 0, len(items))
	for _, item := range items {
		text, ok := item.(string)
		require.True(t, ok, "%s entries must be strings, got %T", description, item)
		result = append(result, text)
	}
	return result
}

func requireSchemaObject(t *testing.T, schemas map[string]any, name string) map[string]any {
	t.Helper()
	schema := requireObject(t, schemas[name], name+" schema")
	require.Equal(t, "object", schema["type"], "%s must declare type: object", name)
	require.Equal(t, false, schema["additionalProperties"], "%s must reject undeclared properties", name)
	return schema
}

func requireOperationResponseSchemaRef(
	t *testing.T,
	paths map[string]any,
	path string,
	method string,
	status string,
	expectedRef string,
) {
	t.Helper()
	pathItem := requireObject(t, paths[path], "OpenAPI path "+path)
	operation := requireObject(t, pathItem[method], strings.ToUpper(method)+" "+path)
	responses := requireObject(t, operation["responses"], strings.ToUpper(method)+" "+path+" responses")
	response := requireObject(t, responses[status], strings.ToUpper(method)+" "+path+" response "+status)
	content := requireObject(t, response["content"], strings.ToUpper(method)+" "+path+" response content")
	mediaType := requireObject(t, content["application/json"], strings.ToUpper(method)+" "+path+" JSON response")
	schema := requireObject(t, mediaType["schema"], strings.ToUpper(method)+" "+path+" response schema")
	require.Equal(t, expectedRef, schema["$ref"])
}

func requireMutationContract(
	t *testing.T,
	paths map[string]any,
	path string,
	method string,
	successStatus string,
	expectedResponseRef string,
) {
	t.Helper()
	pathItem := requireObject(t, paths[path], "OpenAPI path "+path)
	operation := requireObject(t, pathItem[method], strings.ToUpper(method)+" "+path)
	parameters, ok := operation["parameters"].([]any)
	require.True(t, ok, "%s %s must declare parameters", strings.ToUpper(method), path)
	hasIdempotencyKey := false
	for _, rawParameter := range parameters {
		parameter := requireObject(t, rawParameter, strings.ToUpper(method)+" "+path+" parameter")
		if parameter["$ref"] == "#/components/parameters/IdempotencyKey" {
			hasIdempotencyKey = true
		}
	}
	require.True(t, hasIdempotencyKey, "%s %s must require Idempotency-Key", strings.ToUpper(method), path)

	responses := requireObject(t, operation["responses"], strings.ToUpper(method)+" "+path+" responses")
	for _, status := range []string{"403", "409", "422"} {
		response := requireObject(t, responses[status], strings.ToUpper(method)+" "+path+" response "+status)
		require.NotEmpty(t, response["$ref"], "%s %s must use a shared business error response for %s", strings.ToUpper(method), path, status)
	}
	requireOperationResponseSchemaRef(t, paths, path, method, successStatus, expectedResponseRef)
}

func requireAllLocalReferencesResolve(t *testing.T, document map[string]any) {
	t.Helper()

	var walk func(any)
	walk = func(value any) {
		switch node := value.(type) {
		case map[string]any:
			if rawRef, ok := node["$ref"]; ok {
				ref, ok := rawRef.(string)
				require.True(t, ok, "$ref must be a string")
				if strings.HasPrefix(ref, "#/") {
					var current any = document
					for _, escapedToken := range strings.Split(strings.TrimPrefix(ref, "#/"), "/") {
						token := strings.ReplaceAll(strings.ReplaceAll(escapedToken, "~1", "/"), "~0", "~")
						object, ok := current.(map[string]any)
						require.True(t, ok, "local $ref %s traverses a non-object at %s", ref, token)
						current, ok = object[token]
						require.True(t, ok, "local $ref target does not exist: %s", ref)
					}
				}
			}
			for _, child := range node {
				walk(child)
			}
		case []any:
			for _, child := range node {
				walk(child)
			}
		}
	}

	walk(document)
}

func TestChannelPlatformContractAssetsExistAndParse(t *testing.T) {
	openAPI := loadYAMLDocument(t, channelOpenAPIPath)
	require.Equal(t, "3.1.0", openAPI["openapi"])
	info := requireObject(t, openAPI["info"], "OpenAPI info")
	require.NotEmpty(t, info["version"], "OpenAPI info.version must be stable and explicit")

	for eventName, schemaPath := range channelEventSchemaPaths {
		t.Run(eventName, func(t *testing.T) {
			schema := loadJSONDocument(t, schemaPath)
			require.Equal(t, "https://json-schema.org/draft/2020-12/schema", schema["$schema"])
		})
	}
}

func TestChannelPlatformContractOpenAPISurface(t *testing.T) {
	openAPI := loadYAMLDocument(t, channelOpenAPIPath)
	paths := requireObject(t, openAPI["paths"], "OpenAPI paths")

	requiredOperations := map[string][]string{
		"/auth/context":                        {"post"},
		"/authorization/me":                    {"get"},
		"/organizations":                       {"get", "post"},
		"/organizations/{id}/children":         {"get"},
		"/organizations/{id}/members":          {"get"},
		"/invitations":                         {"get", "post"},
		"/devices/claims":                      {"post"},
		"/devices/{sn}/grants":                 {"get", "post"},
		"/devices/{sn}/transfers":              {"get", "post"},
		"/stations/{id}/transfers":             {"get", "post"},
		"/devices/bind":                        {"post"},
		"/devices/{sn}/unbind":                 {"post", "delete"},
		"/devices/{sn}/request-unbind":         {"post"},
		"/devices/{sn}/unbind-requests":        {"get", "post"},
		"/device-unbind-requests/{id}/approve": {"post"},
		"/device-unbind-requests/{id}/reject":  {"post"},
		"/users":                               {"get", "post"},
		"/users/{id}":                          {"get", "patch", "delete"},
		"/users/{id}/password":                 {"put"},
		"/users/{id}/toggle":                   {"put"},
		"/users/{id}/children":                 {"get"},
		"/users/{id}/parent":                   {"put"},
	}

	for path, methods := range requiredOperations {
		pathItem := requireObject(t, paths[path], "OpenAPI path "+path)
		for _, method := range methods {
			require.Contains(t, pathItem, method, "OpenAPI must declare %s %s", strings.ToUpper(method), path)
		}
	}

	components := requireObject(t, openAPI["components"], "OpenAPI components")
	schemas := requireObject(t, components["schemas"], "OpenAPI component schemas")

	permissionGrant := requireSchemaObject(t, schemas, "PermissionScopeGrant")
	permissionGrantProperties := requireObject(t, permissionGrant["properties"], "PermissionScopeGrant properties")
	permissionGrantRequired := requireStringSlice(t, permissionGrant["required"], "PermissionScopeGrant required")
	for _, property := range []string{"permission_code", "data_scope", "source"} {
		require.Contains(t, permissionGrantProperties, property)
		require.Contains(t, permissionGrantRequired, property)
	}

	roleAssignment := requireSchemaObject(t, schemas, "RoleAssignment")
	roleAssignmentProperties := requireObject(t, roleAssignment["properties"], "RoleAssignment properties")
	roleAssignmentRequired := requireStringSlice(t, roleAssignment["required"], "RoleAssignment required")
	for _, property := range []string{"role_code", "permission_grants"} {
		require.Contains(t, roleAssignmentProperties, property)
		require.Contains(t, roleAssignmentRequired, property)
	}

	authorizationContext := requireSchemaObject(t, schemas, "AuthorizationContextV2")
	authorizationProperties := requireObject(t, authorizationContext["properties"], "AuthorizationContextV2 properties")
	authorizationSchemaVersion := requireObject(t, authorizationProperties["schema_version"], "AuthorizationContextV2 schema_version")
	require.Equal(t, "integer", authorizationSchemaVersion["type"])
	require.EqualValues(t, 2, authorizationSchemaVersion["const"])
	authorizationRequired := requireStringSlice(t, authorizationContext["required"], "AuthorizationContextV2 required")
	for _, property := range []string{"actor", "active_organization", "memberships", "permission_grants", "authorization_version"} {
		require.Contains(t, authorizationProperties, property, "AuthorizationContextV2 must declare %s", property)
		require.Contains(t, authorizationRequired, property, "AuthorizationContextV2 must require %s", property)
	}
	require.NotContains(t, authorizationProperties, "data_scope", "authorization scope must remain paired to each permission grant")
	require.NotContains(t, authorizationRequired, "data_scope", "a split global data_scope must not become an authorization fact")

	membership := requireSchemaObject(t, schemas, "MembershipSummary")
	membershipProperties := requireObject(t, membership["properties"], "MembershipSummary properties")
	for _, property := range []string{"role_assignments", "permission_grants"} {
		require.Contains(t, membershipProperties, property)
	}
	for _, forbidden := range []string{"role_codes", "data_scope"} {
		require.NotContains(t, membershipProperties, forbidden, "membership authorization must not use split role/scope fields")
	}

	for _, invitationSchemaName := range []string{"Invitation", "CreateInvitationRequest"} {
		invitation := requireSchemaObject(t, schemas, invitationSchemaName)
		invitationProperties := requireObject(t, invitation["properties"], invitationSchemaName+" properties")
		require.Contains(t, invitationProperties, "role_assignments")
		for _, forbidden := range []string{"role_codes", "data_scope"} {
			require.NotContains(t, invitationProperties, forbidden, "%s must preserve role/permission scope pairing", invitationSchemaName)
		}
	}

	allowedActions := requireObject(t, schemas["AllowedActions"], "AllowedActions schema")
	require.Equal(t, "array", allowedActions["type"])
	for _, resourceSchemaName := range []string{"DeviceResource", "StationResource", "AssetGrant", "DeviceTransfer", "StationTransfer"} {
		resourceSchema := requireSchemaObject(t, schemas, resourceSchemaName)
		resourceProperties := requireObject(t, resourceSchema["properties"], resourceSchemaName+" properties")
		resourceRequired := requireStringSlice(t, resourceSchema["required"], resourceSchemaName+" required")
		require.Contains(t, resourceProperties, "allowed_actions", "%s must expose resource-specific allowed_actions", resourceSchemaName)
		require.Contains(t, resourceRequired, "allowed_actions", "%s must always return allowed_actions", resourceSchemaName)
	}
	unbindRequest := requireSchemaObject(t, schemas, "UnbindRequest")
	unbindRequestProperties := requireObject(t, unbindRequest["properties"], "UnbindRequest properties")
	unbindRequestRequired := requireStringSlice(t, unbindRequest["required"], "UnbindRequest required")
	for _, property := range []string{"version", "status", "allowed_actions"} {
		require.Contains(t, unbindRequestProperties, property, "UnbindRequest must declare %s", property)
		require.Contains(t, unbindRequestRequired, property, "UnbindRequest must require %s", property)
	}
	requireOperationResponseSchemaRef(t, paths, "/devices/claims", "post", "200", "#/components/schemas/DeviceResourceResponse")
	requireOperationResponseSchemaRef(t, paths, "/devices/{sn}/grants", "get", "200", "#/components/schemas/GrantListResponse")
	requireOperationResponseSchemaRef(t, paths, "/devices/{sn}/transfers", "get", "200", "#/components/schemas/DeviceTransferListResponse")
	requireOperationResponseSchemaRef(t, paths, "/devices/{sn}/transfers", "post", "202", "#/components/schemas/DeviceTransferResponse")
	requireOperationResponseSchemaRef(t, paths, "/stations/{id}/transfers", "get", "200", "#/components/schemas/StationTransferListResponse")
	requireOperationResponseSchemaRef(t, paths, "/stations/{id}/transfers", "post", "202", "#/components/schemas/StationTransferResponse")
	requireOperationResponseSchemaRef(t, paths, "/devices/{sn}/unbind-requests", "get", "200", "#/components/schemas/UnbindRequestListResponse")
	requireMutationContract(t, paths, "/devices/{sn}/unbind-requests", "post", "202", "#/components/schemas/UnbindRequestResponse")
	requireMutationContract(t, paths, "/device-unbind-requests/{id}/approve", "post", "200", "#/components/schemas/UnbindRequestResponse")
	requireMutationContract(t, paths, "/device-unbind-requests/{id}/reject", "post", "200", "#/components/schemas/UnbindRequestResponse")

	businessErrorCode := requireObject(t, schemas["BusinessErrorCode"], "BusinessErrorCode schema")
	actualErrorCodes := requireStringSlice(t, businessErrorCode["enum"], "BusinessErrorCode enum")
	requiredErrorCodes := []string{
		"APPROVAL_REQUIRED",
		"ASSET_CONFLICT",
		"CLAIM_INVALID",
		"CLAIM_REPLAYED",
		"MEMBERSHIP_INACTIVE",
		"ORG_SCOPE_DENIED",
		"TRANSFER_PENDING",
		"VERSION_CONFLICT",
	}
	sort.Strings(actualErrorCodes)
	sort.Strings(requiredErrorCodes)
	require.Subset(t, actualErrorCodes, requiredErrorCodes, "BusinessErrorCode must retain stable channel-platform error codes")

	legacyOperations := map[string][]string{
		"/devices/bind":                {"post"},
		"/devices/{sn}/unbind":         {"post", "delete"},
		"/devices/{sn}/request-unbind": {"post"},
		"/users":                       {"get", "post"},
		"/users/{id}":                  {"get", "patch", "delete"},
		"/users/{id}/password":         {"put"},
		"/users/{id}/toggle":           {"put"},
		"/users/{id}/children":         {"get"},
		"/users/{id}/parent":           {"put"},
	}
	for path, methods := range legacyOperations {
		pathItem := requireObject(t, paths[path], "legacy path "+path)
		for _, method := range methods {
			operation := requireObject(t, pathItem[method], "legacy operation "+strings.ToUpper(method)+" "+path)
			require.Equal(t, true, operation["deprecated"], "legacy operation must be explicitly deprecated")
			require.NotEmpty(t, operation["x-replacement"], "legacy operation must identify its replacement")
		}
	}
	for path, methods := range map[string][]string{
		"/devices/{sn}/unbind":         {"post", "delete"},
		"/devices/{sn}/request-unbind": {"post"},
	} {
		pathItem := requireObject(t, paths[path], "legacy unbind path "+path)
		for _, method := range methods {
			operation := requireObject(t, pathItem[method], "legacy unbind operation "+strings.ToUpper(method)+" "+path)
			require.Equal(t, "POST /devices/{sn}/unbind-requests", operation["x-replacement"], "unbind is a lifecycle workflow, not an ownership transfer")
		}
	}

	requireAllLocalReferencesResolve(t, openAPI)
}

func TestChannelPlatformContractEventSchemas(t *testing.T) {
	requiredCommonFields := []string{"schema_version", "event_id", "occurred_at", "root_tenant_id", "payload"}
	requiredPayloadFields := map[string][]string{
		"authorization-cache-invalidated": {"authorization_version", "reason", "scope"},
		"asset-transfer":                  {"transfer_id", "asset_type", "asset_id", "from_organization_id", "to_organization_id", "status", "version"},
		"audit-event":                     {"actor_user_id", "active_organization_id", "action", "resource_type", "resource_id", "result"},
	}

	for eventName, schemaPath := range channelEventSchemaPaths {
		t.Run(eventName, func(t *testing.T) {
			schema := loadJSONDocument(t, schemaPath)
			require.Equal(t, "object", schema["type"])
			require.Equal(t, false, schema["additionalProperties"], "%s event envelope must reject unknown fields", eventName)
			properties := requireObject(t, schema["properties"], eventName+" properties")
			required := requireStringSlice(t, schema["required"], eventName+" required")

			for _, field := range requiredCommonFields {
				require.Contains(t, properties, field, "%s must declare common field %s", eventName, field)
				require.Contains(t, required, field, "%s must require common field %s", eventName, field)
			}

			payload := requireObject(t, properties["payload"], eventName+" payload")
			require.Equal(t, "object", payload["type"])
			require.Equal(t, false, payload["additionalProperties"], "%s payload must reject unknown fields", eventName)
			payloadProperties := requireObject(t, payload["properties"], eventName+" payload properties")
			payloadRequired := requireStringSlice(t, payload["required"], eventName+" payload required")
			for _, field := range requiredPayloadFields[eventName] {
				require.Contains(t, payloadProperties, field, "%s payload must declare %s", eventName, field)
				require.Contains(t, payloadRequired, field, "%s payload must require %s", eventName, field)
			}

			schemaVersion := requireObject(t, properties["schema_version"], eventName+" schema_version")
			require.Equal(t, "string", schemaVersion["type"], "%s schema_version must declare its wire type", eventName)
			require.Equal(t, "1.0", schemaVersion["const"], "%s must pin schema_version", eventName)
			require.Equal(t, "string", requireObject(t, properties["event_id"], eventName+" event_id")["type"])
			require.Equal(t, "string", requireObject(t, properties["occurred_at"], eventName+" occurred_at")["type"])
			require.Equal(t, "integer", requireObject(t, properties["root_tenant_id"], eventName+" root_tenant_id")["type"])

			if eventName == "audit-event" {
				for _, field := range []string{"request_id", "source_ip", "before", "after", "failure_reason"} {
					require.Contains(t, payloadRequired, field, "audit payload must require the stable field %s even when null", field)
				}
				for _, field := range []string{"before", "after", "failure_reason"} {
					fieldSchema := requireObject(t, payloadProperties[field], "audit-event "+field)
					fieldTypes := fieldSchema["type"]
					typeList, ok := fieldTypes.([]any)
					require.True(t, ok, "audit-event %s must use a nullable type array", field)
					require.Contains(t, typeList, "null", "audit-event %s must allow null", field)
				}
			}
			requireAllLocalReferencesResolve(t, schema)
		})
	}
}

func channelContractRepoRoot(t *testing.T) string {
	t.Helper()
	repoRoot, err := filepath.Abs("../..")
	require.NoError(t, err)
	return repoRoot
}

func findPowerShell(t *testing.T) string {
	t.Helper()
	for _, candidate := range []string{"pwsh", "powershell"} {
		path, err := exec.LookPath(candidate)
		if err == nil {
			return path
		}
	}
	if runtime.GOOS == "windows" {
		t.Fatal("PowerShell is required to execute channel contract migration tests on Windows")
	}
	t.Skip("PowerShell is not installed; skipping executable contract-checker test")
	return ""
}

func runChannelContractChecker(t *testing.T, repoRoot string, mode string, baselinePath string) (string, error) {
	t.Helper()
	checkerPath := filepath.Join(repoRoot, "tools", "check_channel_contracts.ps1")
	args := []string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", checkerPath, "-Mode", mode}
	if baselinePath != "" {
		args = append(args, "-BaselinePath", baselinePath)
	}
	command := exec.Command(findPowerShell(t), args...)
	command.Dir = repoRoot
	output, err := command.CombinedOutput()
	return string(output), err
}

func copyContractFixtureFile(t *testing.T, source string, destination string) {
	t.Helper()
	contents, err := os.ReadFile(source)
	require.NoError(t, err)
	require.NoError(t, os.MkdirAll(filepath.Dir(destination), 0o755))
	require.NoError(t, os.WriteFile(destination, contents, 0o600))
}

func TestChannelPlatformContractCheckerMigrationModesAndGatewayCoverage(t *testing.T) {
	repoRoot := channelContractRepoRoot(t)

	legacyOutput, legacyErr := runChannelContractChecker(t, repoRoot, "legacy", "")
	require.NoError(t, legacyErr, "legacy mode must be non-blocking:\n%s", legacyOutput)

	shadowOutput, shadowErr := runChannelContractChecker(t, repoRoot, "shadow", "")
	require.NoError(t, shadowErr, "shadow mode must report without blocking:\n%s", shadowOutput)
	require.Contains(t, shadowOutput, "Gateway route missing", "shadow must report OpenAPI operations with no Gateway route")
	require.Contains(t, shadowOutput, "Gateway route missing: POST /device-unbind-requests/{id}/approve")
	require.Contains(t, shadowOutput, "Gateway route missing: POST /device-unbind-requests/{id}/reject")
	require.Contains(t, shadowOutput, "Deprecated client call", "shadow must identify channel clients still using replacement endpoints")
	require.Contains(t, shadowOutput, "replacement=POST /devices/{sn}/unbind-requests", "legacy unbind calls must migrate to the unbind workflow")
	require.NotContains(t, shadowOutput, "/dashboard/", "non-channel dashboard calls must not be evaluated by this contract")
	require.NotContains(t, shadowOutput, "/alarms", "non-channel alarm calls must not be evaluated by this contract")
	require.NotContains(t, strings.ToLower(shadowOutput), "mocks", "mock sources must not be treated as API consumers")

	enforceOutput, enforceErr := runChannelContractChecker(t, repoRoot, "enforce", "")
	require.Error(t, enforceErr, "enforce must block current Gateway/deprecated-client migration gaps")
	require.Contains(t, enforceOutput, "Gateway route missing")
	require.Contains(t, enforceOutput, "POST /device-unbind-requests/{id}/approve")
}

func TestChannelPlatformContractCheckerExcludesMockConsumers(t *testing.T) {
	realRepoRoot := channelContractRepoRoot(t)
	fixtureRoot := t.TempDir()
	for _, relativePath := range []string{
		"tools/check_channel_contracts.ps1",
		"contracts/openapi/channel-platform-v1.yaml",
		"contracts/events/authorization-cache-invalidated.v1.schema.json",
		"contracts/events/asset-transfer.v1.schema.json",
		"contracts/events/audit-event.v1.schema.json",
		"api-gateway/internal/routes/routes.go",
	} {
		copyContractFixtureFile(t, filepath.Join(realRepoRoot, filepath.FromSlash(relativePath)), filepath.Join(fixtureRoot, filepath.FromSlash(relativePath)))
	}

	productionClient := filepath.Join(fixtureRoot, "inv-admin-frontend", "src", "services", "channelApi.ts")
	require.NoError(t, os.MkdirAll(filepath.Dir(productionClient), 0o755))
	require.NoError(t, os.WriteFile(productionClient, []byte("api.post('/devices/bind')\n"), 0o600))
	mockClient := filepath.Join(fixtureRoot, "inv-admin-frontend", "src", "test", "mocks", "channelMock.ts")
	require.NoError(t, os.MkdirAll(filepath.Dir(mockClient), 0o755))
	require.NoError(t, os.WriteFile(mockClient, []byte("api.get('/organizations/mock-only')\n"), 0o600))

	output, err := runChannelContractChecker(t, fixtureRoot, "shadow", "")
	require.NoError(t, err, "fixture shadow scan must not block:\n%s", output)
	require.Contains(t, output, "POST /devices/bind", "production deprecated channel call must be observed")
	require.NotContains(t, output, "mock-only", "a mock-only route must be excluded behaviorally")
	require.NotContains(t, strings.ToLower(output), "channelmock", "mock file names must never appear in the report")
}

func TestChannelPlatformContractCheckerBaselineCompatibility(t *testing.T) {
	repoRoot := channelContractRepoRoot(t)
	currentPath := filepath.Join(repoRoot, filepath.FromSlash("contracts/openapi/channel-platform-v1.yaml"))
	currentBytes, err := os.ReadFile(currentPath)
	require.NoError(t, err)
	current := strings.ReplaceAll(string(currentBytes), "\r\n", "\n")

	selfOutput, selfErr := runChannelContractChecker(t, repoRoot, "shadow", currentPath)
	require.NoError(t, selfErr, "an unchanged contract must be baseline-compatible:\n%s", selfOutput)

	tests := []struct {
		name            string
		baseline        string
		expectedMessage string
	}{
		{
			name:            "operation removed",
			baseline:        strings.Replace(current, "\ncomponents:\n", "\n  /compatibility/probe:\n    get:\n      responses:\n        '204':\n          description: compatibility probe\ncomponents:\n", 1),
			expectedMessage: "operation removed",
		},
		{
			name:            "enum narrowed",
			baseline:        strings.Replace(current, "    BusinessErrorCode:\n      type: string\n      enum:\n", "    BusinessErrorCode:\n      type: string\n      enum:\n        - COMPATIBILITY_PROBE\n", 1),
			expectedMessage: "enum value removed",
		},
		{
			name:            "required field added",
			baseline:        strings.Replace(current, "required: [code, message, request_id, retryable]", "required: [code, message, retryable]", 1),
			expectedMessage: "required field added",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			require.NotEqual(t, current, test.baseline, "baseline mutation must be applied")
			baselinePath := filepath.Join(t.TempDir(), "channel-platform-baseline.yaml")
			require.NoError(t, os.WriteFile(baselinePath, []byte(test.baseline), 0o600))
			output, runErr := runChannelContractChecker(t, repoRoot, "shadow", baselinePath)
			require.Error(t, runErr, "breaking baseline change must block in every mode")
			require.Contains(t, strings.ToLower(output), test.expectedMessage, "unexpected baseline failure:\n%s", output)
		})
	}
}
