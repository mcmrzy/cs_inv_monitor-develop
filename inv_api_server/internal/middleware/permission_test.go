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

func TestAutoPermission_不匹配路径直接通过(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("user_id", int64(1))
		c.Next()
	})
	r.Use(AutoPermission(&mockChecker{result: false}))
	r.GET("/api/v1/devices", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	r.ServeHTTP(w, req)

	// /api/v1/devices 不在 resourceActionMap 中，应直接通过
	assert.Equal(t, 200, w.Code)
}

func TestAutoPermission_未认证直接通过(t *testing.T) {
	r := gin.New()
	// 不设置 user_id
	r.Use(AutoPermission(&mockChecker{result: false}))
	r.GET("/api/v1/admin/test", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/admin/test", nil)
	r.ServeHTTP(w, req)

	// 无 user_id 时 AutoPermission 应直接 c.Next()
	assert.Equal(t, 200, w.Code)
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

// ==================== resourceActionMap ====================

func TestResourceActionMap_包含预期前缀(t *testing.T) {
	expectedPrefixes := []string{
		"/api/v1/admin/",
		"/api/v1/users/",
		"/api/v1/ota/",
		"/api/v1/parallel/",
		"/api/v1/models",
	}

	for _, prefix := range expectedPrefixes {
		_, exists := resourceActionMap[prefix]
		assert.True(t, exists, "resourceActionMap 应包含前缀: %s", prefix)
	}
}
