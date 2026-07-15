package handler

import (
	"encoding/csv"
	"errors"
	"fmt"
	"log"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/xuri/excelize/v2"
)

var deviceSNRegex = regexp.MustCompile(`^[A-Z0-9-]{8,64}$`)

type DeviceHandler struct {
	deviceService  *service.DeviceService
	alarmService   *service.AlarmService
	stationService *service.StationService
	db             *pgxpool.Pool
}

func NewDeviceHandler(deviceService *service.DeviceService, alarmService *service.AlarmService, stationService *service.StationService, db *pgxpool.Pool) *DeviceHandler {
	return &DeviceHandler{
		deviceService:  deviceService,
		alarmService:   alarmService,
		stationService: stationService,
		db:             db,
	}
}

func (h *DeviceHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}

	pageSize := getPageSize(c, 20)
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 200 {
		pageSize = 200
	}

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

	var devices []*model.Device
	var total int64
	var err error

	if isAdmin {
		devices, total, err = h.deviceService.GetAll(c.Request.Context(), stationID, status, page, pageSize)
	} else {
		devices, total, err = h.deviceService.GetByUserID(c.Request.Context(), userID, stationID, status, page, pageSize)
	}

	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	// Batch-fetch realtime data for all devices (eliminates N+1 Redis calls)
	sns := make([]string, len(devices))
	for i, d := range devices {
		sns[i] = d.SN
	}
	rtDataMap, _ := h.deviceService.BatchGetRealtimeData(c.Request.Context(), sns)

	for _, device := range devices {
		rtData := rtDataMap[device.SN]
		if rtData != nil {
			enrichDeviceWithRealtime(device, rtData)
		}
	}

	response.Page(c, devices, total, page, pageSize)
}

func (h *DeviceHandler) GetDetail(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if device == nil {
		response.HandleError(c, apperr.NotFound("device not found"))
		return
	}

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	realtimeData, _ := h.deviceService.GetRealtimeData(c.Request.Context(), sn)

	// 判断在线状态：status=1(在线) 或 status=2(故障) 都表示设备在线
	// 优先使用 Redis 实时标记，仅在 Redis 明确说离线时才覆盖
	online := device.Status == 1 || device.Status == 2
	if realtimeData != nil {
		if rtOnline, ok := realtimeData["online"].(bool); ok {
			if !rtOnline {
				online = false
			}
		}

		// 从嵌套的 info 对象读取设备信息（支持 {"info": {...}} 和 {"info": {"data": {...}}} 两种格式）
		var info map[string]interface{}
		if v, ok := realtimeData["info"].(map[string]interface{}); ok {
			info = v
			if innerData, ok := v["data"].(map[string]interface{}); ok {
				info = innerData
			}
		}
		if info != nil {
			if v, ok := info["model"]; ok && v != nil {
				if s, ok := v.(string); ok && s != "" && device.Model == "" {
					device.Model = s
				}
			}
			if v, ok := info["manufacturer"]; ok && v != nil {
				if s, ok := v.(string); ok && s != "" && device.Manufacturer == "" {
					device.Manufacturer = s
				}
			}
			if v, ok := info["firmware_arm"]; ok && v != nil {
				if s, ok := v.(string); ok && s != "" && device.FirmwareArm == "" {
					device.FirmwareArm = s
				}
			}
			if v, ok := info["firmware_esp"]; ok && v != nil {
				if s, ok := v.(string); ok && s != "" && device.FirmwareEsp == "" {
					device.FirmwareEsp = s
				}
			}
			if v, ok := info["rated_power"]; ok && v != nil {
				if f, ok := toFloat64(v); ok && f > 0 && device.RatedPower == 0 {
					device.RatedPower = f
				}
			}
		}
	}

	result := map[string]interface{}{
		"device":        device,
		"realtime_data": realtimeData,
		"online_status": map[string]interface{}{
			"online": online,
		},
	}

	// 附加型号字段元数据
	modelFields, _ := h.deviceService.GetModelFieldsBySN(c.Request.Context(), sn)
	if len(modelFields) > 0 {
		result["model_fields"] = modelFields
	}

	response.Success(c, result)
}

func (h *DeviceHandler) GetRealtimeData(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	data, err := h.deviceService.GetRealtimeData(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if data == nil {
		response.HandleError(c, apperr.NotFound("no data"))
		return
	}

	deviceSN := data["device_sn"]
	if deviceSN == nil {
		deviceSN = data["_sn"]
	}
	if deviceSN == nil {
		deviceSN = sn
	}

	response.Success(c, map[string]interface{}{
		"device_sn": deviceSN,
		"data_time": data["updated_at"],
		"online":    data["online"],
		"realtime":  data,
	})
}

type BindDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	StationID int64  `json:"station_id"`
}

func (h *DeviceHandler) Bind(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BindDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if !deviceSNRegex.MatchString(req.SN) {
		response.HandleError(c, apperr.BadRequest("invalid SN format"))
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if device == nil {
		if err := h.deviceService.EnsureDevice(c.Request.Context(), req.SN); err != nil {
			response.HandleError(c, apperr.Internal("create device failed", err))
			return
		}
		device, err = h.deviceService.GetBySN(c.Request.Context(), req.SN)
		if err != nil || device == nil {
			response.HandleError(c, apperr.Internal("system error", err))
			return
		}
	}

	if device.UserID != 0 {
		response.Error(c, 5002, "device already bound")
		return
	}
	if err := ensureTenantDeviceCapacity(c.Request.Context(), h.db, userID); err != nil {
		response.HandleError(c, apperr.BadRequest(err.Error()))
		return
	}

	if err := h.deviceService.Bind(c.Request.Context(), req.SN, userID, req.StationID); err != nil {
		if err.Error() == "device already bound" {
			response.Error(c, 5002, "device already bound")
			return
		}
		response.HandleError(c, apperr.Internal("bind device failed", err))
		return
	}

	response.SuccessWithMessage(c, "device bound success", nil)
}

func (h *DeviceHandler) Unbind(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if device == nil {
		response.HandleError(c, apperr.NotFound("device not found"))
		return
	}

	if !isAdmin && device.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	if err := h.deviceService.Unbind(c.Request.Context(), sn); err != nil {
		response.HandleError(c, apperr.Internal("unbind device failed", err))
		return
	}

	response.SuccessWithMessage(c, "device unbound success", nil)
}

func (h *DeviceHandler) RequestUnbind(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if device == nil {
		response.HandleError(c, apperr.NotFound("device not found"))
		return
	}

	if !isAdmin && device.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	c.ShouldBindJSON(&req)

	id, err := h.deviceService.RequestUnbind(c.Request.Context(), sn, userID, req.Reason)
	if err != nil {
		response.HandleError(c, apperr.Internal("create unbind request failed", err))
		return
	}

	response.Success(c, map[string]interface{}{
		"id":        id,
		"device_sn": sn,
		"status":    "pending",
	})
}

type ControlRequest struct {
	Command string                 `json:"command" binding:"required"`
	Params  map[string]interface{} `json:"params"`
}

func (h *DeviceHandler) Control(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	// 步骤1前置：RBAC devices:control + 数据归属检查（兼容现有中间件层）
	if !isAdmin && !h.deviceService.HasControlPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	var req ControlRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 9步校验链：ValidateAndPrepareCommand 集成步骤1-8（身份/型号/参数/关系/状态/BMS限制/拓扑/风险确认）
	prepared, err := h.deviceService.ValidateAndPrepareCommand(c.Request.Context(), userID, sn, req.Command, req.Params)
	if err != nil {
		log.Printf("[Control] validate and prepare failed: sn=%s, cmd=%s, err=%v", sn, req.Command, err)
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
		response.HandleError(c, err)
		return
	}

	// 步骤9：发送已校验的命令
	taskID, err := h.deviceService.SendPreparedCommand(c.Request.Context(), sn, prepared)
	if err != nil {
		log.Printf("[Control] send prepared command failed: sn=%s, cmd=%s, err=%v", sn, req.Command, err)
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

	response.SuccessWithMessage(c, "command sent", gin.H{"task_id": taskID})
}

func (h *DeviceHandler) GetControlFields(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	fields, err := h.deviceService.GetControlFieldsBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询控制字段失败", err))
		return
	}

	response.Success(c, fields)
}

// GetControlCapabilities returns the full command capability metadata for a device's model.
func (h *DeviceHandler) GetControlCapabilities(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	caps, err := h.deviceService.GetControlCapabilitiesBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询控制能力失败", err))
		return
	}

	response.Success(c, caps)
}

// DEPRECATED: Device params removed. Use MQTT direct configuration.
// func (h *DeviceHandler) GetParams(c *gin.Context) {}

type CreateDeviceRequest struct {
	SN              string   `json:"sn" binding:"required"`
	Model           string   `json:"model"`
	RatedPower      *float64 `json:"ratedPower"`
	FirmwareVersion string   `json:"firmwareVersion"`
	HardwareVersion string   `json:"hardwareVersion"`
}

// Create creates a new device. Only admin and installer (role <= 4) can create devices.
func (h *DeviceHandler) Create(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 4 {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	var req CreateDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request body"))
		return
	}

	if !deviceSNRegex.MatchString(req.SN) {
		response.HandleError(c, apperr.BadRequest("invalid SN format"))
		return
	}

	// Check if device already exists
	existing, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}
	if existing != nil {
		response.HandleError(c, apperr.BadRequest("device already exists"))
		return
	}

	if err := h.deviceService.Create(c.Request.Context(), req.SN, req.Model, req.RatedPower, req.FirmwareVersion, req.HardwareVersion); err != nil {
		if strings.Contains(err.Error(), "already exists") {
			response.HandleError(c, apperr.BadRequest("device already exists"))
			return
		}
		response.HandleError(c, apperr.Internal("failed to create device", err))
		return
	}

	// Fetch the created device to return in response
	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil || device == nil {
		response.SuccessWithMessage(c, "device created", nil)
		return
	}

	response.SuccessWithMessage(c, "device created", device)
}

type UpdateDeviceRequest struct {
	Model           string   `json:"model"`
	RatedPower      *float64 `json:"ratedPower"`
	FirmwareVersion string   `json:"firmwareVersion"`
	HardwareVersion string   `json:"hardwareVersion"`
}

func (h *DeviceHandler) Update(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	// Ownership check: non-admin users can only update their own devices
	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}
	if device == nil {
		response.HandleError(c, apperr.NotFound("device not found"))
		return
	}
	if !isAdmin && device.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	var req UpdateDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request body"))
		return
	}
	if err := h.deviceService.Update(c.Request.Context(), sn, req.Model, req.RatedPower, req.FirmwareVersion, req.HardwareVersion); err != nil {
		response.HandleError(c, apperr.Internal("failed to update device", err))
		return
	}
	response.SuccessWithMessage(c, "device updated", nil)
}

func (h *DeviceHandler) GetHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "hour")

	data, err := h.deviceService.GetHistoryData(c.Request.Context(), sn, startDate, endDate, period)
	if err != nil {
		response.HandleError(c, apperr.Internal("get history failed", err))
		return
	}

	response.Success(c, data)
}

func (h *DeviceHandler) GetAlarms(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
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

	alarms, total, err := h.alarmService.GetByDeviceSN(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	response.Page(c, alarms, total, page, pageSize)
}

// DEPRECATED: Device sharing feature removed.
// func (h *DeviceHandler) Share(c *gin.Context) {}
// func (h *DeviceHandler) CancelShare(c *gin.Context) {}
// func (h *DeviceHandler) GetShares(c *gin.Context) {}

type AddDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	StationID int64  `json:"station_id"`
}

func (h *DeviceHandler) AddToStation(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	var req AddDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if device == nil {
		response.Error(c, 5001, "device not found")
		return
	}

	if !isAdmin {
		// Check device ownership
		if device.UserID != userID {
			response.HandleError(c, apperr.Forbidden("permission denied"))
			return
		}
		// Check station ownership
		station, err := h.stationService.GetByID(c.Request.Context(), req.StationID)
		if err != nil || station == nil {
			response.HandleError(c, apperr.BadRequest("station not found"))
			return
		}
		if station.UserID != userID {
			response.HandleError(c, apperr.Forbidden("station not owned by you"))
			return
		}
	}

	if err := h.deviceService.AddToStation(c.Request.Context(), req.SN, req.StationID); err != nil {
		response.HandleError(c, apperr.Internal("add to station failed", err))
		return
	}

	response.SuccessWithMessage(c, "device added to station", nil)
}

func (h *DeviceHandler) RemoveFromStation(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("invalid sn"))
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}
	if device == nil {
		response.Error(c, 5001, "device not found")
		return
	}

	if !isAdmin && device.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	if err := h.deviceService.RemoveFromStation(c.Request.Context(), sn); err != nil {
		response.HandleError(c, apperr.Internal("remove from station failed", err))
		return
	}

	response.SuccessWithMessage(c, "device removed from station", nil)
}

func (h *DeviceHandler) ScanLocal(c *gin.Context) {
	userID := middleware.GetUserID(c)

	devices, err := h.deviceService.ScanLocalNetwork(c.Request.Context(), userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("scan failed", err))
		return
	}

	response.Success(c, devices)
}

func (h *DeviceHandler) GetStatistics(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
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
		response.HandleError(c, apperr.Internal("get statistics failed", err))
		return
	}

	response.Success(c, data)
}

func (h *DeviceHandler) GetControlState(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	if middleware.GetRole(c) != 0 && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}
	state, err := h.deviceService.GetControlState(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("get control state failed", err))
		return
	}
	response.Success(c, state)
}

// DEPRECATED: OTA management migrated to NestJS backend (inv-admin-backend).
// func (h *DeviceHandler) OTAUpgrade(c *gin.Context) {}
// func (h *DeviceHandler) GetOTAStatus(c *gin.Context) {}

func (h *DeviceHandler) GetCommands(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
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
		response.HandleError(c, apperr.Internal("get commands failed", err))
		return
	}

	response.Page(c, commands, total, page, pageSize)
}

// BatchControl 批量发送控制命令
func (h *DeviceHandler) BatchControl(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	var req struct {
		SNs     []string               `json:"sns" binding:"required"`
		Command string                 `json:"command" binding:"required"`
		Params  map[string]interface{} `json:"params"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: sns and command are required"))
		return
	}

	if len(req.SNs) == 0 {
		response.HandleError(c, apperr.BadRequest("sns cannot be empty"))
		return
	}
	if len(req.SNs) > 50 {
		response.HandleError(c, apperr.BadRequest("batch size cannot exceed 50"))
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

func (h *DeviceHandler) GetTelemetry(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	startTime := c.Query("startTime")
	endTime := c.Query("endTime")
	granularity := c.DefaultQuery("granularity", "")

	// 分页参数
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSizeParam := getPageSize(c, 20)
	if page < 1 {
		page = 1
	}
	if pageSizeParam < 1 || pageSizeParam > 500 {
		pageSizeParam = 20
	}

	// 支持 granularity+pageSize 作为 startTime/endTime 的替代参数
	if startTime == "" || endTime == "" {
		if granularity == "" {
			granularity = "day"
		}
		rangeSizeStr := c.DefaultQuery("page_size", c.DefaultQuery("pageSize", "7"))
		rangeSize, _ := strconv.Atoi(rangeSizeStr)
		if rangeSize <= 0 || rangeSize > 365 {
			rangeSize = 7
		}

		now := timezone.NowUTC()
		endTime = now.Format(time.RFC3339)

		switch granularity {
		case "hour":
			startTime = now.Add(-time.Duration(rangeSize) * time.Hour).Format(time.RFC3339)
		case "week":
			startTime = now.AddDate(0, 0, -rangeSize*7).Format(time.RFC3339)
		case "month":
			startTime = now.AddDate(0, -rangeSize, 0).Format(time.RFC3339)
		default: // "day"
			startTime = now.AddDate(0, 0, -rangeSize).Format(time.RFC3339)
		}
	}

	data, err := h.deviceService.GetTelemetryData(c.Request.Context(), sn, startTime, endTime, granularity)
	if err != nil {
		log.Printf("[GetTelemetry] error: sn=%s, err=%v", sn, err)
		response.HandleError(c, apperr.Internal("获取遥测数据失败", err))
		return
	}

	// 支持降序排序
	sortOrder := c.DefaultQuery("sort", "asc")
	if sortOrder == "desc" {
		for i, j := 0, len(data)-1; i < j; i, j = i+1, j-1 {
			data[i], data[j] = data[j], data[i]
		}
	}

	// 应用分页
	total := int64(len(data))
	start := (page - 1) * pageSizeParam
	if start > len(data) {
		start = len(data)
	}
	end := start + pageSizeParam
	if end > len(data) {
		end = len(data)
	}
	pagedData := data[start:end]

	response.Page(c, pagedData, total, page, pageSizeParam)
}

func (h *DeviceHandler) GetLifecycleHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
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

	items, total, err := h.deviceService.GetLifecycleHistory(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		log.Printf("[GetLifecycleHistory] error: sn=%s, err=%v", sn, err)
		response.HandleError(c, apperr.Internal("获取生命周期历史失败", err))
		return
	}

	response.Page(c, items, total, page, pageSize)
}

func (h *DeviceHandler) GetUnbindRequests(c *gin.Context) {
	role := middleware.GetRole(c)
	if role != 0 {
		response.HandleError(c, apperr.Forbidden("admin only"))
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
		response.HandleError(c, apperr.Internal("get unbind requests failed", err))
		return
	}

	response.Page(c, items, total, page, pageSize)
}

func (h *DeviceHandler) ApproveUnbind(c *gin.Context) {
	role := middleware.GetRole(c)
	if role != 0 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request id"))
		return
	}

	userID := middleware.GetUserID(c)
	var req struct {
		Comment string `json:"comment"`
	}
	c.ShouldBindJSON(&req)

	if err := h.deviceService.ApproveUnbind(c.Request.Context(), id, userID, req.Comment); err != nil {
		log.Printf("[ApproveUnbind] error: id=%d, err=%v", id, err)
		response.HandleError(c, apperr.Internal("操作失败，请稍后重试", err))
		return
	}

	response.SuccessWithMessage(c, "unbind approved", nil)
}

func (h *DeviceHandler) RejectUnbind(c *gin.Context) {
	role := middleware.GetRole(c)
	if role != 0 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request id"))
		return
	}

	userID := middleware.GetUserID(c)
	var req struct {
		Comment string `json:"comment"`
	}
	c.ShouldBindJSON(&req)

	if err := h.deviceService.RejectUnbind(c.Request.Context(), id, userID, req.Comment); err != nil {
		log.Printf("[RejectUnbind] error: id=%d, err=%v", id, err)
		response.HandleError(c, apperr.Internal("操作失败，请稍后重试", err))
		return
	}

	response.SuccessWithMessage(c, "unbind rejected", nil)
}

func (h *DeviceHandler) DeleteDevice(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if device == nil {
		response.HandleError(c, apperr.NotFound("device not found"))
		return
	}

	if !isAdmin && device.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	if err := h.deviceService.Delete(c.Request.Context(), sn); err != nil {
		response.HandleError(c, apperr.Internal("delete device failed", err))
		return
	}

	response.SuccessWithMessage(c, "device deleted", nil)
}

// AssignInstallerRequest 分配安装商的请求
type AssignInstallerRequest struct {
	InstallerID int64 `json:"installerId" binding:"required"`
}

// AssignInstaller 分配设备给安装商
func (h *DeviceHandler) AssignInstaller(c *gin.Context) {
	// Only admin can assign installers
	if middleware.GetRole(c) != 0 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}

	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("device sn is required"))
		return
	}

	var req AssignInstallerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// 验证设备存在
	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil || device == nil {
		response.HandleError(c, apperr.NotFound("device not found"))
		return
	}

	// 更新设备的installer_id
	err = h.deviceService.UpdateInstallerID(c.Request.Context(), sn, req.InstallerID)
	if err != nil {
		response.HandleError(c, apperr.Internal("failed to assign installer", err))
		return
	}

	response.SuccessWithMessage(c, "installer assigned successfully", gin.H{"sn": sn, "installerId": req.InstallerID})
}

// BatchAssignInstallerRequest 批量分配安装商的请求
type BatchAssignInstallerRequest struct {
	DeviceSNs   []string `json:"deviceSns" binding:"required"`
	InstallerID int64    `json:"installerId" binding:"required"`
}

// BatchAssignInstaller 批量分配设备给安装商
func (h *DeviceHandler) BatchAssignInstaller(c *gin.Context) {
	// Only admin can batch assign installers
	if middleware.GetRole(c) != 0 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}

	var req BatchAssignInstallerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if len(req.DeviceSNs) == 0 {
		response.HandleError(c, apperr.BadRequest("deviceSns is required"))
		return
	}

	// 批量更新设备的installer_id
	err := h.deviceService.BatchUpdateInstallerID(c.Request.Context(), req.DeviceSNs, req.InstallerID)
	if err != nil {
		response.HandleError(c, apperr.Internal("failed to batch assign installer", err))
		return
	}

	response.SuccessWithMessage(c, "installer assigned successfully", gin.H{"count": len(req.DeviceSNs), "installerId": req.InstallerID})
}

// RemoveInstaller 移除设备的安装商分配
func (h *DeviceHandler) RemoveInstaller(c *gin.Context) {
	// Only admin can remove installers
	if middleware.GetRole(c) != 0 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}

	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("device sn is required"))
		return
	}

	// 更新设备的installer_id为null
	err := h.deviceService.UpdateInstallerID(c.Request.Context(), sn, 0)
	if err != nil {
		response.HandleError(c, apperr.Internal("failed to remove installer", err))
		return
	}

	response.SuccessWithMessage(c, "installer removed successfully", nil)
}

// ImportExcel 通过 Excel 批量导入设备并绑定到当前用户。
// Excel 格式：第一行为表头（跳过），后续每行包含：
//   - A列: SN（必填）
//   - B列: 型号（可选）
//   - C列: 电站ID（可选）
func (h *DeviceHandler) ImportExcel(c *gin.Context) {
	userID := middleware.GetUserID(c)

	file, err := c.FormFile("file")
	if err != nil {
		response.HandleError(c, apperr.BadRequest("请选择要上传的文件"))
		return
	}

	src, err := file.Open()
	if err != nil {
		response.HandleError(c, apperr.Internal("打开文件失败", err))
		return
	}
	defer src.Close()

	f, err := excelize.OpenReader(src)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无法解析Excel文件，请确保为 .xlsx 格式"))
		return
	}
	defer f.Close()

	sheetName := f.GetSheetName(0)
	rows, err := f.GetRows(sheetName)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("读取Excel数据失败"))
		return
	}

	successCount := 0
	failedCount := 0
	var importErrors []string

	for i, row := range rows {
		if i == 0 {
			// 跳过表头行
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

		// 可选：从C列读取电站ID
		var stationID int64
		if len(row) > 2 {
			sVal := strings.TrimSpace(row[2])
			if sVal != "" {
				stationID, _ = strconv.ParseInt(sVal, 10, 64)
			}
		}

		// 查询设备是否存在，不存在则创建
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

		// 可选：如果B列有型号信息，更新设备型号
		if len(row) > 1 {
			modelVal := strings.TrimSpace(row[1])
			if modelVal != "" {
				h.deviceService.Update(c.Request.Context(), sn, modelVal, nil, "", "")
			}
		}

		successCount++
	}

	log.Printf("[ImportExcel] userID=%d, success=%d, failed=%d", userID, successCount, failedCount)

	response.Success(c, gin.H{
		"success": successCount,
		"failed":  failedCount,
		"errors":  importErrors,
	})
}

// ExportTelemetry 导出设备遥测数据为 CSV 格式。
// 支持查询参数：start_time / startTime, end_time / endTime, granularity
func (h *DeviceHandler) ExportTelemetry(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	startTime := c.Query("start_time")
	if startTime == "" {
		startTime = c.Query("startTime")
	}
	endTime := c.Query("end_time")
	if endTime == "" {
		endTime = c.Query("endTime")
	}
	granularity := c.DefaultQuery("granularity", "")

	// 提供默认时间范围（最近7天）
	if startTime == "" || endTime == "" {
		if granularity == "" {
			granularity = "day"
		}
		now := timezone.NowUTC()
		endTime = now.Format(time.RFC3339)
		startTime = now.AddDate(0, 0, -7).Format(time.RFC3339)
	}

	data, err := h.deviceService.GetTelemetryData(c.Request.Context(), sn, startTime, endTime, granularity)
	if err != nil {
		log.Printf("[ExportTelemetry] error: sn=%s, err=%v", sn, err)
		response.HandleError(c, apperr.Internal("获取遥测数据失败", err))
		return
	}

	// 收集所有字段名并排序，保证列顺序一致
	fieldSet := make(map[string]bool)
	for _, row := range data {
		for k := range row {
			fieldSet[k] = true
		}
	}
	var headers []string
	for field := range fieldSet {
		headers = append(headers, field)
	}
	sort.Strings(headers)

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=telemetry_%s.csv", sn))

	writer := csv.NewWriter(c.Writer)
	// 写入表头
	writer.Write(headers)
	// 写入数据行
	for _, row := range data {
		record := make([]string, len(headers))
		for i, field := range headers {
			val := row[field]
			if val == nil {
				record[i] = ""
			} else {
				record[i] = fmt.Sprintf("%v", val)
			}
		}
		writer.Write(record)
	}
	writer.Flush()
}

// ExportTelemetryExcel 导出设备遥测数据为 Excel(xlsx) 格式。
// 支持查询参数：start_time / startTime, end_time / endTime, granularity
func (h *DeviceHandler) ExportTelemetryExcel(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	startTime := c.Query("start_time")
	if startTime == "" {
		startTime = c.Query("startTime")
	}
	endTime := c.Query("end_time")
	if endTime == "" {
		endTime = c.Query("endTime")
	}
	granularity := c.DefaultQuery("granularity", "")

	// 提供默认时间范围（最近7天）
	if startTime == "" || endTime == "" {
		if granularity == "" {
			granularity = "day"
		}
		now := timezone.NowUTC()
		endTime = now.Format(time.RFC3339)
		startTime = now.AddDate(0, 0, -7).Format(time.RFC3339)
	}

	data, err := h.deviceService.GetTelemetryData(c.Request.Context(), sn, startTime, endTime, granularity)
	if err != nil {
		log.Printf("[ExportTelemetryExcel] error: sn=%s, err=%v", sn, err)
		response.HandleError(c, apperr.Internal("获取遥测数据失败", err))
		return
	}

	// 收集所有字段名并排序
	fieldSet := make(map[string]bool)
	for _, row := range data {
		for k := range row {
			fieldSet[k] = true
		}
	}
	var headers []string
	for field := range fieldSet {
		headers = append(headers, field)
	}
	sort.Strings(headers)

	f := excelize.NewFile()
	defer f.Close()
	sheetName := "Telemetry"
	f.SetSheetName(f.GetSheetName(0), sheetName)

	// 写入表头
	for col, header := range headers {
		cell, _ := excelize.CoordinatesToCellName(col+1, 1)
		f.SetCellValue(sheetName, cell, header)
	}

	// 写入数据行
	for rowIdx, row := range data {
		for col, field := range headers {
			cell, _ := excelize.CoordinatesToCellName(col+1, rowIdx+2)
			val := row[field]
			if val != nil {
				f.SetCellValue(sheetName, cell, val)
			} else {
				f.SetCellValue(sheetName, cell, "")
			}
		}
	}

	c.Header("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=telemetry_%s.xlsx", sn))

	if err := f.Write(c.Writer); err != nil {
		log.Printf("[ExportTelemetryExcel] write error: sn=%s, err=%v", sn, err)
	}
}
