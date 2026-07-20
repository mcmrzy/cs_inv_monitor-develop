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

type clientLimiter struct {
	mu          sync.Mutex
	limiters    map[string]*tokenBucket
	rate        float64
	burst       int
	lastCleanup time.Time
}

func newClientLimiter(rate float64, burst int) *clientLimiter {
	return &clientLimiter{
		limiters:    make(map[string]*tokenBucket),
		rate:        rate,
		burst:       burst,
		lastCleanup: time.Now(),
	}
}

func (l *clientLimiter) get(key string) *tokenBucket {
	l.mu.Lock()
	defer l.mu.Unlock()

	if limiter, ok := l.limiters[key]; ok {
		return limiter
	}
	limiter := newTokenBucket(l.rate, l.burst)
	l.limiters[key] = limiter

	if time.Since(l.lastCleanup) > 5*time.Minute {
		cutoff := time.Now().Add(-10 * time.Minute)
		for clientKey, bucket := range l.limiters {
			bucket.mu.Lock()
			stale := bucket.lastRefill.Before(cutoff)
			bucket.mu.Unlock()
			if stale {
				delete(l.limiters, clientKey)
			}
		}
		l.lastCleanup = time.Now()
	}
	return limiter
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
	limiter := newClientLimiter(ratePerSec, burst)

	return func(c *gin.Context) {
		if !limiter.get(c.ClientIP()).allow() {
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
	limiters := make(map[string]*clientLimiter, len(rules))
	for _, rule := range rules {
		limiters[rule.PathPrefix] = newClientLimiter(rule.Rate, rule.Burst)
	}

	return func(c *gin.Context) {
		path := c.Request.URL.Path
		for prefix, limiter := range limiters {
			if strings.HasPrefix(path, prefix) {
				key := prefix + "\x00" + c.ClientIP()
				if !limiter.get(key).allow() {
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
