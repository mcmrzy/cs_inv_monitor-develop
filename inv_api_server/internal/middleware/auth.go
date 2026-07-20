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
		token := ""
		if parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2); len(parts) == 2 && parts[0] == "Bearer" {
			token = parts[1]
		}
		if token == "" {
			token, _ = c.Cookie("access_token")
		}
		if token == "" {
			response.Unauthorized(c, "missing authorization")
			c.Abort()
			return
		}
		claims, err := jwtService.ParseAccessToken(token)
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
		revoked, err := jwtService.IsUserSessionRevoked(c.Request.Context(), claims.UserID, claims.SessionIAT)
		if err != nil {
			response.InternalError(c, "session validation unavailable")
			c.Abort()
			return
		}
		if revoked {
			response.Unauthorized(c, "user session has been revoked")
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
		parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			if claims, err := jwtService.ParseAccessToken(parts[1]); err == nil {
				jti := jwtService.GetJTI(claims)
				revoked, sessionErr := jwtService.IsUserSessionRevoked(c.Request.Context(), claims.UserID, claims.SessionIAT)
				if sessionErr == nil && !revoked && !jwtService.IsBlacklisted(c.Request.Context(), jti) {
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
		if !ok || userRole > minRole {
			response.Forbidden(c, "permission denied")
			c.Abort()
			return
		}
		c.Next()
	}
}

func GetUserID(c *gin.Context) int64 {
	value, exists := c.Get("user_id")
	if !exists {
		return 0
	}
	id, ok := value.(int64)
	if !ok {
		return 0
	}
	return id
}

func GetRole(c *gin.Context) int {
	value, exists := c.Get("role")
	if !exists {
		return -1
	}
	role, ok := value.(int)
	if !ok {
		return -1
	}
	return role
}

func GetPhone(c *gin.Context) string {
	value, exists := c.Get("phone")
	if !exists {
		return ""
	}
	phone, ok := value.(string)
	if !ok {
		return ""
	}
	return phone
}

func CORS(allowedOrigins []string) gin.HandlerFunc {
	originSet := make(map[string]bool, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		origin = strings.TrimSpace(origin)
		if origin != "" && origin != "*" {
			originSet[origin] = true
		}
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		allowed := origin != "" && originSet[origin]
		if allowed {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
			c.Header("Access-Control-Allow-Credentials", "true")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")
		c.Header("Access-Control-Expose-Headers", "Content-Length, Access-Control-Allow-Origin, Access-Control-Allow-Headers, Content-Type")
		if c.Request.Method == http.MethodOptions {
			if !allowed {
				c.AbortWithStatus(http.StatusForbidden)
				return
			}
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func RateLimit() gin.HandlerFunc { return RateLimitWith(10, 20) }

func RateLimitWith(rate float64, burst int) gin.HandlerFunc {
	if rate <= 0 {
		rate = 1
	}
	if burst <= 0 {
		burst = 1
	}
	return (&ipRateLimiter{limiters: make(map[string]*tokenBucket), rate: rate, burst: burst}).Handle()
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
	b.tokens += now.Sub(b.lastRefill).Seconds() * b.rate
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
	if limiter, exists = l.limiters[ip]; exists {
		return limiter
	}
	limiter = &tokenBucket{rate: l.rate, burst: l.burst, tokens: float64(l.burst), lastRefill: time.Now()}
	l.limiters[ip] = limiter
	if time.Since(l.cleanup) > 5*time.Minute {
		l.cleanup = time.Now()
		l.cleanupStaleLimiters()
	}
	return limiter
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
		if !l.getLimiter(c.ClientIP()).allow() {
			response.TooManyRequests(c, "请求过于频繁，请稍后再试")
			c.Abort()
			return
		}
		c.Next()
	}
}
