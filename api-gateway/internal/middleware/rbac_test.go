package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
)

func TestIsAppAllowedPath(t *testing.T) {
	tests := []struct {
		path   string
		expect bool
	}{
		{"/api/v1/ota/check/DEV001", true},
		{"/api/v1/ota/trigger", true},
		{"/api/v1/ota/resend/123", true},
		{"/api/v1/ota/devices/DEV001", true},
		{"/api/v1/ota/app/check", true},
		{"/api/v1/ota/app/packages", true},
		{"/api/v1/ota/available-packages/1", true},
		{"/api/v1/ota/app/packages/install", true},
		{"/api/v1/ota/trigger-admin", false},
		{"/api/v1/ota/app/packages/admin-delete", false},
		{"/api/v1/ota/tasks", false},
		{"/api/v1/devices", false},
		{"/api/v1/admin/users", false},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			assert.Equal(t, tt.expect, isAppAllowedPath(tt.path))
		})
	}
}

func TestIsAppAllowedPathWithMethod(t *testing.T) {
	tests := []struct {
		path   string
		method string
		expect bool
	}{
		{"/api/v1/stations", "POST", true},
		{"/api/v1/stations", "GET", false},
		{"/api/v1/stations/123", "PUT", false},
		{"/api/v1/stations/123", "DELETE", false},
		{"/api/v1/ota/check/DEV001", "GET", true},
		{"/api/v1/ota/trigger", "POST", true},
		{"/api/v1/devices", "GET", false},
	}

	for _, tt := range tests {
		name := tt.method + " " + tt.path
		t.Run(name, func(t *testing.T) {
			assert.Equal(t, tt.expect, isAppAllowedPathWithMethod(tt.path, tt.method))
		})
	}
}

func TestActionForRequest_CommandPostsUseEdit(t *testing.T) {
	paths := []string{
		"/api/v1/devices/SN001/control",
		"/api/v1/devices/SN001/unbind",
		"/api/v1/devices/batch/control",
		"/api/v1/devices/unbind-requests/3/approve",
		"/api/v1/alarms/9/acknowledge",
		"/api/v1/alerts/9/ignore",
		"/api/v1/work-orders/2/attachments",
		"/api/v1/work-orders/2/escalate",
	}
	for _, path := range paths {
		assert.Equal(t, "edit", actionForRequest(http.MethodPost, path), path)
	}
	assert.Equal(t, "create", actionForRequest(http.MethodPost, "/api/v1/devices/bind"))
}

func TestDirectDeviceSN(t *testing.T) {
	sn, ok := directDeviceSN("/api/v1/device/SN001/data")
	assert.True(t, ok)
	assert.Equal(t, "SN001", sn)
	_, ok = directDeviceSN("/api/v1/device/SN001/command")
	assert.False(t, ok)
}

func TestParseUserID(t *testing.T) {
	tests := []struct {
		name   string
		header string
		expect int64
	}{
		{"valid ID", "42", 42},
		{"zero", "0", 0},
		{"empty", "", 0},
		{"invalid", "abc", 0},
		{"negative", "-1", -1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, _ := gin.CreateTestContext(httptest.NewRecorder())
			c.Request, _ = http.NewRequest("GET", "/", nil)
			if tt.header != "" {
				c.Request.Header.Set("X-User-ID", tt.header)
			}
			assert.Equal(t, tt.expect, ParseUserID(c))
		})
	}
}

func TestNewRBACMiddleware_DefaultTTL(t *testing.T) {
	r := NewRBACMiddleware(nil, nil, 0)
	assert.Equal(t, 300*time.Second, r.cacheTTL)

	r2 := NewRBACMiddleware(nil, nil, -5)
	assert.Equal(t, 300*time.Second, r2.cacheTTL)

	r3 := NewRBACMiddleware(nil, nil, 60)
	assert.Equal(t, 60*time.Second, r3.cacheTTL)
}

// newTestRouter creates a test router with RBACGuard
func newTestRouter(rbac *RBACMiddleware) *gin.Engine {
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Next()
	})
	router.Use(rbac.RBACGuard())
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.GET("/api/v1/admin/users", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.GET("/api/v1/ota/check/DEV001", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.POST("/api/v1/devices/bind", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.POST("/api/v1/devices/by-sn/TEST001/unbind", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.POST("/api/v1/devices/claim-code/generate", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.POST("/api/v1/devices/by-sn/TEST001/request-transfer", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	return router
}

func TestRBACGuard_PublicPath(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/health", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_AppAllowedPath(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	// For app allowed paths, the user just needs to be active. With no DB,
	// isUserActive returns true (fail open for tests).
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/ota/check/DEV001", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_NoUserID_FailsClosed(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestRBACGuard_SystemAdmin_Bypass(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-Is-System-Admin", "true")
	router.ServeHTTP(w, req)

	// System admin should bypass all RBAC checks
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_RejectsBlacklistedToken(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	mr.Set("token_blacklist:revoked-jti", "1")
	router := newTestRouter(NewRBACMiddleware(rdb, nil, 300))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-Is-System-Admin", "true")
	req.Header.Set("X-Token-JTI", "revoked-jti")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestRBACGuard_RejectsRevokedSession(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	router := newTestRouter(NewRBACMiddleware(rdb, nil, 300))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-Is-System-Admin", "true")
	req.Header.Set("X-Session-ID", "revoked-session")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestRBACGuard_DoesNotTrustClientSideIsSystemAdmin(t *testing.T) {
	// The X-Is-System-Admin header is stripped by JWT middleware's
	// stripUntrustedIdentityHeaders. In tests without JWT middleware,
	// a client-supplied header should still work since RBACGuard reads it
	// directly. This test verifies the header is checked.
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	// Without X-Is-System-Admin, non-admin user gets 403 for admin paths
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestIsSelfServiceDeviceOperation(t *testing.T) {
	cases := []struct {
		path   string
		method string
		want   bool
	}{
		{"/api/v1/devices/bind", http.MethodPost, true},
		{"/api/v1/devices/import-excel", http.MethodPost, true},
		{"/api/v1/devices/by-sn/SN123/unbind", http.MethodPost, true},
		{"/api/v1/devices/by-sn/SN123/request-unbind", http.MethodPost, true},
		{"/api/v1/devices/by-sn/SN123/claim", http.MethodPost, true},
		{"/api/v1/devices/by-sn/SN123/request-transfer", http.MethodPost, true},
		{"/api/v1/devices/claim-code/generate", http.MethodPost, true},
		{"/api/v1/devices/claim-code/verify", http.MethodPost, true},
		// Negative cases: GET never qualifies; non-self-service POST paths stay RBAC-protected
		{"/api/v1/devices/bind", http.MethodGet, false},
		{"/api/v1/devices", http.MethodPost, false},
		{"/api/v1/devices/batch/control", http.MethodPost, false},
		{"/api/v1/devices/add-to-station", http.MethodPost, false},
		{"/api/v1/devices/by-sn/SN123/control", http.MethodPost, false},
		{"/api/v1/devices/by-sn/SN123/remove-from-station", http.MethodPost, false},
		{"/api/v1/devices/by-sn/SN123", http.MethodPost, false},
		{"/api/v1/devices/unbind-requests", http.MethodGet, false},
	}
	for _, tc := range cases {
		assert.Equal(t, tc.want, isSelfServiceDeviceOperation(tc.path, tc.method),
			"%s %s", tc.method, tc.path)
	}
}

func TestRBACGuard_SelfServiceDeviceOperations_Pass(t *testing.T) {
	// User 42 has NO permission grants cached — self-service device operations
	// must still pass the gateway so downstream business rules can evaluate
	// ownership/tenant checks (the 403 regression for registered users binding
	// their own devices).
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	router := newTestRouter(NewRBACMiddleware(rdb, nil, 300))

	paths := []string{
		"/api/v1/devices/bind",
		"/api/v1/devices/by-sn/TEST001/unbind",
		"/api/v1/devices/claim-code/generate",
		"/api/v1/devices/by-sn/TEST001/request-transfer",
	}
	for _, p := range paths {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, p, nil)
		req.Header.Set("X-User-ID", "42")
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "POST %s should pass gateway RBAC", p)
	}
}

func TestRBACGuard_SelfServiceDeviceOperation_Unauthenticated(t *testing.T) {
	router := newTestRouter(NewRBACMiddleware(nil, nil, 300))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/bind", nil)
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestRBACGuard_NonAdminWithoutPermissions_Forbidden(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	// Cache empty permissions for user 42
	mr.Set("gw:user_perms:42:0:0", "[]")
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_PermissionCheck_WithRedisCache(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)

	// Cache permissions for user 10 with devices:view
	perms := []PermissionEntry{
		{PermissionCode: "devices:view", DataScope: "organization"},
	}
	data, _ := json.Marshal(perms)
	mr.Set("gw:user_perms:10:100:1000", string(data))

	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "10")
	req.Header.Set("X-Organization-ID", "100")
	req.Header.Set("X-Membership-ID", "1000")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_PermissionDenied(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	// User 20 has no permissions cached
	mr.Set("gw:user_perms:20:0:0", "[]")

	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "20")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_NoDBConnection_Forbidden(t *testing.T) {
	// No Redis, no PG: permission resolution fails → forbidden
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_UnmatchedResource_FailsClosed(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := gin.New()
	router.Use(rbac.RBACGuard())
	router.GET("/api/v1/unknown-resource", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/unknown-resource", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_AuthenticatedOnlyPath(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := gin.New()
	router.Use(rbac.RBACGuard())
	router.POST("/api/v1/auth/logout", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusNoContent, w.Code)
}

func TestRBACGuard_Geocode_BasicUserGET_Pass(t *testing.T) {
	// 回归：App 创建电站页地图选点依赖 GET /api/v1/geocode（及 /geocode/reverse），
	// 普通注册用户无组织级 stations:view 授权，须在 basicUserGET 白名单放行
	// （与 POST /api/v1/stations 的自助创建放行保持一致）。
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	// 用户 42 无任何权限授权（空权限缓存）
	mr.Set("gw:user_perms:42:0:0", "[]")

	router := gin.New()
	router.Use(NewRBACMiddleware(rdb, nil, 300).RBACGuard())
	router.GET("/api/v1/geocode", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.GET("/api/v1/geocode/reverse", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	for _, p := range []string{"/api/v1/geocode", "/api/v1/geocode/reverse"} {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, p, nil)
		req.Header.Set("X-User-ID", "42")
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "GET %s should pass for basic user", p)
	}
}

func TestRBACGuard_StaleNegativeCacheRefreshes(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	queries := 0
	rbac.queryUserPermissions = func(_ context.Context, userID, orgID, membershipID int64) ([]PermissionEntry, error) {
		queries++
		return []PermissionEntry{{PermissionCode: "admin:manage", DataScope: "organization"}}, nil
	}

	router := newTestRouter(rbac)

	// First request — no cache, queries DB, gets admin:manage
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, 1, queries)
}

func TestInvalidateUserPermissions(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	mr.Set("gw:user_perms:42:100:1000", "[]")

	rbac.InvalidateUserPermissions("42", "100", "1000")

	assert.False(t, mr.Exists("gw:user_perms:42:100:1000"))
}

func TestInvalidateUserCache_Wildcard(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	mr.Set("gw:user_perms:42:100:1000", "[]")
	mr.Set("gw:user_perms:42:200:2000", "[]")

	rbac.InvalidateUserCache("42")

	assert.False(t, mr.Exists("gw:user_perms:42:100:1000"))
	assert.False(t, mr.Exists("gw:user_perms:42:200:2000"))
}

func TestResourceActionMap(t *testing.T) {
	expectedMappings := map[string]string{
		"/api/v1/admin/users":   "admin",
		"/api/v1/users":         "users",
		"/api/v1/devices":       "devices",
		"/api/v1/alarms":        "alerts",
		"/api/v1/alerts/1":      "alerts",
		"/api/v1/stations":      "stations",
		"/api/v1/models":        "models",
		"/api/v1/dashboard":     "dashboard",
		"/api/v1/ota/tasks":     "ota",
		"/api/v1/ota/firmware":  "firmware",
		"/api/v1/parallel":      "parallel",
		"/api/v1/notifications": "notifications",
		"/api/v1/alert-rules":   "alert_rules",
		"/api/v1/work-orders":   "work_orders",
		"/api/v1/firmwares":     "firmware",
	}

	for path, resource := range expectedMappings {
		assert.Equal(t, resource, resourceForPath(path),
			"path %s should map to resource %s", path, resource)
	}
	assert.Empty(t, resourceForPath("/api/v1/users-export"))
	assert.Empty(t, resourceForPath("/api/v1/ota-admin"))
	assert.Empty(t, resourceForPath("/api/v1/devices2"))
}

func TestResourceForPath_UsesMostSpecificPrefix(t *testing.T) {
	assert.Equal(t, "devices", resourceForPath("/api/v1/devices/INV001/three-phase"))
	assert.Equal(t, "firmware", resourceForPath("/api/v1/ota/firmwares/12"))
	assert.Empty(t, resourceForPath("/api/v1/unknown"))
}

func TestResourceForPath_ExactRootsAliasesAndProtocolRoutes(t *testing.T) {
	tests := map[string]string{
		"/api/v1/stations":                      "stations",
		"/api/v1/notifications":                 "notifications",
		"/api/v1/alerts":                        "alerts",
		"/api/v1/alerts/9/acknowledge":          "alerts",
		"/api/v1/alarm-events/42":               "alerts",
		"/api/v1/parallel-groups":               "parallel",
		"/api/v1/parallel-groups/7":             "parallel",
		"/api/v1/models":                        "models",
		"/api/v1/field-catalog":                 "models",
		"/api/v1/protocol-versions":             "models",
		"/api/v1/protocol-versions/2/release":   "models",
		"/api/v1/devices/INV001/alarm-events":   "devices",
		"/api/v1/devices/INV001/parallel-state": "devices",
		"/api/v1/devices/INV001/three-phase":    "devices",
	}

	for path, want := range tests {
		t.Run(path, func(t *testing.T) {
			assert.Equal(t, want, resourceForPath(path))
		})
	}
}

func TestResourceForPath_RequiresPathBoundary(t *testing.T) {
	assert.Empty(t, resourceForPath("/api/v1/stations-archive"))
	assert.Empty(t, resourceForPath("/api/v1/alerts-export"))
	assert.Empty(t, resourceForPath("/api/v1/parallel-groups-legacy"))
	assert.Empty(t, resourceForPath("/api/v1/field-catalogue"))
}

func TestBuildPermissionCode(t *testing.T) {
	rbac := &RBACMiddleware{}
	// Admin paths always get "admin:manage"
	assert.Equal(t, "admin:manage", rbac.buildPermissionCode("/api/v1/admin/system-health", http.MethodGet, "admin"))
	assert.Equal(t, "admin:manage", rbac.buildPermissionCode("/api/v1/admin/permissions/2", http.MethodPut, "admin"))
	// Regular paths combine resource + action
	assert.Equal(t, "users:view", rbac.buildPermissionCode("/api/v1/users", http.MethodGet, "users"))
	assert.Equal(t, "users:edit", rbac.buildPermissionCode("/api/v1/users/2", http.MethodPatch, "users"))
	assert.Equal(t, "alerts:edit", rbac.buildPermissionCode("/api/v1/alerts/1/acknowledge", http.MethodPost, "alerts"))
	assert.Equal(t, "alerts:create", rbac.buildPermissionCode("/api/v1/alerts", http.MethodPost, "alerts"))
	assert.Equal(t, "devices:view", rbac.buildPermissionCode("/api/v1/devices/INV001/three-phase", http.MethodGet, "devices"))

	// OTA control requests get ":control" action
	controlRequests := []struct {
		path   string
		method string
	}{
		{"/api/v1/ota/upgrades/retry", http.MethodPost},
		{"/api/v1/ota/upgrades/cancel", http.MethodPost},
		{"/api/v1/ota/packages/12/publish", http.MethodPatch},
		{"/api/v1/ota/packages/12/rollback", http.MethodPost},
		{"/api/v1/ota/tasks/9/execute", http.MethodPost},
		{"/api/v1/ota/rollback", http.MethodPost},
	}
	for _, tt := range controlRequests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			assert.Equal(t, "ota:control", rbac.buildPermissionCode(tt.path, tt.method, "ota"))
		})
	}
}

func TestAuthenticatedOnlyPaths_AreExact(t *testing.T) {
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/logout"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/change-password"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/profile"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/upload/avatar"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/send-email-change-code"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/change-email"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/send-phone-code"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/change-phone"))
	assert.False(t, isAuthenticatedOnlyPath("/api/v1/auth/profile/export"))
	assert.False(t, isAuthenticatedOnlyPath("/api/v1/auth/unknown"))
	assert.False(t, isAuthenticatedOnlyPath("/api/v1/upload/avatar/extra"))
}
