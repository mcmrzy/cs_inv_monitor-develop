package middleware

import (
	"fmt"
	"strings"

	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type resourceRule struct {
	prefix   string
	resource string
}

var resourceRules = []resourceRule{
	{prefix: "/api/v1/admin", resource: "admin"},
	{prefix: "/api/v1/users", resource: "users"},
	{prefix: "/api/v1/ota", resource: "ota"},
	{prefix: "/api/v1/parallel", resource: "parallel"},
	{prefix: "/api/v1/models", resource: "models"},
	{prefix: "/api/v1/field-catalog", resource: "models"},
	{prefix: "/api/v1/protocol-versions", resource: "models"},
	{prefix: "/api/v1/stations", resource: "stations"},
	{prefix: "/api/v1/devices", resource: "devices"},
	{prefix: "/api/v1/alarms", resource: "alerts"},
	{prefix: "/api/v1/alerts", resource: "alerts"},
	{prefix: "/api/v1/dashboard", resource: "dashboard"},
	{prefix: "/api/v1/notifications", resource: "notifications"},
	{prefix: "/api/v1/alert-rules", resource: "alert_rules"},
	{prefix: "/api/v1/work-orders", resource: "work_orders"},
}

func resourceForPath(path string) string {
	for _, rule := range resourceRules {
		if path == rule.prefix || strings.HasPrefix(path, rule.prefix+"/") {
			return rule.resource
		}
	}
	return ""
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

func actionForRequest(method, path string) string {
	if method != "POST" {
		return getActionFromMethod(method)
	}

	switch path {
	case "/api/v1/devices/batch/control",
		"/api/v1/devices/add-to-station",
		"/api/v1/devices/batch-assign-installer":
		return "edit"
	}
	if strings.HasPrefix(path, "/api/v1/devices/") &&
		(strings.HasSuffix(path, "/unbind") ||
			strings.HasSuffix(path, "/control") ||
			strings.HasSuffix(path, "/remove-from-station") ||
			strings.HasSuffix(path, "/assign-installer") ||
			strings.HasSuffix(path, "/approve") ||
			strings.HasSuffix(path, "/reject")) {
		return "edit"
	}
	if strings.HasPrefix(path, "/api/v1/alarms/") &&
		(strings.HasSuffix(path, "/acknowledge") || strings.HasSuffix(path, "/ignore")) {
		return "edit"
	}
	if strings.HasPrefix(path, "/api/v1/work-orders/") &&
		(strings.HasSuffix(path, "/attachments") || strings.HasSuffix(path, "/escalate")) {
		return "edit"
	}
	return "create"
}

func isAuthenticatedSelfService(method, path string) bool {
	switch path {
	case "/api/v1/auth/logout", "/api/v1/auth/change-password":
		return method == "POST"
	case "/api/v1/auth/profile":
		return method == "GET" || method == "PUT"
	default:
		return false
	}
}

type PermissionChecker interface {
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

		uid, ok := userID.(int64)
		if !ok || checker == nil || !checker.CheckPermission(uid, resource, action) {
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
			response.Unauthorized(c, "unauthorized")
			c.Abort()
			return
		}

		path := c.Request.URL.Path
		if resource := resourceForPath(path); resource != "" {
			action := actionForRequest(c.Request.Method, path)
			uid, ok := userID.(int64)
			if !ok || checker == nil {
				response.Forbidden(c, "invalid permission context")
				c.Abort()
				return
			}
			if !checker.CheckPermission(uid, resource, action) {
				response.Forbidden(c, fmt.Sprintf("权限不足: %s:%s", resource, action))
				c.Abort()
				return
			}
			c.Next()
			return
		}
		if isAuthenticatedSelfService(c.Request.Method, path) {
			c.Next()
			return
		}

		response.Forbidden(c, "unclassified protected route")
		c.Abort()
	}
}
