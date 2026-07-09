package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
)

const testSecret = "test-secret-key-for-unit-tests"

func init() {
	gin.SetMode(gin.TestMode)
}

// makeToken 生成测试用 JWT token
func makeToken(claims jwt.MapClaims, secret string) string {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := token.SignedString([]byte(secret))
	return signed
}

func TestJWTAuth_ValidToken(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"user_id": c.GetHeader("X-User-ID"),
			"role":    c.GetHeader("X-User-Role"),
			"phone":   c.GetHeader("X-User-Phone"),
		})
	})

	token := makeToken(jwt.MapClaims{
		"user_id": float64(42),
		"role":    float64(1),
		"phone":   "13800001111",
		"exp":     float64(time.Now().Add(time.Hour).Unix()),
	}, testSecret)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var body map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, "42", body["user_id"])
	assert.Equal(t, "1", body["role"])
	assert.Equal(t, "13800001111", body["phone"])
}

func TestJWTAuth_ExpiredToken(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	token := makeToken(jwt.MapClaims{
		"user_id": float64(1),
		"exp":     float64(time.Now().Add(-time.Hour).Unix()),
	}, testSecret)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestJWTAuth_ForgedToken(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	// 用不同的 secret 签名
	token := makeToken(jwt.MapClaims{
		"user_id": float64(1),
		"exp":     float64(time.Now().Add(time.Hour).Unix()),
	}, "wrong-secret")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestJWTAuth_MissingAuthHeader(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestJWTAuth_InvalidAuthFormat(t *testing.T) {
	tests := []struct {
		name   string
		header string
	}{
		{"no Bearer prefix", "some-token"},
		{"empty Bearer", "Bearer "},
		{"only Bearer", "Bearer"},
	}

	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
			req.Header.Set("Authorization", tt.header)
			router.ServeHTTP(w, req)

			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestJWTAuth_PublicPaths(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.GET("/api/v1/auth/login", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	tests := []struct {
		name string
		path string
	}{
		{"health", "/health"},
		{"login", "/api/v1/auth/login"},
		{"metrics", "/metrics"},
		{"captcha prefix", "/api/v1/captcha/generate"},
		{"uploads prefix", "/uploads/image.png"},
		{"firmware prefix", "/firmware/v1.bin"},
		{"ws prefix", "/ws/conn"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", tt.path, nil)
			router.ServeHTTP(w, req)

			// 公开路径不应返回 401
			assert.NotEqual(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestJWTAuth_ClaimsPropagation(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/stations", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"x-user-id":    c.GetHeader("X-User-ID"),
			"x-user-role":  c.GetHeader("X-User-Role"),
			"x-user-phone": c.GetHeader("X-User-Phone"),
			"x-user-sub":   c.GetHeader("X-User-Sub"),
		})
	})

	token := makeToken(jwt.MapClaims{
		"user_id": float64(99),
		"role":    float64(0),
		"phone":   "13900000000",
		"sub":     "user-abc",
		"exp":     float64(time.Now().Add(time.Hour).Unix()),
	}, testSecret)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/stations", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var body map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, "99", body["x-user-id"])
	assert.Equal(t, "0", body["x-user-role"])
	assert.Equal(t, "13900000000", body["x-user-phone"])
	assert.Equal(t, "user-abc", body["x-user-sub"])
}

func TestIsPublicPath(t *testing.T) {
	tests := []struct {
		path   string
		expect bool
	}{
		{"/health", true},
		{"/metrics", true},
		{"/api/v1/auth/login", true},
		{"/api/v1/auth/register", true},
		{"/api/v1/timezones", true},
		{"/uploads/test.png", true},
		{"/firmware/v1.bin", true},
		{"/ws/conn", true},
		{"/api/v1/captcha/generate", true},
		{"/api/v1/devices", false},
		{"/api/v1/admin/users", false},
		{"/api/v1/stations", false},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			assert.Equal(t, tt.expect, isPublicPath(tt.path))
		})
	}
}
