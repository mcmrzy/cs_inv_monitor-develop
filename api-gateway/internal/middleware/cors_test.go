package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestCORSRejectsDisallowedPreflight(t *testing.T) {
	router := gin.New()
	router.Use(CORS([]string{"https://admin.example.com"}))
	router.GET("/data", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/data", nil)
	req.Header.Set("Origin", "https://evil.example")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
	assert.Empty(t, w.Header().Get("Access-Control-Allow-Origin"))
}

func TestCORSReflectsOnlyConfiguredOrigin(t *testing.T) {
	router := gin.New()
	router.Use(CORS([]string{"https://admin.example.com"}))
	router.GET("/data", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/data", nil)
	req.Header.Set("Origin", "https://admin.example.com")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "https://admin.example.com", w.Header().Get("Access-Control-Allow-Origin"))
	assert.Equal(t, "true", w.Header().Get("Access-Control-Allow-Credentials"))
}

// 发码/滑块验证接口依赖 X-Captcha-Token；前端切到 api 子域后该请求变成跨域，
// 头一旦不在白名单里，浏览器会在预检阶段直接拦掉请求。
func TestCORSPreflightAllowsCaptchaTokenHeader(t *testing.T) {
	router := gin.New()
	router.Use(CORS([]string{"https://www.example.com"}))
	router.POST("/api/v1/auth/send-code", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/auth/send-code", nil)
	req.Header.Set("Origin", "https://www.example.com")
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "content-type,x-captcha-token")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusNoContent, w.Code)
	allowed := strings.ToLower(w.Header().Get("Access-Control-Allow-Headers"))
	assert.Contains(t, allowed, "x-captcha-token")
	assert.Contains(t, allowed, "authorization")
}

func TestCORSDoesNotEnableCredentialedWildcard(t *testing.T) {
	router := gin.New()
	router.Use(CORS([]string{"*"}))
	router.GET("/data", func(c *gin.Context) { c.Status(http.StatusOK) })

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/data", nil)
	req.Header.Set("Origin", "https://any.example")
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusForbidden, w.Code)
	assert.Empty(t, w.Header().Get("Access-Control-Allow-Origin"))
}
