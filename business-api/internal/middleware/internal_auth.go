package middleware

import (
	"crypto/subtle"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// InternalAuth authenticates service-to-service requests with the validated
// internal key from application configuration. An empty key always fails
// closed. Constant-time comparison avoids leaking key prefixes through timing.
func InternalAuth(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := c.GetHeader("X-Internal-Key")
		valid := secret != "" && key != "" && len(key) == len(secret) &&
			subtle.ConstantTimeCompare([]byte(key), []byte(secret)) == 1
		if !valid {
			response.Unauthorized(c, "invalid internal key")
			c.Abort()
			return
		}
		c.Next()
	}
}
