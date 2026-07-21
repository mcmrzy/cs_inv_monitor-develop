package middleware

import (
	"log"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		c.Next()

		latency := time.Since(start)
		status := c.Writer.Status()
		clientIP := c.ClientIP()
		method := c.Request.Method

		log.Printf("[GW] %3d | %13v | %15s | %-7s %s",
			status, latency, clientIP, method, path)
	}
}

func redactedQuery(values url.Values) string {
	if len(values) == 0 {
		return ""
	}
	copy := make(url.Values, len(values))
	for key, entries := range values {
		switch strings.ToLower(key) {
		case "token", "access_token", "refresh_token", "authorization", "code":
			copy[key] = []string{"[REDACTED]"}
		default:
			copy[key] = append([]string(nil), entries...)
		}
	}
	return copy.Encode()
}
