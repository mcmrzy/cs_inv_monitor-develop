package middleware

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/response"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeAccessContextValidator struct {
	valid bool
	err   error
}

func (f fakeAccessContextValidator) ValidateAuthorizationSessionContext(context.Context, model.AuthorizationSessionContext) (bool, error) {
	return f.valid, f.err
}

// ==================== test helpers ====================

func init() {
	gin.SetMode(gin.TestMode)
	gin.DisableConsoleColor()
}

func setupJWTService(t *testing.T) (*service.JWTService, *miniredis.Miniredis) {
	t.Helper()
	mr, err := miniredis.Run()
	require.NoError(t, err)

	jwtInstance := jwt.NewJWT(&jwt.JWTConfig{
		Secret:            "test-secret",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "test",
	})
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	return service.NewJWTService(jwtInstance, rdb), mr
}

func generateContextToken(t *testing.T, jwtSvc *service.JWTService, userID int64, phone string, role int) string {
	t.Helper()
	refreshToken, err := jwtSvc.GenerateRefreshTokenWithVersion(userID, 1)
	require.NoError(t, err)
	refreshClaims, err := jwtSvc.ParseRefreshToken(refreshToken)
	require.NoError(t, err)
	require.NoError(t, jwtSvc.StoreRefreshToken(context.Background(), userID, refreshToken, time.Hour))
	token, err := jwtSvc.GenerateContextAccessTokenForSession(userID, 100, 101, 102, 1, 1, 1, refreshClaims.SessionID, phone, role)
	require.NoError(t, err)
	return token
}

func parseResponseBody(t *testing.T, w *httptest.ResponseRecorder) response.Response {
	t.Helper()
	var resp response.Response
	err := json.Unmarshal(w.Body.Bytes(), &resp)
	require.NoError(t, err)
	return resp
}

// ==================== Auth 中间件 ====================

func TestAuth_合法Token通过(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	accessToken := generateContextToken(t, jwtSvc, 42, "13800138000", 5)

	r := gin.New()
	r.Use(Auth(jwtSvc))
	r.GET("/test", func(c *gin.Context) {
		userID := GetUserID(c)
		role := GetRole(c)
		phone := GetPhone(c)
		c.JSON(200, gin.H{"user_id": userID, "role": role, "phone": phone})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)

	var body map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, float64(42), body["user_id"])
	assert.Equal(t, float64(5), body["role"])
	assert.Equal(t, "13800138000", body["phone"])
}

func TestAuth_缺失Token返回401(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	r := gin.New()
	r.Use(Auth(jwtSvc))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 401, w.Code)
	resp := parseResponseBody(t, w)
	assert.Contains(t, resp.Message, "missing")
}

func TestAuth_无效Token返回401(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	r := gin.New()
	r.Use(Auth(jwtSvc))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer invalid.token.here")
	r.ServeHTTP(w, req)

	assert.Equal(t, 401, w.Code)
}

func TestAuth_被拉黑的Token返回401(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	accessToken := generateContextToken(t, jwtSvc, 1, "13800138000", 5)

	// 解析 token 获取 JTI 并拉黑
	claims, _ := jwtSvc.ParseToken(accessToken)
	jti := jwtSvc.GetJTI(claims)
	_ = jwtSvc.AddToBlacklist(t.Context(), jti, 15*time.Minute)

	r := gin.New()
	r.Use(Auth(jwtSvc))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	r.ServeHTTP(w, req)

	assert.Equal(t, 401, w.Code)
	resp := parseResponseBody(t, w)
	assert.Contains(t, resp.Message, "revoked")
}

func TestAuth_从Cookie读取Token(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	accessToken := generateContextToken(t, jwtSvc, 1, "13800138000", 5)

	r := gin.New()
	r.Use(Auth(jwtSvc))
	r.GET("/test", func(c *gin.Context) {
		c.JSON(200, gin.H{"user_id": GetUserID(c)})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.AddCookie(&http.Cookie{Name: "access_token", Value: accessToken})
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
}

func TestAuthRejectsRevokedAndUnavailableAuthorizationContext(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()
	accessToken := generateContextToken(t, jwtSvc, 1, "13800138000", 5)

	for _, test := range []struct {
		name      string
		validator fakeAccessContextValidator
		status    int
	}{
		{name: "version changed", validator: fakeAccessContextValidator{valid: false}, status: http.StatusUnauthorized},
		{name: "state store unavailable", validator: fakeAccessContextValidator{err: errors.New("db unavailable")}, status: http.StatusServiceUnavailable},
	} {
		t.Run(test.name, func(t *testing.T) {
			router := gin.New()
			router.Use(Auth(jwtSvc, test.validator))
			router.GET("/test", func(c *gin.Context) { c.Status(http.StatusOK) })
			request := httptest.NewRequest(http.MethodGet, "/test", nil)
			request.Header.Set("Authorization", "Bearer "+accessToken)
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			assert.Equal(t, test.status, recorder.Code)
		})
	}
}

// ==================== OptionalAuth 中间件 ====================

func TestOptionalAuth_无Token仍通过(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	r := gin.New()
	r.Use(OptionalAuth(jwtSvc))
	r.GET("/test", func(c *gin.Context) {
		_, exists := c.Get("user_id")
		c.JSON(200, gin.H{"has_user": exists})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
	var body map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, false, body["has_user"])
}

func TestOptionalAuth_合法Token注入用户信息(t *testing.T) {
	jwtSvc, mr := setupJWTService(t)
	defer mr.Close()

	accessToken := generateContextToken(t, jwtSvc, 7, "13900139000", 1)

	r := gin.New()
	r.Use(OptionalAuth(jwtSvc))
	r.GET("/test", func(c *gin.Context) {
		c.JSON(200, gin.H{"user_id": GetUserID(c), "role": GetRole(c)})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
	var body map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, float64(7), body["user_id"])
	assert.Equal(t, float64(1), body["role"])
}

// ==================== RequireRole 中间件 ====================

func TestRequireRole_允许同等角色(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("role", 1) // admin
		c.Next()
	})
	r.Use(RequireRole(1))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
}

func TestRequireRole_拒绝低权限角色(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("role", 5) // 普通用户
		c.Next()
	})
	r.Use(RequireRole(1)) // 需要 admin
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 403, w.Code)
	resp := parseResponseBody(t, w)
	assert.Contains(t, resp.Message, "permission denied")
}

func TestRequireRole_未认证返回401(t *testing.T) {
	r := gin.New()
	r.Use(RequireRole(1))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	assert.Equal(t, 401, w.Code)
}

// ==================== CORS 中间件 ====================

func TestCORS_匹配的Origin设置AllowHeader(t *testing.T) {
	r := gin.New()
	r.Use(CORS([]string{"https://example.com", "https://app.test"}))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Origin", "https://example.com")
	r.ServeHTTP(w, req)

	assert.Equal(t, "https://example.com", w.Header().Get("Access-Control-Allow-Origin"))
	assert.Equal(t, "true", w.Header().Get("Access-Control-Allow-Credentials"))
}

func TestCORS_不匹配的Origin不设置AllowOrigin(t *testing.T) {
	r := gin.New()
	r.Use(CORS([]string{"https://example.com"}))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Origin", "https://evil.com")
	r.ServeHTTP(w, req)

	assert.Empty(t, w.Header().Get("Access-Control-Allow-Origin"))
}

func TestCORS_空列表允许所有Origin(t *testing.T) {
	r := gin.New()
	r.Use(CORS([]string{}))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.Header.Set("Origin", "https://anything.com")
	r.ServeHTTP(w, req)

	assert.Equal(t, "*", w.Header().Get("Access-Control-Allow-Origin"))
}

func TestCORS_OPTIONS请求返回204(t *testing.T) {
	r := gin.New()
	r.Use(CORS([]string{"https://example.com"}))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("OPTIONS", "/test", nil)
	req.Header.Set("Origin", "https://example.com")
	r.ServeHTTP(w, req)

	assert.Equal(t, 204, w.Code)
}

// ==================== RateLimit 中间件 ====================

func TestRateLimit_正常请求通过(t *testing.T) {
	r := gin.New()
	r.Use(RateLimit())
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "1.2.3.4:1234"
	r.ServeHTTP(w, req)

	assert.Equal(t, 200, w.Code)
}

func TestRateLimit_超频请求被拒(t *testing.T) {
	// 直接测试 tokenBucket 行为
	bucket := &tokenBucket{
		rate:       10,
		burst:      20,
		tokens:     20,
		lastRefill: time.Now(),
	}

	// 前20个请求应通过
	for i := 0; i < 20; i++ {
		assert.True(t, bucket.allow(), "第 %d 个请求应通过", i+1)
	}

	// 第21个请求应被拒绝（tokens 已耗尽）
	assert.False(t, bucket.allow(), "第21个请求应被拒绝")

	// 等待一段时间让 token 恢复
	time.Sleep(150 * time.Millisecond) // 10 tokens/s * 0.15s = 1.5 tokens
	assert.True(t, bucket.allow(), "等待后应有新 token")
}

func TestRateLimitWith_使用自定义突发上限(t *testing.T) {
	r := gin.New()
	r.Use(RateLimitWith(0.01, 2))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	for i, wantStatus := range []int{200, 200, 429} {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/test", nil)
		req.RemoteAddr = "5.6.7.8:1234"
		r.ServeHTTP(w, req)
		assert.Equal(t, wantStatus, w.Code, "第 %d 个请求状态不符", i+1)
	}
}

func TestRateLimitWith_无效配置使用安全默认值(t *testing.T) {
	r := gin.New()
	r.Use(RateLimitWith(0, 0))
	r.GET("/test", func(c *gin.Context) { c.JSON(200, nil) })

	first := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "9.8.7.6:1234"
	r.ServeHTTP(first, req)
	assert.Equal(t, 200, first.Code)

	second := httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "9.8.7.6:1234"
	r.ServeHTTP(second, req)
	assert.Equal(t, 429, second.Code)
}

// ==================== 上下文 Helper ====================

func TestGetUserID_不存在返回0(t *testing.T) {
	r := gin.New()
	var got int64
	r.GET("/test", func(c *gin.Context) {
		got = GetUserID(c)
		c.JSON(200, nil)
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)
	assert.Equal(t, int64(0), got)
}

func TestGetUserID_类型不匹配返回0(t *testing.T) {
	r := gin.New()
	var got int64
	r.Use(func(c *gin.Context) {
		c.Set("user_id", "not-int64")
		c.Next()
	})
	r.GET("/test", func(c *gin.Context) {
		got = GetUserID(c)
		c.JSON(200, nil)
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)
	assert.Equal(t, int64(0), got)
}

func TestGetRole_不存在返回0(t *testing.T) {
	r := gin.New()
	var got int
	r.GET("/test", func(c *gin.Context) {
		got = GetRole(c)
		c.JSON(200, nil)
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)
	assert.Equal(t, 0, got)
}

func TestGetPhone_不存在返回空(t *testing.T) {
	r := gin.New()
	var got string
	r.GET("/test", func(c *gin.Context) {
		got = GetPhone(c)
		c.JSON(200, nil)
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)
	assert.Equal(t, "", got)
}
