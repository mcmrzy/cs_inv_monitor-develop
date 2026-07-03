package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// CORS 创建CORS中间件，支持配置允许的来源
func CORS(allowedOrigins []string) gin.HandlerFunc {
	// 将允许的来源列表转换为map，提高查找效率
	originSet := make(map[string]bool, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		originSet[origin] = true
	}

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		
		// 检查请求的Origin是否在允许列表中
		if origin != "" && originSet[origin] {
			c.Header("Access-Control-Allow-Origin", origin)
		} else if len(allowedOrigins) > 0 {
			// 如果有配置的允许来源但不匹配，使用第一个作为默认（可选策略）
			// 或者可以不设置header来拒绝请求
			c.Header("Access-Control-Allow-Origin", allowedOrigins[0])
		}
		
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Requested-With")
		c.Header("Access-Control-Expose-Headers", "Content-Length, Content-Type")
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
