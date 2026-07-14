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

		// 仅当 Origin 在允许列表中时才设置 CORS 响应头
		if origin != "" && originSet[origin] {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Credentials", "true")
		}
		// 不匹配的 Origin 不设置 CORS 头，浏览器会拒绝跨域请求

		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-Requested-With")
		c.Header("Access-Control-Expose-Headers", "Content-Length, Content-Type")
		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
