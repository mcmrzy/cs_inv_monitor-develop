package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// mockChecker 实现 PermissionChecker 接口
type mockChecker struct {
	result bool
}

func (m *mockChecker) CheckPermission(userID int64, resource string, action string) bool {
	return m.result
}

func parseResp(t *testing.T, w *httptest.ResponseRecorder) map[string]interface{} {
	t.Helper()
	var body map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &body)
	if err != nil {
		return nil
	}
	return body
}

// ==================== RequirePermission ====================

func TestRequirePermission_有权限通过(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(RequirePermission(&mockChecker{result: true}, "devices", "view"))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
}

func TestRequirePermission_无权限返回403(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(RequirePermission(&mockChecker{result: false}, "devices", "edit"))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 403, w.Code)
	body := parseResp(t, w)
	assert.Contains(t, body["message"], "权限不足")
}

func TestRequirePermission_未认证返回403(t *testing.T) {
	r := gin.New()
	// 不设置 user_id
	r.Use(RequirePermission(&mockChecker{result: true}, "devices", "view"))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 403, w.Code)
}

// ==================== AutoPermission ====================

func TestAutoPermission_匹配路径且无权限时返回403(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(AutoPermission(&mockChecker{result: false}))
	r.GET("/api/v1/admin/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 403, w.Code)
}

func TestAutoPermission_匹配路径且有权限时通过(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(AutoPermission(&mockChecker{result: true}))
	r.GET("/api/v1/admin/test", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
}

func TestAutoPermission_认证自服务路径通过(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(AutoPermission(&mockChecker{result: false}))
	r.GET("/api/v1/auth/profile", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/auth/profile", nil)
	r.ServeHTTP(w, req)

	// 认证资料接口不属于业务资源 RBAC，由登录鉴权保护。
	assert.Equal(t, 200, w.Code)
}

func TestAutoPermission_未知受保护路径默认拒绝(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(AutoPermission(&mockChecker{result: true}))
	r.POST("/api/v1/new-sensitive-route", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/new-sensitive-route", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
	body := parseResp(t, w)
	assert.NotNil(t, body)
	assert.Equal(t, "unclassified protected route", body["message"])
}

func TestAutoPermission_未认证拒绝(t *testing.T) {
	r := gin.New()
	// 不设置 user_id
	r.Use(AutoPermission(&mockChecker{result: false}))
	r.GET("/api/v1/admin/test", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

// ==================== getActionFromMethod ====================

func TestGetActionFromMethod_表驱动(t *testing.T) {
	tests := []struct {
		method   string
		expected string
	}{
		{"GET", "view"},
		{"POST", "create"},
		{"PUT", "edit"},
		{"PATCH", "edit"},
		{"DELETE", "delete"},
		{"HEAD", "view"},
		{"OPTIONS", "view"},
	}

	for _, tc := range tests {
		t.Run(tc.method, func(t *testing.T) {
			assert.Equal(t, tc.expected, getActionFromMethod(tc.method))
		})
	}
}

func TestActionForRequest_命令型POST按编辑鉴权(t *testing.T) {
	paths := []string{
		"/api/v1/devices/SN001/control",
		"/api/v1/devices/SN001/unbind",
		"/api/v1/devices/batch/control",
		"/api/v1/devices/add-to-station",
		"/api/v1/devices/unbind-requests/3/approve",
		"/api/v1/alarms/9/acknowledge",
		"/api/v1/alarms/9/ignore",
		"/api/v1/work-orders/2/attachments",
		"/api/v1/work-orders/2/escalate",
	}
	for _, path := range paths {
		assert.Equal(t, "edit", actionForRequest(http.MethodPost, path), path)
	}
	assert.Equal(t, "create", actionForRequest(http.MethodPost, "/api/v1/work-orders"))
	assert.Equal(t, "create", actionForRequest(http.MethodPost, "/api/v1/devices/bind"))
}

// ==================== resource rules ====================

func TestResourceActionMap_包含预期前缀(t *testing.T) {
	expected := map[string]string{
		"/api/v1/admin/users":          "admin",
		"/api/v1/users":                "users",
		"/api/v1/ota/tasks":            "ota",
		"/api/v1/parallel":             "parallel",
		"/api/v1/models":               "models",
		"/api/v1/stations":             "stations",
		"/api/v1/devices":              "devices",
		"/api/v1/alarms":               "alerts",
		"/api/v1/work-orders/1/status": "work_orders",
	}

	for path, resource := range expected {
		assert.Equal(t, resource, resourceForPath(path), "路径映射错误: %s", path)
	}
}

func TestResourceActionMap_要求路径边界(t *testing.T) {
	assert.Empty(t, resourceForPath("/api/v1/users-export"))
	assert.Empty(t, resourceForPath("/api/v1/ota-admin"))
	assert.Empty(t, resourceForPath("/api/v1/devices2"))
}
