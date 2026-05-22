package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type DeviceHandler struct {
	deviceService *service.DeviceService
	alarmService  *service.AlarmService
}

func NewDeviceHandler(deviceService *service.DeviceService, alarmService *service.AlarmService) *DeviceHandler {
	return &DeviceHandler{
		deviceService: deviceService,
		alarmService:  alarmService,
	}
}

func (h *DeviceHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	stationIDStr := c.Query("station_id")
	statusStr := c.Query("status")

	var stationID int64
	if stationIDStr != "" {
		stationID, _ = strconv.ParseInt(stationIDStr, 10, 64)
	}

	var status int = -1
	if statusStr != "" {
		status, _ = strconv.Atoi(statusStr)
	}

	devices, total, err := h.deviceService.GetByUserID(c.Request.Context(), userID, stationID, status, page, pageSize)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Page(c, devices, total, page, pageSize)
}

func (h *DeviceHandler) GetDetail(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		response.NotFound(c, "device not found")
		return
	}

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	realtimeData, _ := h.deviceService.GetRealtimeData(c.Request.Context(), sn)

	result := map[string]interface{}{
		"device":        device,
		"realtime_data": realtimeData,
	}

	response.Success(c, result)
}

func (h *DeviceHandler) GetRealtimeData(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	data, err := h.deviceService.GetRealtimeData(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if data == nil {
		response.NotFound(c, "no data")
		return
	}

	response.Success(c, data)
}

type BindDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	StationID int64  `json:"station_id"`
}

func (h *DeviceHandler) Bind(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BindDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		if err := h.deviceService.EnsureDevice(c.Request.Context(), req.SN); err != nil {
			response.InternalError(c, "create device failed")
			return
		}
		device, err = h.deviceService.GetBySN(c.Request.Context(), req.SN)
		if err != nil || device == nil {
			response.InternalError(c, "system error")
			return
		}
	}

	if device.UserID != 0 {
		response.Error(c, 5002, "device already bound")
		return
	}

	if err := h.deviceService.Bind(c.Request.Context(), req.SN, userID, req.StationID); err != nil {
		response.InternalError(c, "bind device failed")
		return
	}

	response.SuccessWithMessage(c, "device bound success", nil)
}

func (h *DeviceHandler) Unbind(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		response.NotFound(c, "device not found")
		return
	}

	if device.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	if err := h.deviceService.Unbind(c.Request.Context(), sn); err != nil {
		response.InternalError(c, "unbind device failed")
		return
	}

	response.SuccessWithMessage(c, "device unbound success", nil)
}

type ControlRequest struct {
	Command string                 `json:"command" binding:"required"`
	Params  map[string]interface{} `json:"params"`
}

func (h *DeviceHandler) Control(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasControlPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	var req ControlRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.deviceService.SendCommand(c.Request.Context(), sn, req.Command, req.Params); err != nil {
		response.Error(c, 5003, "send command failed: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "command sent", nil)
}

func (h *DeviceHandler) GetParams(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	params, err := h.deviceService.GetParams(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Success(c, params)
}

type UpdateParamsRequest struct {
	Params map[string]interface{} `json:"params" binding:"required"`
}

func (h *DeviceHandler) UpdateParams(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasControlPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	var req UpdateParamsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.deviceService.UpdateParams(c.Request.Context(), sn, req.Params); err != nil {
		response.InternalError(c, "update params failed")
		return
	}

	response.SuccessWithMessage(c, "params updated", nil)
}

func (h *DeviceHandler) GetHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "hour")

	data, err := h.deviceService.GetHistoryData(c.Request.Context(), sn, startDate, endDate, period)
	if err != nil {
		response.InternalError(c, "get history failed")
		return
	}

	response.Success(c, data)
}

func (h *DeviceHandler) GetAlarms(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	alarms, total, err := h.alarmService.GetByDeviceSN(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Page(c, alarms, total, page, pageSize)
}

type ShareDeviceRequest struct {
	Phone      string `json:"phone" binding:"required"`
	Permission string `json:"permission" binding:"required"`
}

func (h *DeviceHandler) Share(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil || device.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	var req ShareDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.deviceService.Share(c.Request.Context(), sn, userID, req.Phone, req.Permission); err != nil {
		response.InternalError(c, "share device failed: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "device shared", nil)
}

func (h *DeviceHandler) CancelShare(c *gin.Context) {
	_ = c.Param("sn")
	shareID, err := strconv.ParseInt(c.Param("share_id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid share id")
		return
	}

	userID := middleware.GetUserID(c)

	if err := h.deviceService.CancelShare(c.Request.Context(), shareID, userID); err != nil {
		response.InternalError(c, "cancel share failed: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "share canceled", nil)
}

func (h *DeviceHandler) GetShares(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil || device.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	shares, err := h.deviceService.GetShares(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Success(c, shares)
}

type AddDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	StationID int64  `json:"station_id"`
}

func (h *DeviceHandler) AddToStation(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req AddDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		response.Error(c, 5001, "device not found")
		return
	}

	if device.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	if err := h.deviceService.AddToStation(c.Request.Context(), req.SN, req.StationID); err != nil {
		response.InternalError(c, "add to station failed")
		return
	}

	response.SuccessWithMessage(c, "device added to station", nil)
}

func (h *DeviceHandler) ScanLocal(c *gin.Context) {
	userID := middleware.GetUserID(c)

	devices, err := h.deviceService.ScanLocalNetwork(c.Request.Context(), userID)
	if err != nil {
		response.InternalError(c, "scan failed")
		return
	}

	response.Success(c, devices)
}

func (h *DeviceHandler) GetStatistics(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "day")

	data, err := h.deviceService.GetStatistics(c.Request.Context(), sn, startDate, endDate, period)
	if err != nil {
		response.InternalError(c, "get statistics failed")
		return
	}

	response.Success(c, data)
}

type OTAUpgradeRequest struct {
	FirmwareID int64 `json:"firmware_id" binding:"required"`
}

func (h *DeviceHandler) OTAUpgrade(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil || device.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	var req OTAUpgradeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.deviceService.StartOTA(c.Request.Context(), sn, req.FirmwareID); err != nil {
		response.InternalError(c, "start OTA failed: "+err.Error())
		return
	}

	response.SuccessWithMessage(c, "OTA upgrade started", nil)
}

func (h *DeviceHandler) GetOTAStatus(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)

	if !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	status, err := h.deviceService.GetOTAStatus(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Success(c, status)
}
