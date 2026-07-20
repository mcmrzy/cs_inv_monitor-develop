package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// BodyLimit bounds request bodies before they reach a reverse proxy. JSON APIs
// use a conservative default while the two authenticated upload flows receive
// explicit, independently bounded limits.
func BodyLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		const (
			defaultLimit         = int64(2 << 20)
			firmwareUploadLimit  = int64(201 << 20)
			workOrderUploadLimit = int64(51 << 20)
		)
		limit := defaultLimit
		path := c.Request.URL.Path
		if c.Request.Method == http.MethodPost && (path == "/api/v1/ota/firmware" || path == "/api/v1/firmwares") {
			limit = firmwareUploadLimit
		} else if c.Request.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/work-orders/") && strings.HasSuffix(path, "/attachments") {
			limit = workOrderUploadLimit
		}
		if c.Request.ContentLength > limit {
			c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{"error": "request body too large"})
			return
		}
		if c.Request.Body != nil {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, limit)
		}
		c.Next()
	}
}
