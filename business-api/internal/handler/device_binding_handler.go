package handler

import (
	"fmt"
	"strconv"
	"strings"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
	"go.uber.org/zap"
)

// BindDeviceRequest represents the JSON body for device binding.
type BindDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	StationID int64  `json:"station_id"`
}

// Bind binds a device to the current user.
func (h *DeviceHandler) Bind(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BindDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if !deviceSNRegex.MatchString(req.SN) {
		response.Error(c, 400, "invalid SN format")
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if device == nil {
		if err := h.deviceService.EnsureDevice(c.Request.Context(), req.SN); err != nil {
			response.Error(c, 500, "create device failed")
			return
		}
		device, err = h.deviceService.GetBySN(c.Request.Context(), req.SN)
		if err != nil || device == nil {
			response.Error(c, 500, "system error")
			return
		}
	}

	if device.UserID != 0 {
		response.Error(c, 5002, "device already bound")
		return
	}
	if err := ensureTenantDeviceCapacity(c.Request.Context(), h.db, userID); err != nil {
		response.Error(c, 400, err.Error())
		return
	}

	if err := h.deviceService.Bind(c.Request.Context(), req.SN, userID, req.StationID); err != nil {
		if err.Error() == "device already bound" {
			response.Error(c, 5002, "device already bound")
			return
		}
		response.Error(c, 500, "bind device failed")
		return
	}

	response.SuccessWithMessage(c, "device bound success", nil)
}

// Unbind unbinds a device from its owner.
func (h *DeviceHandler) Unbind(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if device == nil {
		response.Error(c, 404, "device not found")
		return
	}

	if !isAdmin && device.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	if err := h.deviceService.Unbind(c.Request.Context(), sn); err != nil {
		response.Error(c, 500, "unbind device failed")
		return
	}

	response.SuccessWithMessage(c, "device unbound success", nil)
}

// RequestUnbind creates an unbind approval request.
func (h *DeviceHandler) RequestUnbind(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if device == nil {
		response.Error(c, 404, "device not found")
		return
	}

	if !isAdmin && device.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	c.ShouldBindJSON(&req)

	id, err := h.deviceService.RequestUnbind(c.Request.Context(), sn, userID, req.Reason)
	if err != nil {
		response.Error(c, 500, "create unbind request failed")
		return
	}

	response.Success(c, map[string]interface{}{
		"id":        id,
		"device_sn": sn,
		"status":    "pending",
	})
}

// GetUnbindRequests lists pending unbind approval requests (admin only).
func (h *DeviceHandler) GetUnbindRequests(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "admin only")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, 10)
	if pageSize < 1 {
		pageSize = 10
	}
	if pageSize > 100 {
		pageSize = 100
	}

	items, total, err := h.deviceService.GetUnbindRequests(c.Request.Context(), page, pageSize)
	if err != nil {
		response.Error(c, 500, "get unbind requests failed")
		return
	}

	response.Page(c, items, total, page, pageSize)
}

// ApproveUnbind approves a pending unbind request (admin only).
func (h *DeviceHandler) ApproveUnbind(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "admin only")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid request id")
		return
	}

	userID := middleware.GetUserID(c)
	var req struct {
		Comment string `json:"comment"`
	}
	c.ShouldBindJSON(&req)

	if err := h.deviceService.ApproveUnbind(c.Request.Context(), id, userID, req.Comment); err != nil {
		logger.Error("ApproveUnbind failed", zap.Int64("id", id), zap.Error(err))
		response.Error(c, 500, "操作失败，请稍后重试")
		return
	}

	response.SuccessWithMessage(c, "unbind approved", nil)
}

// RejectUnbind rejects a pending unbind request (admin only).
func (h *DeviceHandler) RejectUnbind(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "admin only")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid request id")
		return
	}

	userID := middleware.GetUserID(c)
	var req struct {
		Comment string `json:"comment"`
	}
	c.ShouldBindJSON(&req)

	if err := h.deviceService.RejectUnbind(c.Request.Context(), id, userID, req.Comment); err != nil {
		logger.Error("RejectUnbind failed", zap.Int64("id", id), zap.Error(err))
		response.Error(c, 500, "操作失败，请稍后重试")
		return
	}

	response.SuccessWithMessage(c, "unbind rejected", nil)
}

// ImportExcel imports devices from an Excel file and binds them to the current user.
// Excel format: header row (skipped), then rows with:
//   - A: SN (required)
//   - B: Model (optional)
//   - C: Station ID (optional)
func (h *DeviceHandler) ImportExcel(c *gin.Context) {
	userID := middleware.GetUserID(c)

	file, err := c.FormFile("file")
	if err != nil {
		response.Error(c, 400, "请选择要上传的文件")
		return
	}

	src, err := file.Open()
	if err != nil {
		response.Error(c, 500, "打开文件失败")
		return
	}
	defer src.Close()

	f, err := excelize.OpenReader(src)
	if err != nil {
		response.Error(c, 400, "无法解析Excel文件，请确保为 .xlsx 格式")
		return
	}
	defer f.Close()

	sheetName := f.GetSheetName(0)
	rows, err := f.GetRows(sheetName)
	if err != nil {
		response.Error(c, 400, "读取Excel数据失败")
		return
	}

	successCount := 0
	failedCount := 0
	var importErrors []string

	for i, row := range rows {
		if i == 0 {
			continue
		}
		if len(row) == 0 {
			continue
		}

		sn := strings.TrimSpace(row[0])
		if sn == "" {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: SN为空", i+1))
			continue
		}

		if !deviceSNRegex.MatchString(sn) {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: SN格式无效: %s", i+1, sn))
			continue
		}

		var stationID int64
		if len(row) > 2 {
			sVal := strings.TrimSpace(row[2])
			if sVal != "" {
				stationID, _ = strconv.ParseInt(sVal, 10, 64)
			}
		}

		device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
		if err != nil {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: 查询设备失败: %s", i+1, sn))
			continue
		}

		if device == nil {
			if err := h.deviceService.EnsureDevice(c.Request.Context(), sn); err != nil {
				failedCount++
				importErrors = append(importErrors, fmt.Sprintf("第%d行: 创建设备失败: %s", i+1, sn))
				continue
			}
			device, err = h.deviceService.GetBySN(c.Request.Context(), sn)
			if err != nil || device == nil {
				failedCount++
				importErrors = append(importErrors, fmt.Sprintf("第%d行: 创建设备后查询失败: %s", i+1, sn))
				continue
			}
		}

		if device.UserID != 0 {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: 设备已被绑定: %s", i+1, sn))
			continue
		}

		if err := ensureTenantDeviceCapacity(c.Request.Context(), h.db, userID); err != nil {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: %s", i+1, err.Error()))
			continue
		}

		if err := h.deviceService.Bind(c.Request.Context(), sn, userID, stationID); err != nil {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: 绑定失败: %s - %s", i+1, sn, err.Error()))
			continue
		}

		if len(row) > 1 {
			modelVal := strings.TrimSpace(row[1])
			if modelVal != "" {
				h.deviceService.Update(c.Request.Context(), sn, modelVal, nil, "", "")
			}
		}

		successCount++
	}

	logger.Info("ImportExcel completed", zap.Int64("user_id", userID), zap.Int("success", successCount), zap.Int("failed", failedCount))

	response.Success(c, gin.H{
		"success": successCount,
		"failed":  failedCount,
		"errors":  importErrors,
	})
}
