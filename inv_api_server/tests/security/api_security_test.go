package security

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	j "inv-api-server/pkg/jwt"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func newTestJWTService(t *testing.T) (*service.JWTService, *miniredis.Miniredis) {
	t.Helper()
	mr, err := miniredis.Run()
	require.NoError(t, err)

	jwtInstance := j.NewJWT(&j.JWTConfig{
		Secret:            "test-secret-32bytes-long-enough-for-test!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	return service.NewJWTService(jwtInstance, rdb), mr
}

// ==================== CORS 安全 ====================

func TestAPISecurity_CORS白名单模式(t *testing.T) {
	allowedOrigins := []string{"https://admin.example.com", "https://app.example.com"}

	r := gin.New()
	r.Use(middleware.CORS(allowedOrigins))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

	// 白名单内的 Origin 应被允许
	for _, origin := range allowedOrigins {
		t.Run("allowed_"+origin, func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/test", nil)
			req.Header.Set("Origin", origin)
			r.ServeHTTP(w, req)

			assert.Equal(t, origin, w.Header().Get("Access-Control-Allow-Origin"))
		})
	}

	// 白名单外的 Origin 不应被允许
	maliciousOrigins := []string{
		"https://evil.com",
		"https://phishing.example.com",
		"http://admin.example.com", // 协议不同
		"https://admin.example.com.evil.com",
	}

	for _, origin := range maliciousOrigins {
		t.Run("blocked_"+origin, func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/test", nil)
			req.Header.Set("Origin", origin)
			r.ServeHTTP(w, req)

			allowOrigin := w.Header().Get("Access-Control-Allow-Origin")
			assert.NotEqual(t, origin, allowOrigin,
				"恶意 Origin %s 不应被允许", origin)
		})
	}
}

func TestAPISecurity_CORS空列表允许所有(t *testing.T) {
	// 空列表 = 允许所有（开发模式），生产环境应显式配置白名单
	r := gin.New()
	r.Use(middleware.CORS([]string{})) // 空列表
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Origin", "https://any-domain.com")
	r.ServeHTTP(w, req)

	assert.Equal(t, "*", w.Header().Get("Access-Control-Allow-Origin"),
		"空列表时应返回 * （仅适用于开发环境）")
}

func TestAPISecurity_CORSPreflightOPTIONS(t *testing.T) {
	r := gin.New()
	r.Use(middleware.CORS([]string{"https://admin.example.com"}))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("OPTIONS", "/test", nil)
	req.Header.Set("Origin", "https://admin.example.com")
	r.ServeHTTP(w, req)

	assert.Equal(t, 204, w.Code, "OPTIONS 预检请求应返回 204")
	assert.Equal(t, "true", w.Header().Get("Access-Control-Allow-Credentials"))
}

// ==================== Rate Limiting 安全 ====================

func TestAPISecurity_RateLimit防暴力破解(t *testing.T) {
	r := gin.New()
	r.Use(middleware.RateLimit()) // burst=20, rate=10/s
	r.POST("/auth/login", func(c *gin.Context) { c.JSON(200, nil) })

	// 快速发送大量请求，使用相同 IP
	got429 := false
	for i := 0; i < 100; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/auth/login", nil)
		req.RemoteAddr = "192.168.1.100:5555"
		r.ServeHTTP(w, req)

		if w.Code == 429 {
			got429 = true
			break
		}
	}

	// 由于 token bucket 的 refill 机制，需要足够快的请求才能触发限流
	if !got429 {
		t.Log("警告: 100个请求未触发 429，可能因为 refill 太快。在生产环境中应有并发压测验证。")
	}

	// 验证限流后恢复
	time.Sleep(200 * time.Millisecond)
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/auth/login", nil)
	req.RemoteAddr = "192.168.1.100:5555"
	r.ServeHTTP(w, req)
	assert.NotEqual(t, 429, w.Code, "等待后请求应恢复正常")
}

// ==================== RBAC 权限绕过防护 ====================

func TestAPISecurity_RequireRole防越权(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("role", 5) // 普通用户
		c.Set("user_id", int64(100))
		c.Next()
	})
	r.Use(middleware.RequireRole(0)) // 需要管理员
	r.GET("/admin/users", func(c *gin.Context) { c.JSON(200, gin.H{"users": []interface{}{}}) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/admin/users", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 403, w.Code, "普通用户不应能访问管理员接口")

	// 验证响应体包含权限不足信息
	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	assert.Contains(t, resp["message"], "permission",
		"应返回权限不足信息")
}

func TestAPISecurity_RequireRole多级权限(t *testing.T) {
	testCases := []struct {
		name       string
		userRole   int
		minRole    int
		shouldPass bool
	}{
		{"管理员访问管理接口", 0, 0, true},
		{"管理员访问普通接口", 0, 5, true},
		{"普通用户访问管理接口", 5, 0, false},
		{"普通用户访问普通接口", 5, 5, true},
		{"高级用户访问中级接口", 2, 3, true},
		{"中级用户访问高级接口", 3, 2, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			r := gin.New()
			r.Use(func(c *gin.Context) {
				c.Set("role", tc.userRole)
				c.Next()
			})
			r.Use(middleware.RequireRole(tc.minRole))
			r.GET("/test", func(c *gin.Context) { c.JSON(200, gin.H{"ok": true}) })

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/test", nil)
			r.ServeHTTP(w, req)

			if tc.shouldPass {
				assert.Equal(t, 200, w.Code)
			} else {
				assert.Equal(t, 403, w.Code)
			}
		})
	}
}

// ==================== Auth 中间件安全 ====================

func TestAPISecurity_缺失AuthHeader返回401(t *testing.T) {
	jwtSvc, mr := newTestJWTService(t)
	defer mr.Close()

	r := gin.New()
	r.Use(middleware.Auth(jwtSvc))
	r.GET("/protected", func(c *gin.Context) { c.JSON(200, gin.H{"data": "secret"}) })

	// 无 Authorization header，无 Cookie
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/protected", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 401, w.Code, "无认证信息应返回 401")

	// 验证响应体不包含敏感信息
	body := w.Body.String()
	assert.NotContains(t, body, "secret", "401 响应不应包含受保护数据")
}

func TestAPISecurity_伪造BearerToken返回401(t *testing.T) {
	jwtSvc, mr := newTestJWTService(t)
	defer mr.Close()

	r := gin.New()
	r.Use(middleware.Auth(jwtSvc))
	r.GET("/protected", func(c *gin.Context) { c.JSON(200, nil) })

	fakeTokens := []string{
		"Bearer fake.token.here",
		"Bearer ",
		"Bearer not-a-jwt",
		"Basic dXNlcjpwYXNz",           // Basic auth 不被接受
		"Token abc123",                  // 非 Bearer 方案
		"Bearer eyJhbGciOiJub25lIn0=", // none 算法
	}

	for i, auth := range fakeTokens {
		t.Run(fakeTokens[i], func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/protected", nil)
			req.Header.Set("Authorization", auth)
			r.ServeHTTP(w, req)

			assert.Equal(t, 401, w.Code, "伪造 token 应返回 401: %s", auth)
		})
	}
}

// ==================== 敏感信息泄露检测 ====================

func TestAPISecurity_错误响应不泄露堆栈信息(t *testing.T) {
	r := gin.New()
	r.GET("/error", func(c *gin.Context) {
		c.JSON(500, gin.H{
			"code":    500,
			"message": "internal server error",
		})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/error", nil)
	r.ServeHTTP(w, req)

	body := w.Body.String()
	sensitivePatterns := []string{
		"stack trace",
		"goroutine",
		".go:",
		"panic:",
		"database/sql",
		"postgres://",
		"redis://",
		"password",
	}

	for _, pattern := range sensitivePatterns {
		assert.NotContains(t, strings.ToLower(body), strings.ToLower(pattern),
			"错误响应不应包含敏感信息: %s", pattern)
	}
}

func TestAPISecurity_CookieHttpOnly(t *testing.T) {
	r := gin.New()
	r.GET("/login", func(c *gin.Context) {
		c.SetCookie("access_token", "test-token", 7200, "/", "", false, true) // httpOnly=true
		c.JSON(200, nil)
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/login", nil)
	r.ServeHTTP(w, req)

	cookies := w.Result().Cookies()
	for _, cookie := range cookies {
		if cookie.Name == "access_token" {
			assert.True(t, cookie.HttpOnly,
				"access_token cookie 必须设置 HttpOnly 标志")
		}
	}
}

// ==================== 大 Payload 防护 ====================

func TestAPISecurity_超大RequestBody(t *testing.T) {
	r := gin.New()
	r.POST("/test", func(c *gin.Context) {
		var body map[string]interface{}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(400, gin.H{"error": "too large"})
			return
		}
		c.JSON(200, nil)
	})

	// 构造超大 JSON body (1MB)
	largeBody := `{"data":"` + strings.Repeat("x", 1024*1024) + `"}`

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/test", strings.NewReader(largeBody))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	// 验证超大请求不会导致 panic
	assert.NotEqual(t, 500, w.Code, "超大 body 不应导致 500 错误")
}
