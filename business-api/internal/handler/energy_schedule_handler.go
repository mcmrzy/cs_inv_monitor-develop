package handler

import (
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type EnergyScheduleHandler struct {
	scheduleService *service.EnergyScheduleService
}

func NewEnergyScheduleHandler(scheduleService *service.EnergyScheduleService) *EnergyScheduleHandler {
	return &EnergyScheduleHandler{scheduleService: scheduleService}
}

// GetSchedule GET /devices/:sn/energy-schedule
func (h *EnergyScheduleHandler) GetSchedule(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "设备 SN 不能为空")
		return
	}

	schedule, err := h.scheduleService.GetSchedule(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "查询能源计划失败")
		return
	}
	if schedule == nil {
		// 返回默认空计划
		schedule = &repository.EnergySchedule{
			DeviceSN: sn,
			Timezone: "Asia/Shanghai",
			Revision: 0,
			Enabled:  true,
			Periods:  []map[string]interface{}{},
		}
	}

	response.Success(c, schedule)
}

// UpdateSchedule PUT /devices/:sn/energy-schedule（读 If-Match header 实现乐观锁）
func (h *EnergyScheduleHandler) UpdateSchedule(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "设备 SN 不能为空")
		return
	}

	var req repository.UpsertScheduleReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "请求参数无效: "+err.Error())
		return
	}

	if req.Timezone == "" {
		req.Timezone = "Asia/Shanghai"
	}
	if req.Periods == nil {
		req.Periods = []map[string]interface{}{}
	}

	// 从 If-Match header 读取客户端持有的 revision
	ifMatch := c.GetHeader("If-Match")
	expectedRevision, err := strconv.ParseInt(ifMatch, 10, 64)
	if err != nil {
		response.Error(c, 400, "If-Match header 缺失或无效，需提供当前 revision")
		return
	}

	req.UpdatedBy = middleware.GetUserID(c)

	result, err := h.scheduleService.UpdateSchedule(c.Request.Context(), sn, req, expectedRevision)
	if err != nil {
		response.Error(c, 500, err.Error())
		return
	}

	// 在响应 header 中返回新的 revision
	c.Header("ETag", strconv.FormatInt(result.Revision, 10))
	response.Success(c, result)
}

// CreateOverride POST /devices/:sn/control-overrides
func (h *EnergyScheduleHandler) CreateOverride(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "设备 SN 不能为空")
		return
	}

	var req repository.CreateOverrideReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "请求参数无效: "+err.Error())
		return
	}

	if req.Domain == "" {
		response.Error(c, 400, "domain 不能为空")
		return
	}
	if req.Value == nil {
		response.Error(c, 400, "value 不能为空")
		return
	}
	if req.ExpiresAt.IsZero() {
		response.Error(c, 400, "expires_at 不能为空")
		return
	}
	if req.ExpiresAt.Before(time.Now()) {
		response.Error(c, 400, "expires_at 不能是过去时间")
		return
	}

	req.CreatedBy = middleware.GetUserID(c)

	override, err := h.scheduleService.CreateOverride(c.Request.Context(), sn, req)
	if err != nil {
		response.Error(c, 500, "创建临时覆盖失败")
		return
	}

	response.Success(c, override)
}

// ListOverrides GET /devices/:sn/control-overrides
func (h *EnergyScheduleHandler) ListOverrides(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "设备 SN 不能为空")
		return
	}

	overrides, err := h.scheduleService.ListActiveOverrides(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "查询临时覆盖列表失败")
		return
	}

	response.Success(c, overrides)
}

// CancelOverride DELETE /devices/:sn/control-overrides/:id
func (h *EnergyScheduleHandler) CancelOverride(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "设备 SN 不能为空")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "无效的覆盖 ID")
		return
	}

	if err := h.scheduleService.CancelOverride(c.Request.Context(), sn, id); err != nil {
		response.Error(c, 500, "取消临时覆盖失败")
		return
	}

	response.SuccessWithMessage(c, "临时覆盖已取消", nil)
}
