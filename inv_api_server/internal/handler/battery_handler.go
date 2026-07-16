package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type BatteryHandler struct {
	batteryService *service.BatteryService
}

func NewBatteryHandler(batteryService *service.BatteryService) *BatteryHandler {
	return &BatteryHandler{batteryService: batteryService}
}

// ListProfiles GET /battery-profiles
func (h *BatteryHandler) ListProfiles(c *gin.Context) {
	profiles, err := h.batteryService.ListProfiles(c.Request.Context())
	if err != nil {
		response.HandleError(c, apperr.Internal("查询电池模板列表失败", err))
		return
	}
	response.Success(c, profiles)
}

// GetProfile GET /battery-profiles/:id
func (h *BatteryHandler) GetProfile(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的模板ID"))
		return
	}

	profile, err := h.batteryService.GetProfile(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询电池模板失败", err))
		return
	}
	if profile == nil {
		response.HandleError(c, apperr.NotFound("电池模板不存在"))
		return
	}

	response.Success(c, profile)
}

// CreateProfile POST /battery-profiles
func (h *BatteryHandler) CreateProfile(c *gin.Context) {
	var req repository.CreateBatteryProfileReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("请求参数无效: "+err.Error()))
		return
	}

	if req.ProfileCode == "" {
		response.HandleError(c, apperr.BadRequest("profile_code 不能为空"))
		return
	}
	if req.Chemistry == "" {
		response.HandleError(c, apperr.BadRequest("chemistry 不能为空"))
		return
	}
	if req.SeriesCells <= 0 {
		response.HandleError(c, apperr.BadRequest("series_cells 必须大于 0"))
		return
	}
	if req.ChargeEnvelope == nil {
		req.ChargeEnvelope = make(map[string]interface{})
	}
	if req.DischargeEnvelope == nil {
		req.DischargeEnvelope = make(map[string]interface{})
	}

	profile, err := h.batteryService.CreateProfile(c.Request.Context(), req)
	if err != nil {
		response.HandleError(c, apperr.Internal("创建电池模板失败", err))
		return
	}

	response.Success(c, profile)
}

// BindDeviceConfig PUT /devices/:sn/battery-config
func (h *BatteryHandler) BindDeviceConfig(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备 SN 不能为空"))
		return
	}

	var req repository.UpsertBatteryConfigReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("请求参数无效: "+err.Error()))
		return
	}

	if req.ProfileID <= 0 {
		response.HandleError(c, apperr.BadRequest("profile_id 必须大于 0"))
		return
	}
	if req.CapacityAh <= 0 {
		response.HandleError(c, apperr.BadRequest("capacity_ah 必须大于 0"))
		return
	}
	if req.ParallelStrings <= 0 {
		req.ParallelStrings = 1
	}

	req.ConfiguredBy = middleware.GetUserID(c)

	if err := h.batteryService.BindDeviceConfig(c.Request.Context(), sn, req); err != nil {
		response.HandleError(c, apperr.Internal("绑定设备电池配置失败", err))
		return
	}

	response.SuccessWithMessage(c, "设备电池配置已更新", nil)
}

// GetDeviceConfig GET /devices/:sn/battery-config
func (h *BatteryHandler) GetDeviceConfig(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备 SN 不能为空"))
		return
	}

	cfg, err := h.batteryService.GetDeviceConfig(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备电池配置失败", err))
		return
	}
	if cfg == nil {
		response.HandleError(c, apperr.NotFound("设备未配置电池模板"))
		return
	}

	response.Success(c, cfg)
}
