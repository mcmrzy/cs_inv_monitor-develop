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
		{"/api/v1/ota/packages/available/1", true},
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
		// POST /api/v1/stations 允许普通用户创建电站
		{"/api/v1/stations", "POST", true},
		// GET/PUT/DELETE 仍走 RBAC，不通过白名单
		{"/api/v1/stations", "GET", false},
		{"/api/v1/stations/123", "PUT", false},
		{"/api/v1/stations/123", "DELETE", false},
		// OTA 路径不受方法限制（沿用 appAllowedPaths）
		{"/api/v1/ota/check/DEV001", "GET", true},
		{"/api/v1/ota/trigger", "POST", true},
		// 其他路径不受影响
		{"/api/v1/devices", "GET", false},
	}

	for _, tt := range tests {
		name := tt.method + " " + tt.path
		t.Run(name, func(t *testing.T) {
			assert.Equal(t, tt.expect, isAppAllowedPathWithMethod(tt.path, tt.method))
		})
	}
}

func TestGetActionFromMethod(t *testing.T) {
	r := &RBACMiddleware{}
	tests := []struct {
		method string
		expect string
	}{
		{"GET", "view"},
		{"POST", "create"},
		{"PUT", "edit"},
		{"PATCH", "edit"},
		{"DELETE", "delete"},
		{"HEAD", "view"},
		{"OPTIONS", "view"},
	}

	for _, tt := range tests {
		t.Run(tt.method, func(t *testing.T) {
			assert.Equal(t, tt.expect, r.getActionFromMethod(tt.method))
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

// newTestRouter 创建带 RBACGuard 的测试路由
func newTestRouter(rbac *RBACMiddleware) *gin.Engine {
	router := gin.New()
	router.Use(func(c *gin.Context) {
		// 模拟 JWT 中间件注入的 header
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
	mr.Set("gw:user_roles:42", "5")
	rbac := NewRBACMiddleware(rdb, nil, 300)
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

func TestRBACGuard_SuperAdmin_Bypass(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	// 在 Redis 缓存中设置 role=0 (super_admin)
	mr.Set("gw:user_roles:1", "[0]")

	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	router.ServeHTTP(w, req)

	// super_admin (role=0) 应直接放行
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_RejectsBlacklistedToken(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	mr.Set("gw:user_roles:1", "0")
	mr.Set("token_blacklist:revoked-jti", "1")
	router := newTestRouter(NewRBACMiddleware(rdb, nil, 300))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-Token-JTI", "revoked-jti")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestRBACGuard_RejectsRevokedSession(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	mr.Set("gw:user_roles:1", "0")
	router := newTestRouter(NewRBACMiddleware(rdb, nil, 300))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-Session-ID", "revoked-session")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestRBACGuard_DoesNotTrustHeaderRole(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-User-Role", "0")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_EmptyCachedRoleIsNotSuperAdmin(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	mr.Set("gw:user_roles:42", "[]")
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_RoleOneStillRequiresPermission(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	mr.Set("gw:user_roles:1", "[1]")
	mr.Set("gw:role_perms:1", "[]")
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-User-Role", "1")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_StaleNegativeCacheRefreshesAuthoritativePermissions(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	mr.Set("gw:user_roles:42", "[5]")
	mr.Set("gw:role_perms:5", "[]")
	queries := 0
	rbac.queryRolePermissions = func(_ context.Context, role int) ([]PermissionEntry, error) {
		queries++
		assert.Equal(t, 5, role)
		return []PermissionEntry{{Resource: "devices", Action: "view"}}, nil
	}
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices/INV001/alarm-events", nil)
	req.Header.Set("X-User-ID", "42")
	req.Header.Set("X-User-Role", "5")
	router.GET("/api/v1/devices/:sn/alarm-events", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, 1, queries)
}

func TestRBACGuard_InvalidRoleCacheNeverBecomesSuperAdmin(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	mr.Set("gw:user_roles:1", "not-a-role")
	router := newTestRouter(NewRBACMiddleware(rdb, nil, 300))

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_NoDBConnection_Forbidden(t *testing.T) {
	// 无 Redis 无 PG，headerRole="-1" 触发 getUserRole 查询会失败
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "42")
	req.Header.Set("X-User-Role", "-1") // 负数角色触发 DB 查询
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

	// An authenticated business route without an explicit policy must fail closed.
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

func TestRBACGuard_PermissionCheck_WithRedisCache(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)

	// 设置用户角色为 1 (admin)
	mr.Set("gw:user_roles:10", "[1]")

	// 设置角色权限
	perms := []PermissionEntry{
		{Resource: "devices", Action: "view"},
		{Resource: "users", Action: "view"},
	}
	data, _ := json.Marshal(perms)
	mr.Set("gw:role_perms:1", string(data))

	router := newTestRouter(rbac)

	// 有 devices:view 权限
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "10")
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_PermissionDenied(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)

	// 设置用户角色为 2 (普通用户)
	mr.Set("gw:user_roles:20", "[2]")

	// 角色 2 无任何权限
	mr.Set("gw:role_perms:2", "[]")

	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "20")
	req.Header.Set("X-User-Role", "2") // 角色 2，无权限
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
}

func TestRBACGuard_RedisInvalidationOverridesMemoryCache(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)

	// 预热 Redis 缓存
	perms := []PermissionEntry{
		{Resource: "devices", Action: "view"},
	}
	data, _ := json.Marshal(perms)
	mr.Set("gw:role_perms:1", string(data))
	mr.Set("gw:user_roles:5", "[1]")

	router := newTestRouter(rbac)

	// 第一次请求 - 从 Redis 加载并填充内存缓存
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("X-User-ID", "5")
	req.Header.Set("X-User-Role", "1") // 角色 1，触发权限缓存路径
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusOK, w.Code)

	// 验证内存缓存已填充
	rbac.mu.RLock()
	_, cached := rbac.roleCache["gw:role_perms:1"]
	rbac.mu.RUnlock()
	assert.True(t, cached)

	// 删除 Redis 缓存
	mr.Del("gw:role_perms:1")
	rbac.queryRolePermissions = func(_ context.Context, role int) ([]PermissionEntry, error) {
		assert.Equal(t, 1, role)
		return []PermissionEntry{}, nil
	}

	// 第二次请求 - 应使用内存缓存
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req2.Header.Set("X-User-ID", "5")
	req2.Header.Set("X-User-Role", "1") // 角色 1，使用内存缓存
	router.ServeHTTP(w2, req2)
	assert.Equal(t, http.StatusForbidden, w2.Code)
}

func TestInvalidateUserCache(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)
	mr.Set("gw:user_roles:42", "1")

	rbac.InvalidateUserCache("42")

	assert.False(t, mr.Exists("gw:user_roles:42"))
}

func TestInvalidateRoleCache(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()

	rbac := NewRBACMiddleware(rdb, nil, 300)

	// 填充内存和 Redis 缓存
	rbac.mu.Lock()
	rbac.roleCache["gw:role_perms:1"] = cacheEntry{
		perms:    []PermissionEntry{{Resource: "test", Action: "view"}},
		cachedAt: time.Now(),
	}
	rbac.mu.Unlock()
	mr.Set("gw:role_perms:1", `[{"resource":"test","action":"view"}]`)

	rbac.InvalidateRoleCache(1)

	// 内存缓存应被清除
	rbac.mu.RLock()
	_, exists := rbac.roleCache["gw:role_perms:1"]
	rbac.mu.RUnlock()
	assert.False(t, exists)

	// Redis 缓存也应被清除
	assert.False(t, mr.Exists("gw:role_perms:1"))
}

func TestResourceActionMap(t *testing.T) {
	// 验证关键资源映射存在
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

func TestGetActionForRequest(t *testing.T) {
	rbac := &RBACMiddleware{}
	assert.Equal(t, "manage", rbac.getActionForRequest("/api/v1/admin/system-health", http.MethodGet))
	assert.Equal(t, "manage", rbac.getActionForRequest("/api/v1/admin/permissions/2", http.MethodPut))
	assert.Equal(t, "manage", rbac.getActionForRequest("/api/v1/admin/tenants", http.MethodPost))
	assert.Equal(t, "view", rbac.getActionForRequest("/api/v1/users", http.MethodGet))
	assert.Equal(t, "edit", rbac.getActionForRequest("/api/v1/users/2", http.MethodPatch))
	assert.Equal(t, "edit", rbac.getActionForRequest("/api/v1/alerts/1/acknowledge", http.MethodPost))
	assert.Equal(t, "edit", rbac.getActionForRequest("/api/v1/alarms/1/ignore", http.MethodPost))
	assert.Equal(t, "create", rbac.getActionForRequest("/api/v1/alerts", http.MethodPost))
	assert.Equal(t, "view", rbac.getActionForRequest("/api/v1/devices/INV001/three-phase", http.MethodGet))

	controlRequests := []struct {
		path   string
		method string
	}{
		{"/api/v1/ota/upgrades/retry", http.MethodPost},
		{"/api/v1/ota/upgrades/cancel", http.MethodPost},
		{"/api/v1/ota/packages/12/publish", http.MethodPatch},
		{"/api/v1/ota/packages/12/rollback", http.MethodPost},
		{"/api/v1/ota/tasks/9/execute", http.MethodPost},
		{"/api/v1/ota/tasks/9/cancel", http.MethodPost},
		{"/api/v1/ota/tasks/9/retry", http.MethodPost},
		{"/api/v1/ota/rollback", http.MethodPost},
		{"/api/v1/ota/rollback-to-published", http.MethodPost},
		{"/api/v1/ota/app/versions/3/rollout", http.MethodPut},
		{"/api/v1/ota/app/versions/3/rollback", http.MethodPost},
		{"/api/v1/ota/app/versions/3/restore", http.MethodPost},
	}
	for _, tt := range controlRequests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			assert.Equal(t, "control", rbac.getActionForRequest(tt.path, tt.method))
		})
	}

	assert.Equal(t, "create", rbac.getActionForRequest("/api/v1/ota/tasks", http.MethodPost))
	assert.Equal(t, "edit", rbac.getActionForRequest("/api/v1/work-orders/9/cancel", http.MethodPatch))
}

func TestAuthenticatedOnlyPaths_AreExact(t *testing.T) {
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/logout"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/change-password"))
	assert.True(t, isAuthenticatedOnlyPath("/api/v1/auth/profile"))
	assert.False(t, isAuthenticatedOnlyPath("/api/v1/auth/profile/export"))
	assert.False(t, isAuthenticatedOnlyPath("/api/v1/auth/unknown"))
}
