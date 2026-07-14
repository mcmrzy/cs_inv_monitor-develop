package middleware

import (
	"fmt"
	"strings"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

var resourceActionMap = map[string][2]string{
	"/api/v1/admin/":            {"admin", "manage"},
	"/api/v1/users/":            {"users", "view"},
	"/api/v1/ota/":              {"ota", "view"},
	"/api/v1/parallel/":         {"parallel", "view"},
	"/api/v1/models":            {"models", "view"},
	"/api/v1/field-catalog":     {"models", "view"},
	"/api/v1/protocol-versions": {"models", "view"},
	"/api/v1/alert-rules":       {"alert_rules", "view"},
	"/api/v1/work-orders":       {"work_orders", "view"},
}

func getActionFromMethod(method string) string {
	switch method {
	case "GET":
		return "view"
	case "POST":
		return "create"
	case "PUT", "PATCH":
		return "edit"
	case "DELETE":
		return "delete"
	default:
		return "view"
	}
}

type PermissionChecker interface {
	/* return true if user has permission for (resource, action) */
	CheckPermission(userID int64, resource string, action string) bool
}

func RequirePermission(checker PermissionChecker, resource string, action string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID, exists := c.Get("user_id")
		if !exists {
			response.Forbidden(c, "unauthorized")
			c.Abort()
			return
		}

		if !checker.CheckPermission(userID.(int64), resource, action) {
			response.Forbidden(c, fmt.Sprintf("权限不足: %s:%s", resource, action))
			c.Abort()
			return
		}
		c.Next()
	}
}

func AutoPermission(checker PermissionChecker) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID, exists := c.Get("user_id")
		if !exists {
			c.Next()
			return
		}

		path := c.Request.URL.Path

		for prefix, ra := range resourceActionMap {
			if strings.HasPrefix(path, prefix) {
				resource := ra[0]
				action := getActionFromMethod(c.Request.Method)

				uid, ok := userID.(int64)
				if !ok || checker == nil {
					c.Next()
					return
				}

				if !checker.CheckPermission(uid, resource, action) {
					response.Forbidden(c, fmt.Sprintf("权限不足: %s:%s", resource, action))
					c.Abort()
					return
				}
				break
			}
		}
		c.Next()
	}
}
