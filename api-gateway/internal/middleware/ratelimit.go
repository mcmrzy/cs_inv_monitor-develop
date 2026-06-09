package middleware

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type tokenBucket struct {
	rate       float64
	burst      int
	tokens     float64
	lastRefill time.Time
	mu         sync.Mutex
}

func newTokenBucket(rate float64, burst int) *tokenBucket {
	return &tokenBucket{
		rate:       rate,
		burst:      burst,
		tokens:     float64(burst),
		lastRefill: time.Now(),
	}
}

func (tb *tokenBucket) allow() bool {
	tb.mu.Lock()
	defer tb.mu.Unlock()

	now := time.Now()
	elapsed := now.Sub(tb.lastRefill).Seconds()
	tb.tokens += elapsed * tb.rate
	if tb.tokens > float64(tb.burst) {
		tb.tokens = float64(tb.burst)
	}
	tb.lastRefill = now

	if tb.tokens >= 1 {
		tb.tokens--
		return true
	}
	return false
}

func RateLimit(ratePerSec float64, burst int) gin.HandlerFunc {
	limiter := newTokenBucket(ratePerSec, burst)

	return func(c *gin.Context) {
		if !limiter.allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"code":    429,
				"message": "请求过于频繁，请稍后再试",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

type RouteRateLimitConfig struct {
	PathPrefix string
	Rate       float64
	Burst      int
}

func RouteRateLimits(rules []RouteRateLimitConfig) gin.HandlerFunc {
	limiters := make(map[string]*tokenBucket, len(rules))
	for _, rule := range rules {
		limiters[rule.PathPrefix] = newTokenBucket(rule.Rate, rule.Burst)
	}

	return func(c *gin.Context) {
		path := c.Request.URL.Path
		for prefix, limiter := range limiters {
			if strings.HasPrefix(path, prefix) {
				if !limiter.allow() {
					c.JSON(http.StatusTooManyRequests, gin.H{
						"code":    429,
						"message": "该接口请求过于频繁，请稍后再试",
					})
					c.Abort()
					return
				}
				break
			}
		}
		c.Next()
	}
}
