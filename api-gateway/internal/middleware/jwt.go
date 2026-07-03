package middleware

import (
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	jwt "github.com/golang-jwt/jwt/v5"
)

var publicPaths = map[string]bool{
	"/health":                      true,
	"/metrics":                     true,
	"/api/docs":                    true,
	"/api/v1/auth/login":           true,
	"/api/v1/auth/register":        true,
	"/api/v1/auth/send-code":       true,
	"/api/v1/auth/reset-password":  true,
	"/api/v1/auth/email-register":  true,
	"/api/v1/auth/email-login":     true,
	"/api/v1/auth/send-email-code": true,
	"/api/v1/timezones":            true,
}

var publicPrefixes = []string{
	"/uploads/",
	"/firmware/",
	"/ws/",
	"/api/v1/captcha/",
}

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
		if isPublicPath(c.Request.URL.Path) {
			c.Next()
			return
		}

		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			log.Printf("[DEBUG-INSTRUMENT] JWTAuth: %s %s - 缺少 Authorization 头", c.Request.Method, c.Request.URL.Path)
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "缺少 Authorization 请求头",
			})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			log.Printf("[DEBUG-INSTRUMENT] JWTAuth: %s %s - Authorization 格式错误", c.Request.Method, c.Request.URL.Path)
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "Authorization 格式错误，应为 Bearer <token>",
			})
			c.Abort()
			return
		}

		tokenString := parts[1]

		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("不支持的签名算法: %v", token.Header["alg"])
			}
			return []byte(secret), nil
		})

		if err != nil || !token.Valid {
			log.Printf("[DEBUG-INSTRUMENT] JWTAuth: %s %s - token 无效: %v", c.Request.Method, c.Request.URL.Path, err)
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "无效的 token",
			})
			c.Abort()
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			log.Printf("[DEBUG-INSTRUMENT] JWTAuth: %s %s - 无法解析 claims", c.Request.Method, c.Request.URL.Path)
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "无法解析 token claims",
			})
			c.Abort()
			return
		}

		if userID, exists := claims["user_id"]; exists {
			c.Request.Header.Set("X-User-ID", fmt.Sprintf("%v", userID))
		}
		if phone, exists := claims["phone"]; exists {
			c.Request.Header.Set("X-User-Phone", fmt.Sprintf("%v", phone))
		}
		if role, exists := claims["role"]; exists {
			c.Request.Header.Set("X-User-Role", fmt.Sprintf("%v", role))
		}
		if sub, exists := claims["sub"]; exists {
			c.Request.Header.Set("X-User-Sub", fmt.Sprintf("%v", sub))
		}

		log.Printf("[DEBUG-INSTRUMENT] JWTAuth: %s %s - user_id=%s role=%s",
			c.Request.Method, c.Request.URL.Path,
			c.GetHeader("X-User-ID"), c.GetHeader("X-User-Role"))
		c.Next()
	}
}
