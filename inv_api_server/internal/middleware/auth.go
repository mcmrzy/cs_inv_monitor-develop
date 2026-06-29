package middleware

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

func Auth(jwtService *service.JWTService) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 从 Authorization header 或 httpOnly cookie 获取 token
		tokenStr := ""
		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) == 2 && parts[0] == "Bearer" {
				tokenStr = parts[1]
			}
		}
		if tokenStr == "" {
			tokenStr, _ = c.Cookie("access_token")
		}

		if tokenStr == "" {
			response.Unauthorized(c, "missing authorization")
			c.Abort()
			return
		}

		claims, err := jwtService.ParseToken(tokenStr)
		if err != nil {
			response.Unauthorized(c, "invalid token")
			c.Abort()
			return
		}

		jti := jwtService.GetJTI(claims)
		if jwtService.IsBlacklisted(c.Request.Context(), jti) {
			response.Unauthorized(c, "token has been revoked")
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("phone", claims.Phone)
		c.Set("role", claims.Role)
		c.Set("token_jti", jti)
		c.Next()
	}
}

func OptionalAuth(jwtService *service.JWTService) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Next()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			claims, err := jwtService.ParseToken(parts[1])
			if err == nil {
				jti := jwtService.GetJTI(claims)
				if !jwtService.IsBlacklisted(c.Request.Context(), jti) {
					c.Set("user_id", claims.UserID)
					c.Set("phone", claims.Phone)
					c.Set("role", claims.Role)
					c.Set("token_jti", jti)
				}
			}
		}
		c.Next()
	}
}

func RequireRole(minRole int) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			response.Unauthorized(c, "unauthorized")
			c.Abort()
			return
		}

		userRole, ok := role.(int)
		if !ok {
			response.Forbidden(c, "invalid role type")
			c.Abort()
			return
		}
		if userRole > minRole {
			response.Forbidden(c, "permission denied")
			c.Abort()
			return
		}

		c.Next()
	}
}

func GetUserID(c *gin.Context) int64 {
	v, exists := c.Get("user_id")
	if !exists {
		return 0
	}
	id, ok := v.(int64)
	if !ok {
		return 0
	}
	return id
}

func GetRole(c *gin.Context) int {
	v, exists := c.Get("role")
	if !exists {
		return 0
	}
	r, ok := v.(int)
	if !ok {
		return 0
	}
	return r
}

func CORS(allowedOrigins []string) gin.HandlerFunc {
	originSet := make(map[string]bool, len(allowedOrigins))
	for _, o := range allowedOrigins {
		originSet[o] = true
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if originSet[origin] {
			c.Header("Access-Control-Allow-Origin", origin)
		} else if len(allowedOrigins) == 0 {
			c.Header("Access-Control-Allow-Origin", "*")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")
		c.Header("Access-Control-Expose-Headers", "Content-Length, Access-Control-Allow-Origin, Access-Control-Allow-Headers, Content-Type")
		c.Header("Access-Control-Allow-Credentials", "true")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func RateLimit() gin.HandlerFunc {
	limiter := &ipRateLimiter{
		limiters: make(map[string]*tokenBucket),
		rate:     10,
		burst:    20,
	}
	return limiter.Handle()
}

type tokenBucket struct {
	rate       float64
	burst      int
	tokens     float64
	lastRefill time.Time
	mu         sync.Mutex
}

func (b *tokenBucket) allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	elapsed := now.Sub(b.lastRefill).Seconds()
	b.tokens += elapsed * b.rate
	if b.tokens > float64(b.burst) {
		b.tokens = float64(b.burst)
	}
	b.lastRefill = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

type ipRateLimiter struct {
	limiters map[string]*tokenBucket
	rate     float64
	burst    int
	mu       sync.RWMutex
	cleanup  time.Time
}

func (l *ipRateLimiter) getLimiter(ip string) *tokenBucket {
	l.mu.RLock()
	limiter, exists := l.limiters[ip]
	l.mu.RUnlock()

	if exists {
		return limiter
	}

	l.mu.Lock()
	defer l.mu.Unlock()

	limiter, exists = l.limiters[ip]
	if exists {
		return limiter
	}

	l.limiters[ip] = &tokenBucket{
		rate:       l.rate,
		burst:      l.burst,
		tokens:     float64(l.burst),
		lastRefill: time.Now(),
	}

	if time.Since(l.cleanup) > 5*time.Minute {
		l.cleanup = time.Now()
		l.cleanupStaleLimiters()
	}

	return l.limiters[ip]
}

func (l *ipRateLimiter) cleanupStaleLimiters() {
	for ip, limiter := range l.limiters {
		limiter.mu.Lock()
		if time.Since(limiter.lastRefill) > 10*time.Minute {
			delete(l.limiters, ip)
		}
		limiter.mu.Unlock()
	}
}

func (l *ipRateLimiter) Handle() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()
		limiter := l.getLimiter(ip)
		if !limiter.allow() {
			response.Error(c, 429, "请求过于频繁，请稍后再试")
			c.Abort()
			return
		}
		c.Next()
	}
}
