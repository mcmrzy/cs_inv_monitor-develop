package handler

import (
	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
)

// GetStatistics returns aggregated statistics for a device.
func (h *DeviceHandler) GetStatistics(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "day")

	tz := getUserTimezone(c.Request.Context(), h.db, userID)

	// 当日期参数为空时，提供合理默认值
	if startDate == "" {
		now := timezone.NowInTimezone(tz)
		switch period {
		case "hour":
			startDate = now.AddDate(0, 0, -1).Format("2006-01-02")
		case "month":
			startDate = now.AddDate(0, -12, 0).Format("2006-01-02")
		default: // "day"
			startDate = now.AddDate(0, 0, -30).Format("2006-01-02")
		}
	}
	if endDate == "" {
		endDate = timezone.TodayInTimezone(tz)
	}

	data, err := h.deviceService.GetStatistics(c.Request.Context(), sn, startDate, endDate, period, tz)
	if err != nil {
		response.Error(c, 500, "get statistics failed")
		return
	}

	response.Success(c, data)
}

// AssignInstallerRequest represents the JSON body for assigning an installer to a device.
type AssignInstallerRequest struct {
	InstallerID int64 `json:"installerId" binding:"required"`
}

// AssignInstaller assigns a device to an installer (admin only).
func (h *DeviceHandler) AssignInstaller(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "admin only")
		return
	}

	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "device sn is required")
		return
	}

	var req AssignInstallerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// 验证设备存在
	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil || device == nil {
		response.Error(c, 404, "device not found")
		return
	}

	// 更新设备的installer_id
	err = h.deviceService.UpdateInstallerID(c.Request.Context(), sn, req.InstallerID)
	if err != nil {
		response.Error(c, 500, "failed to assign installer")
		return
	}

	response.SuccessWithMessage(c, "installer assigned successfully", gin.H{"sn": sn, "installerId": req.InstallerID})
}

// BatchAssignInstallerRequest represents the JSON body for batch assigning installers.
type BatchAssignInstallerRequest struct {
	DeviceSNs   []string `json:"deviceSns" binding:"required"`
	InstallerID int64    `json:"installerId" binding:"required"`
}

// BatchAssignInstaller assigns multiple devices to an installer (admin only).
func (h *DeviceHandler) BatchAssignInstaller(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "admin only")
		return
	}

	var req BatchAssignInstallerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if len(req.DeviceSNs) == 0 {
		response.Error(c, 400, "deviceSns is required")
		return
	}

	// 批量更新设备的installer_id
	err := h.deviceService.BatchUpdateInstallerID(c.Request.Context(), req.DeviceSNs, req.InstallerID)
	if err != nil {
		response.Error(c, 500, "failed to batch assign installer")
		return
	}

	response.SuccessWithMessage(c, "installer assigned successfully", gin.H{"count": len(req.DeviceSNs), "installerId": req.InstallerID})
}

// RemoveInstaller removes the installer assignment from a device (admin only).
func (h *DeviceHandler) RemoveInstaller(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "admin only")
		return
	}

	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "device sn is required")
		return
	}

	// 更新设备的installer_id为null
	err := h.deviceService.UpdateInstallerID(c.Request.Context(), sn, 0)
	if err != nil {
		response.Error(c, 500, "failed to remove installer")
		return
	}

	response.SuccessWithMessage(c, "installer removed successfully", nil)
}
