package middleware

import (
	"github.com/gin-gonic/gin"
)

// SecurityHeaders 添加安全响应头，防止常见Web攻击
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 防止点击劫持 - 禁止iframe嵌入
		c.Header("X-Frame-Options", "DENY")

		// 防止MIME类型嗅探
		c.Header("X-Content-Type-Options", "nosniff")

		// XSS保护（现代浏览器已弃用，但仍有兼容性价值）
		c.Header("X-XSS-Protection", "0")

		// 控制引用来源信息
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// 内容安全策略 - 基础配置
		// 注意：生产环境应根据实际需求调整
		c.Header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")

		// 权限策略 - 限制浏览器功能访问
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()")

		// 严格传输安全 - 仅在HTTPS环境下启用
		// 生产环境启用HTTPS后取消注释
		if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Header("Cache-Control", "no-store")

		c.Next()
	}
}
