package middleware

import (
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	jwt "github.com/golang-jwt/jwt/v5"
)

var publicPaths = map[string]bool{
	"/health": true, "/metrics": true, "/api/docs": true,
	"/api/v1/auth/login": true, "/api/v1/auth/register": true,
	"/api/v1/auth/send-code": true, "/api/v1/auth/reset-password": true,
	"/api/v1/auth/email-register": true, "/api/v1/auth/email-login": true,
	"/api/v1/auth/send-email-code": true, "/api/v1/auth/refresh": true,
	"/api/v1/timezones": true,
}

var publicPrefixes = []string{"/uploads/", "/firmware/", "/ws/", "/api/v1/captcha/"}

func isPublicPath(path string) bool {
	if publicPaths[path] {
		return true
	}
	for _, prefix := range publicPrefixes {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

func JWTAuth(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		for _, header := range trustedIdentityHeaders {
			c.Request.Header.Del(header)
		}
		if isPublicPath(c.Request.URL.Path) {
			c.Next()
			return
		}

		parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "Authorization 格式错误，应为 Bearer <token>"})
			return
		}
		token, err := jwt.Parse(parts[1], func(token *jwt.Token) (interface{}, error) {
			if token.Method.Alg() != jwt.SigningMethodHS256.Alg() {
				return nil, fmt.Errorf("unsupported signing algorithm: %v", token.Header["alg"])
			}
			return []byte(secret), nil
		})
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "无效的 token"})
			return
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "无法解析 token claims"})
			return
		}
		tokenType, ok := safeClaimString(claims["token_type"], 16)
		if !ok || tokenType != "access" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "token 类型无效"})
			return
		}
		jti, ok := safeClaimString(claims["jti"], 128)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "token 缺少撤销标识"})
			return
		}
		issuedAt, ok := positiveIntegerClaim(claims["session_iat_ms"])
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "token 缺少会话签发时间"})
			return
		}
		userID, ok := positiveIntegerClaim(claims["user_id"])
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "token 缺少用户标识"})
			return
		}
		role, ok := integerClaim(claims["role"])
		if !ok || role < 0 || role > 5 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "token 角色无效"})
			return
		}

		c.Request.Header.Set("X-Token-JTI", jti)
		c.Request.Header.Set("X-Token-Issued-At", strconv.FormatInt(issuedAt, 10))
		c.Request.Header.Set("X-User-ID", strconv.FormatInt(userID, 10))
		c.Request.Header.Set("X-User-Role", strconv.FormatInt(role, 10))
		if phone, exists := claims["phone"]; exists {
			if value, valid := safeClaimString(phone, 128); valid {
				c.Request.Header.Set("X-User-Phone", value)
			}
		}
		if sub, exists := claims["sub"]; exists {
			if value, valid := safeClaimString(sub, 128); valid {
				c.Request.Header.Set("X-User-Sub", value)
			}
		}
		c.Next()
	}
}

func positiveIntegerClaim(value any) (int64, bool) {
	parsed, ok := integerClaim(value)
	return parsed, ok && parsed > 0
}

func integerClaim(value any) (int64, bool) {
	switch typed := value.(type) {
	case float64:
		if typed != math.Trunc(typed) || typed > math.MaxInt64 || typed < math.MinInt64 {
			return 0, false
		}
		return int64(typed), true
	case string:
		parsed, err := strconv.ParseInt(typed, 10, 64)
		return parsed, err == nil
	default:
		return 0, false
	}
}

func safeClaimString(value any, maxLength int) (string, bool) {
	text, ok := value.(string)
	if !ok || text == "" || len(text) > maxLength || strings.ContainsAny(text, "\r\n\x00") {
		return "", false
	}
	return text, true
}
