package middleware

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestTokenBucket_BasicAllow(t *testing.T) {
	tb := newTokenBucket(10, 5)

	// burst=5，前5次应该全部通过
	for i := 0; i < 5; i++ {
		assert.True(t, tb.allow(), "request %d should be allowed", i)
	}

	// 第6次应该被拒绝（burst已耗尽）
	assert.False(t, tb.allow(), "request beyond burst should be denied")
}

func TestTokenBucket_Refill(t *testing.T) {
	tb := newTokenBucket(100, 2) // 每秒100个令牌，burst=2

	// 耗尽令牌
	tb.allow()
	tb.allow()
	assert.False(t, tb.allow())

	// 手动模拟时间推移来回填令牌
	tb.mu.Lock()
	tb.tokens = 1.0
	tb.mu.Unlock()

	assert.True(t, tb.allow())
	assert.False(t, tb.allow())
}

func TestTokenBucket_CapAtBurst(t *testing.T) {
	tb := newTokenBucket(1000, 3)

	// 手动将 tokens 设为超过 burst 的值
	tb.mu.Lock()
	tb.tokens = 100
	tb.mu.Unlock()

	// allow() 后 tokens 应被截断到 burst 值
	tb.allow()
	tb.mu.Lock()
	assert.LessOrEqual(t, tb.tokens, float64(tb.burst))
	tb.mu.Unlock()
}

func TestRateLimit_Middleware(t *testing.T) {
	router := gin.New()
	router.Use(RateLimit(10, 3))
	router.GET("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	// 前3次（burst）应该通过
	for i := 0; i < 3; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/test", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "request %d should pass", i)
	}

	// 第4次应被限流
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusTooManyRequests, w.Code)
}

func TestRouteRateLimits_IndependentBuckets(t *testing.T) {
	rules := []RouteRateLimitConfig{
		{PathPrefix: "/api/v1/auth/", Rate: 10, Burst: 2},
		{PathPrefix: "/api/v1/devices", Rate: 10, Burst: 2},
	}

	router := gin.New()
	router.Use(RouteRateLimits(rules))
	router.POST("/api/v1/auth/login", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	// 耗尽 auth 限流
	for i := 0; i < 2; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/auth/login", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	}

	// auth 应被限流
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/auth/login", nil)
	router.ServeHTTP(w, req)
	assert.Equal(t, http.StatusTooManyRequests, w.Code)

	// devices 仍应通过（独立桶）
	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	router.ServeHTTP(w2, req2)
	assert.Equal(t, http.StatusOK, w2.Code)
}

func TestRouteRateLimits_UnmatchedPath(t *testing.T) {
	rules := []RouteRateLimitConfig{
		{PathPrefix: "/api/v1/auth/", Rate: 10, Burst: 1},
	}

	router := gin.New()
	router.Use(RouteRateLimits(rules))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	// 不匹配任何规则的路径不受限流影响
	for i := 0; i < 10; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	}
}

func TestRateLimit_ConcurrentSafety(t *testing.T) {
	tb := newTokenBucket(1000, 100)

	var allowed int64
	var wg sync.WaitGroup

	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if tb.allow() {
				atomic.AddInt64(&allowed, 1)
			}
		}()
	}

	wg.Wait()

	// 初始 burst=100，加上少量 refill，允许数量应接近100
	assert.LessOrEqual(t, allowed, int64(110))
	assert.Greater(t, allowed, int64(0))
}
