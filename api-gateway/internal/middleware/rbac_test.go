package middleware

import (
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
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/ota/check/DEV001", nil)
	req.Header.Set("X-User-ID", "42")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}

func TestRBACGuard_NoUserID_PassThrough(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	router.ServeHTTP(w, req)

	// 无 X-User-ID 时跳过检查，放行
	assert.Equal(t, http.StatusOK, w.Code)
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

func TestRBACGuard_HeaderRole_SuperAdmin(t *testing.T) {
	rbac := NewRBACMiddleware(nil, nil, 300)
	router := newTestRouter(rbac)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/users", nil)
	req.Header.Set("X-User-ID", "1")
	req.Header.Set("X-User-Role", "0") // super_admin via header
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
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

func TestRBACGuard_UnmatchedResource_PassThrough(t *testing.T) {
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

	// 无匹配资源时跳过 RBAC 检查
	assert.Equal(t, http.StatusOK, w.Code)
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

func TestRBACGuard_MemoryCache(t *testing.T) {
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

	// 第二次请求 - 应使用内存缓存
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req2.Header.Set("X-User-ID", "5")
	req2.Header.Set("X-User-Role", "1") // 角色 1，使用内存缓存
	router.ServeHTTP(w2, req2)
	assert.Equal(t, http.StatusOK, w2.Code)
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
		"/api/v1/admin/":         "admin",
		"/api/v1/users":          "users",
		"/api/v1/devices":        "devices",
		"/api/v1/alarms":         "alerts",
		"/api/v1/stations/":      "stations",
		"/api/v1/models":         "models",
		"/api/v1/dashboard":      "dashboard",
		"/api/v1/ota/tasks":      "ota",
		"/api/v1/ota/firmwares":  "firmware",
		"/api/v1/parallel":       "parallel",
		"/api/v1/notifications/": "notifications",
		"/api/v1/alert-rules":    "alert_rules",
		"/api/v1/work-orders":    "work_orders",
		"/api/v1/firmwares":      "firmware",
	}

	for prefix, resource := range expectedMappings {
		assert.Equal(t, resource, resourceActionMap[prefix],
			"prefix %s should map to resource %s", prefix, resource)
	}
}
