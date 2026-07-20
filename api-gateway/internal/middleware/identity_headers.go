package middleware

import "github.com/gin-gonic/gin"

var trustedIdentityHeaders = []string{
	"X-User-ID",
	"X-User-Phone",
	"X-User-Role",
	"X-User-Sub",
	"X-Token-JTI",
	"X-Token-Issued-At",
}

// SanitizeIdentityHeaders removes all client-supplied identity headers before
// route-specific JWT middleware reconstructs them from verified claims.
func SanitizeIdentityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		for _, header := range trustedIdentityHeaders {
			c.Request.Header.Del(header)
		}
		c.Next()
	}
}
