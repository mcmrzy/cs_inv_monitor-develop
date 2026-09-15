package handler

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// respondLegacyPackageRetired 升级包写路径统一退役响应
func respondLegacyPackageRetired(c *gin.Context) {
	c.AbortWithStatusJSON(http.StatusGone, gin.H{
		"code":    model.ErrCodeLegacyPackageRetired,
		"message": "升级包功能已退役，请使用独立模块固件升级",
	})
}

// LegacyPackageRetired 路由级 410 处理器
func (h *OTAHandler) LegacyPackageRetired(c *gin.Context) {
	respondLegacyPackageRetired(c)
}

// GetDeviceFirmwareOverview GET /ota/devices/:sn/firmware-overview
func (h *OTAHandler) GetDeviceFirmwareOverview(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "device_sn 不能为空")
		return
	}
	if !h.ensureDeviceViewScope(c, sn) {
		return
	}
	ov, err := h.otaService.GetDeviceFirmwareOverview(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 404, "设备不存在或查询失败: "+err.Error())
		return
	}
	response.Success(c, ov)
}

// GetPublishedFirmwareResources GET /ota/devices/:sn/firmware-resources?target_chip=
func (h *OTAHandler) GetPublishedFirmwareResources(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "device_sn 不能为空")
		return
	}
	if !h.ensureDeviceViewScope(c, sn) {
		return
	}
	target := c.Query("target_chip")
	if target != "" {
		if _, err := service.NormalizeFirmwareTarget(target); err != nil {
			response.Error(c, 400, "target_chip 无效")
			return
		}
	}
	list, err := h.otaService.GetPublishedFirmwareResources(c.Request.Context(), sn, target)
	if err != nil {
		response.Error(c, 500, "查询固件资源失败: "+err.Error())
		return
	}
	response.Success(c, list)
}

// GetDeviceFirmwareHistory GET /ota/devices/:sn/history
func (h *OTAHandler) GetDeviceFirmwareHistory(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "device_sn 不能为空")
		return
	}
	if !h.ensureDeviceViewScope(c, sn) {
		return
	}
	filter, ok := parseHistoryFilter(c, sn)
	if !ok {
		return
	}
	items, total, err := h.otaService.GetFilteredUpgradeHistory(c.Request.Context(), filter)
	if err != nil {
		response.Error(c, 500, "查询升级历史失败: "+err.Error())
		return
	}
	response.Page(c, items, int64(total), filter.Page, filter.PageSize)
}

// GetAuthorizedUpgradeHistory GET /ota/history
func (h *OTAHandler) GetAuthorizedUpgradeHistory(c *gin.Context) {
	filter, ok := parseHistoryFilter(c, c.Query("device_sn"))
	if !ok {
		return
	}
	userID := middleware.GetUserID(c)
	if !middleware.GetIsSystemAdmin(c) && filter.DeviceSN != "" {
		if !h.ensureDeviceViewScope(c, filter.DeviceSN) {
			return
		}
	}
	if !middleware.GetIsSystemAdmin(c) && filter.DeviceSN == "" {
		deviceSNs, err := h.otaService.ListAuthorizedDeviceSNs(c.Request.Context(), middleware.GetActorContext(c), "devices:view")
		if err != nil {
			response.Error(c, 500, "查询设备范围失败")
			return
		}
		if len(deviceSNs) == 0 {
			response.Page(c, []model.DeviceUpgrade{}, 0, filter.Page, filter.PageSize)
			return
		}
		filter.DeviceSNs = deviceSNs
		_ = userID
	}
	items, total, err := h.otaService.GetFilteredUpgradeHistory(c.Request.Context(), filter)
	if err != nil {
		response.Error(c, 500, "查询升级历史失败: "+err.Error())
		return
	}
	response.Page(c, items, int64(total), filter.Page, filter.PageSize)
}

func parseHistoryFilter(c *gin.Context, defaultSN string) (model.UpgradeHistoryFilter, bool) {
	f := model.UpgradeHistoryFilter{
		DeviceSN:   strings.TrimSpace(defaultSN),
		TargetChip: strings.TrimSpace(c.Query("target_chip")),
		Status:     strings.TrimSpace(c.Query("status")),
	}
	if f.TargetChip != "" {
		if _, err := service.NormalizeFirmwareTarget(f.TargetChip); err != nil {
			response.Error(c, 400, "target_chip 无效")
			return f, false
		}
	}
	if raw := c.Query("page"); raw != "" {
		p, err := strconv.Atoi(raw)
		if err != nil || p < 1 {
			response.Error(c, 400, "page 无效")
			return f, false
		}
		f.Page = p
	} else {
		f.Page = 1
	}
	if raw := c.Query("page_size"); raw != "" {
		ps, err := strconv.Atoi(raw)
		if err != nil || ps < 1 || ps > 100 {
			response.Error(c, 400, "page_size 无效")
			return f, false
		}
		f.PageSize = ps
	} else {
		f.PageSize = 20
	}
	if raw := c.Query("start_time"); raw != "" {
		t, err := repository.ParseHistoryTime(raw)
		if err != nil {
			response.Error(c, 400, "start_time 无效")
			return f, false
		}
		f.StartTime = t
	}
	if raw := c.Query("end_time"); raw != "" {
		t, err := repository.ParseHistoryTime(raw)
		if err != nil {
			response.Error(c, 400, "end_time 无效")
			return f, false
		}
		f.EndTime = t
	}
	return f, true
}

// PublishFirmware POST /ota/firmware/:id/publish
// Body 可选：rollout_percent / rollout_type / rollout_targets / rollback_to_firmware_id
func (h *OTAHandler) PublishFirmware(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "固件 ID 无效")
		return
	}
	var req model.FirmwarePublishOptions
	// body 可为空
	_ = c.ShouldBindJSON(&req)
	if req.RolloutPercent < 0 || req.RolloutPercent > 100 {
		req.RolloutPercent = 100
	}
	if req.RolloutType != "device" {
		req.RolloutType = "all"
		req.RolloutTargets = strings.TrimSpace(req.RolloutTargets)
	} else {
		req.RolloutTargets = strings.TrimSpace(req.RolloutTargets)
		if req.RolloutTargets == "" {
			response.Error(c, 400, "按设备发布时必须提供 rollout_targets")
			return
		}
	}
	if req.RollbackToFirmwareID != nil && *req.RollbackToFirmwareID <= 0 {
		req.RollbackToFirmwareID = nil
	}
	actorID := middleware.GetUserID(c)
	if err := h.otaService.PublishFirmware(c.Request.Context(), id, actorID, req); err != nil {
		response.Error(c, 500, "发布失败: "+err.Error())
		return
	}
	detail := fmt.Sprintf(`{"rollout_percent":%d,"rollout_type":%q,"rollout_targets":%q}`,
		req.RolloutPercent, req.RolloutType, req.RolloutTargets)
	if req.RollbackToFirmwareID != nil {
		detail = detail[:len(detail)-1] + fmt.Sprintf(`,"rollback_to_firmware_id":%d}`, *req.RollbackToFirmwareID)
	}
	h.logOTAAudit(c, "firmware_publish", strconv.FormatInt(id, 10), detail)
	response.Success(c, gin.H{
		"id":                 id,
		"release_status":     "published",
		"rollout_percent":    req.RolloutPercent,
		"rollout_type":       req.RolloutType,
		"rollout_targets":    req.RolloutTargets,
		"rollback_to_firmware_id": req.RollbackToFirmwareID,
	})
}

// UpdateFirmwareRollout PUT /ota/firmware/:id/rollout 发布后调整灰度
func (h *OTAHandler) UpdateFirmwareRollout(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "固件 ID 无效")
		return
	}
	var req model.FirmwarePublishOptions
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}
	if req.RolloutPercent < 0 || req.RolloutPercent > 100 {
		response.Error(c, 400, "灰度比例需在 0-100 之间")
		return
	}
	if req.RolloutType != "device" {
		req.RolloutType = "all"
		req.RolloutTargets = ""
	}
	if req.RollbackToFirmwareID != nil && *req.RollbackToFirmwareID <= 0 {
		req.RollbackToFirmwareID = nil
	}
	if err := h.otaService.UpdateFirmwareRollout(c.Request.Context(), id, req); err != nil {
		response.Error(c, 500, "更新灰度失败: "+err.Error())
		return
	}
	h.logOTAAudit(c, "firmware_rollout_update", strconv.FormatInt(id, 10),
		fmt.Sprintf(`{"rollout_percent":%d,"rollout_type":%q}`, req.RolloutPercent, req.RolloutType))
	response.Success(c, gin.H{"id": id, "rollout_percent": req.RolloutPercent, "rollout_type": req.RolloutType})
}

// DisableFirmware POST /ota/firmware/:id/disable
func (h *OTAHandler) DisableFirmware(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "固件 ID 无效")
		return
	}
	actorID := middleware.GetUserID(c)
	if err := h.otaService.DisableFirmware(c.Request.Context(), id, actorID); err != nil {
		response.Error(c, 500, "停用失败: "+err.Error())
		return
	}
	h.logOTAAudit(c, "firmware_disable", strconv.FormatInt(id, 10), "disable/stop distributing firmware")
	response.Success(c, gin.H{"id": id, "release_status": "disabled"})
}

// DeleteFirmwareDraft DELETE /ota/firmware/:id 仅 draft
func (h *OTAHandler) DeleteFirmwareDraft(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "固件 ID 无效")
		return
	}
	if err := h.otaService.DeleteDraftFirmware(c.Request.Context(), id); err != nil {
		if errors.Is(err, service.ErrFirmwareNotDraft) {
			response.Error(c, 409, "仅允许删除 draft 状态固件")
			return
		}
		response.Error(c, 500, "删除失败: "+err.Error())
		return
	}
	h.logOTAAudit(c, "firmware_delete", strconv.FormatInt(id, 10), "delete draft firmware")
	response.Success(c, gin.H{"id": id})
}

// TriggerIndependentOTA POST /ota/trigger
func (h *OTAHandler) TriggerIndependentOTA(c *gin.Context) {
	var req model.TriggerFirmwareRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}
	if !h.ensureDeviceControlScope(c, req.DeviceSN) {
		return
	}
	if strings.TrimSpace(req.ForceReason) != "" && !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "只有系统管理员可以强制升级")
		return
	}
	userID := middleware.GetUserID(c)
	refs, err := h.otaService.TriggerIndependentFirmware(c.Request.Context(), userID, req)
	if err != nil {
		if errors.Is(err, service.ErrIdempotencyConflict) {
			response.Error(c, 409, "idempotency_key 与已有请求不一致")
			return
		}
		if errors.Is(err, service.ErrFirmwareNotPublished) || errors.Is(err, service.ErrDuplicateTarget) || errors.Is(err, service.ErrDeviceNotFound) || errors.Is(err, repository.ErrDeviceOffline) || errors.Is(err, service.ErrCurrentVersionUnknown) {
			response.Error(c, 409, err.Error())
			return
		}
		response.Error(c, 500, "触发升级失败: "+err.Error())
		return
	}
	h.logOTAAuditTyped(c, "firmware_trigger", "device_upgrade", req.DeviceSN,
		fmt.Sprintf(`{"firmware_ids":%v,"force":%t}`, req.FirmwareIDs, req.ForceReason != ""))
	response.Success(c, gin.H{"tasks": refs})
}

// RollbackIndependentFirmware POST /ota/firmware/rollback
func (h *OTAHandler) RollbackIndependentFirmware(c *gin.Context) {
	var req struct {
		DeviceSN       string `json:"device_sn" binding:"required"`
		FirmwareID     int64  `json:"firmware_id" binding:"required"`
		IdempotencyKey string `json:"idempotency_key" binding:"required"`
		ForceReason    string `json:"force_reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}
	if !h.ensureDeviceControlScope(c, req.DeviceSN) {
		return
	}
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)
	ref, err := h.otaService.RollbackIndependentFirmware(c.Request.Context(), userID, req.DeviceSN, req.FirmwareID, req.IdempotencyKey, req.ForceReason, isAdmin)
	if err != nil {
		if errors.Is(err, service.ErrCurrentVersionUnknown) || errors.Is(err, repository.ErrDeviceOffline) {
			response.Error(c, 409, "当前模块版本未上报，无法回滚")
			return
		}
		if errors.Is(err, service.ErrIdempotencyConflict) {
			response.Error(c, 409, "idempotency_key 与已有请求不一致")
			return
		}
		response.Error(c, 500, "回滚失败: "+err.Error())
		return
	}
	detail := fmt.Sprintf(`{"firmware_id":%d}`, req.FirmwareID)
	if req.ForceReason != "" {
		detail = fmt.Sprintf(`{"firmware_id":%d,"force_reason":%q}`, req.FirmwareID, req.ForceReason)
	}
	h.logOTAAuditTyped(c, "firmware_rollback", "device_upgrade", req.DeviceSN, detail)
	response.Success(c, ref)
}
