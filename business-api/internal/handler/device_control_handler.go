package handler

import (
	"errors"
	"fmt"
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// ControlRequest represents the JSON body for sending a device control command.
type ControlRequest struct {
	Command string                 `json:"command" binding:"required"`
	Params  map[string]interface{} `json:"params"`
}

// Control sends a validated command to a device.
func (h *DeviceHandler) Control(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	// 步骤1前置：RBAC devices:control + 数据归属检查（兼容现有中间件层）
	if !isAdmin && !h.deviceService.HasControlPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	var req ControlRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// 9步校验链：ValidateAndPrepareCommand 集成步骤1-8（身份/型号/参数/关系/状态/BMS限制/拓扑/风险确认）
	prepared, err := h.deviceService.ValidateAndPrepareCommand(c.Request.Context(), userID, sn, req.Command, req.Params)
	if err != nil {
		logger.Error("Control validate and prepare failed", zap.String("sn", sn), zap.String("cmd", req.Command), zap.Error(err))
		// 处理 CommandError 类型，返回拒绝码
		var cmdErr *service.CommandError
		if errors.As(err, &cmdErr) {
			c.JSON(cmdErr.StatusCode, gin.H{
				"code":           cmdErr.StatusCode,
				"message":        cmdErr.Error(),
				"reject_code":    cmdErr.Code,
				"reject_detail":  cmdErr.Message,
			})
			return
		}
		response.Error(c, 500, err.Error())
		return
	}

	// 步骤9：发送已校验的命令
	taskID, err := h.deviceService.SendPreparedCommand(c.Request.Context(), sn, prepared)
	if err != nil {
		logger.Error("Control send prepared command failed", zap.String("sn", sn), zap.String("cmd", req.Command), zap.Error(err))
		var cmdErr *service.CommandError
		if errors.As(err, &cmdErr) {
			c.JSON(cmdErr.StatusCode, gin.H{
				"code":           cmdErr.StatusCode,
				"message":        cmdErr.Error(),
				"reject_code":    cmdErr.Code,
				"reject_detail":  cmdErr.Message,
			})
			return
		}
		response.Error(c, 5003, "发送命令失败，请稍后重试")
		return
	}

	// 记录审计日志
	h.logDeviceAudit(c, "command", sn, fmt.Sprintf(`{"sn":"%s","command":"%s"}`, sn, req.Command))

	response.SuccessWithMessage(c, "command sent", gin.H{"task_id": taskID})
}

// GetControlFields returns the control field definitions for a device's model.
func (h *DeviceHandler) GetControlFields(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	fields, err := h.deviceService.GetControlFieldsBySN(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "查询控制字段失败")
		return
	}

	response.Success(c, fields)
}

// GetControlCapabilities returns the full command capability metadata for a device's model.
func (h *DeviceHandler) GetControlCapabilities(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	caps, err := h.deviceService.GetControlCapabilitiesBySN(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "查询控制能力失败")
		return
	}

	response.Success(c, caps)
}

// GetControlState returns the current control state for a device.
func (h *DeviceHandler) GetControlState(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	if !middleware.GetIsSystemAdmin(c) && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}
	state, err := h.deviceService.GetControlState(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "get control state failed")
		return
	}
	response.Success(c, state)
}

// GetCommands returns paginated command history for a device.
func (h *DeviceHandler) GetCommands(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, 20)
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}

	commands, total, err := h.deviceService.GetCommandHistory(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.Error(c, 500, "get commands failed")
		return
	}

	response.Page(c, commands, total, page, pageSize)
}

// BatchControl sends a control command to multiple devices.
func (h *DeviceHandler) BatchControl(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	var req struct {
		SNs     []string               `json:"sns" binding:"required"`
		Command string                 `json:"command" binding:"required"`
		Params  map[string]interface{} `json:"params"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: sns and command are required")
		return
	}

	if len(req.SNs) == 0 {
		response.Error(c, 400, "sns cannot be empty")
		return
	}
	if len(req.SNs) > 50 {
		response.Error(c, 400, "batch size cannot exceed 50")
		return
	}

	results := make(map[string]string)
	taskIDs := make(map[string]string)
	for _, sn := range req.SNs {
		if !isAdmin && !h.deviceService.HasControlPermission(c.Request.Context(), userID, sn) {
			results[sn] = "permission denied"
			continue
		}

		if err := h.deviceService.ValidateControlCommand(c.Request.Context(), sn, req.Command); err != nil {
			results[sn] = "命令校验失败"
			continue
		}

		if !isAdmin {
			if err := h.deviceService.CheckCommandPermission(c.Request.Context(), userID, sn, req.Command); err != nil {
				results[sn] = err.Error()
				continue
			}
		}

		taskID, err := h.deviceService.SendCommand(c.Request.Context(), sn, req.Command, req.Params)
		if err != nil {
			results[sn] = err.Error()
			continue
		}

		results[sn] = "sent"
		taskIDs[sn] = taskID
	}

	response.Success(c, gin.H{"results": results, "task_ids": taskIDs})
}
