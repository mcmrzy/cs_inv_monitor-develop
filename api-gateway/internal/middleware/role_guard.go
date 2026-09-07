package middleware

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// RequireRole 角色组准入中间件
// maxRole: 允许通过的最大角色值（role <= maxRole 放行，role > maxRole 拒绝）
// 角色语义: 0=super_admin, 1=admin, 2+=user
// 读取 JWT 中间件注入的 X-Is-System-Admin 请求头，转换失败默认拒绝（安全侧）
func RequireRole(maxRole int) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 检查是否是系统管理员（超级管理员）
		isSystemAdminStr := c.GetHeader("X-Is-System-Admin")
		if isSystemAdminStr == "true" {
			c.Next()
			return
		}
		
		// 如果不是系统管理员，检查角色
		roleStr := c.GetHeader("X-User-Role")
		role, err := strconv.Atoi(roleStr)
		if err != nil || role > maxRole {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "权限不足，需要更高角色",
			})
			return
		}
		c.Next()
	}
}
