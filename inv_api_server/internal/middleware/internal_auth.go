package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"os"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

func InternalAuth() gin.HandlerFunc {
	secret := os.Getenv("INTERNAL_API_SECRET")
	if secret == "" {
		randomBytes := make([]byte, 32)
		if _, err := rand.Read(randomBytes); err != nil {
			log.Printf("[WARN] INTERNAL_API_SECRET is empty and failed to generate random key, internal API will be inaccessible")
			secret = "inaccessible-no-valid-key-configured"
		} else {
			secret = hex.EncodeToString(randomBytes)
			log.Printf("[WARN] INTERNAL_API_SECRET is not set, using random key. Internal API calls will fail unless the env var is configured.")
		}
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