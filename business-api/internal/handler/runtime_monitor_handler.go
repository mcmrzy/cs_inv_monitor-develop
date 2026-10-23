package handler

import (
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// Global runtime diagnostics span organizations and require a system admin even
// when the caller has the more general admin:manage permission.
func RuntimeMonitorHandler(svc *service.RuntimeMonitorService) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !middleware.GetIsSystemAdmin(c) {
			response.Forbidden(c, "permission denied")
			return
		}
		response.Success(c, svc.Snapshot(c.Request.Context()))
	}
}
