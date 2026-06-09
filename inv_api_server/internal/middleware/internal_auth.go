package middleware

import (
	"os"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

func InternalAuth() gin.HandlerFunc {
	secret := os.Getenv("INTERNAL_API_SECRET")
	if secret == "" {
		secret = "default-internal-secret-change-me"
	}

	return func(c *gin.Context) {
		key := c.GetHeader("X-Internal-Key")
		if key == "" || key != secret {
			response.Unauthorized(c, "invalid internal key")
			c.Abort()
			return
		}
		c.Next()
	}
}