package handler

import (
	"encoding/json"
	"log"
	"regexp"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

var snRegex = regexp.MustCompile(`^[A-Z0-9-]{8,64}$`)

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
	role := middleware.GetRole(c)
	isAdmin := role == 0

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}

	// 支持 pageSize 和 page_size 两种格式
	pageSizeStr := c.Query("pageSize")
	if pageSizeStr == "" {
		pageSizeStr = c.DefaultQuery("page_size", "20")
	}
	pageSize, _ := strconv.Atoi(pageSizeStr)
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
		response.InternalError(c, "system error")
		return
	}

	for _, device := range devices {
		rtData, err := h.deviceService.GetRealtimeData(c.Request.Context(), device.SN)
		if err == nil && rtData != nil {
			// 使用实时数据的 online 字段修正设备状态：
			// - Redis 说离线且数据库不是离线 → 快速标记为离线（比定时任务更快）
			// - Redis 说在线 → 保持数据库状态（可能是 1=在线 或 2=故障）
			if online, ok := rtData["online"].(bool); ok {
				if !online && device.Status != 0 {
					device.Status = 0
				}
			}

			// 从嵌套的 info 对象读取设备信息（支持 {"info": {...}} 和 {"info": {"data": {...}}} 两种格式）
			var info map[string]interface{}
			if v, ok := rtData["info"].(map[string]interface{}); ok {
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
				if v, ok := info["rated_power"]; ok && v != nil {
					if f, ok := toFloat64(v); ok && f > 0 && device.RatedPower == 0 {
						device.RatedPower = f
					}
				}
				if v, ok := info["firmware_arm"]; ok && v != nil {
					if s, ok := v.(string); ok && s != "" && device.FirmwareArm == "" {
						device.FirmwareArm = s
					}
				}
			}

			// 从嵌套的 energy 对象读取日发电量（支持 {"energy": {...}} 和 {"energy": {"data": {...}}} 两种格式）
			var energyData map[string]interface{}
			if v, ok := rtData["energy"].(map[string]interface{}); ok {
				energyData = v
				if innerData, ok := v["data"].(map[string]interface{}); ok {
					energyData = innerData
				}
			}
			if energyData != nil {
				if v, ok := energyData["daily_pv"]; ok && v != nil {
					if f, ok := toFloat64(v); ok {
						device.DailyEnergy = f
					}
				}
			}

			// 从嵌套的 ac 对象读取当前功率（支持 {"ac": {...}} 和 {"ac": {"data": {...}}} 两种格式）
			var acData map[string]interface{}
			if v, ok := rtData["ac"].(map[string]interface{}); ok {
				acData = v
				if innerData, ok := v["data"].(map[string]interface{}); ok {
					acData = innerData
				}
			}
			if acData != nil {
				if v, ok := acData["power"]; ok && v != nil {
					if f, ok := toFloat64(v); ok {
						device.CurrentPower = f
					}
				}
			}

			// 兼容旧的扁平格式
			if device.CurrentPower == 0 {
				if v, ok := rtData["power"]; ok && v != nil {
					if f, ok := toFloat64(v); ok {
						device.CurrentPower = f
					}
				} else if v, ok := rtData["ac_power"]; ok && v != nil {
					if f, ok := toFloat64(v); ok {
						device.CurrentPower = f
					}
				} else if v, ok := rtData["total_active_power"]; ok && v != nil {
					if f, ok := toFloat64(v); ok {
						device.CurrentPower = f
					}
				}
			}
		}
	}

	response.Page(c, devices, total, page, pageSize)
}

func toFloat64(v interface{}) (float64, bool) {
	switch val := v.(type) {
	case float64:
		return val, true
	case float32:
		return float64(val), true
	case int:
		return float64(val), true
	case int64:
		return float64(val), true
	case json.Number:
		f, err := val.Float64()
		return f, err == nil
	default:
		return 0, false
	}
}

func (h *DeviceHandler) GetDetail(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		response.NotFound(c, "device not found")
		return
	}

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
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
		response.BadRequest(c, "invalid request")
		return
	}

	if !snRegex.MatchString(req.SN) {
		response.BadRequest(c, "invalid SN format")
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
		if err.Error() == "device already bound" {
			response.Error(c, 5002, "device already bound")
			return
		}
		response.InternalError(c, "bind device failed")
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
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		response.NotFound(c, "device not found")
		return
	}

	if !isAdmin && device.UserID != userID {
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
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasControlPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	var req ControlRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.deviceService.ValidateControlCommand(c.Request.Context(), sn, req.Command); err != nil {
		log.Printf("[Control] validate command failed: sn=%s, err=%v", sn, err)
		response.BadRequest(c, "命令校验失败")
		return
	}

	if err := h.deviceService.SendCommand(c.Request.Context(), sn, req.Command, req.Params); err != nil {
		log.Printf("[Control] send command failed: sn=%s, err=%v", sn, err)
		response.Error(c, 5003, "发送命令失败，请稍后重试")
		return
	}

	response.SuccessWithMessage(c, "command sent", nil)
}

func (h *DeviceHandler) GetControlFields(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	fields, err := h.deviceService.GetControlFieldsBySN(c.Request.Context(), sn)
	if err != nil {
		response.InternalError(c, "查询控制字段失败")
		return
	}

	response.Success(c, fields)
}

// DEPRECATED: Device params removed. Use MQTT direct configuration.
// func (h *DeviceHandler) GetParams(c *gin.Context) {}
// func (h *DeviceHandler) UpdateParams(c *gin.Context) {}

func (h *DeviceHandler) GetHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
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
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}

	alarms, total, err := h.alarmService.GetByDeviceSN(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.InternalError(c, "system error")
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

	if !isAdmin && device.UserID != userID {
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
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "day")

	// 当日期参数为空时，提供合理默认值
	if startDate == "" {
		now := time.Now()
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
		endDate = time.Now().Format("2006-01-02")
	}

	data, err := h.deviceService.GetStatistics(c.Request.Context(), sn, startDate, endDate, period)
	if err != nil {
		response.InternalError(c, "get statistics failed")
		return
	}

	response.Success(c, data)
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
		response.Forbidden(c, "permission denied")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", c.DefaultQuery("page_size", "20")))
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}

	commands, total, err := h.deviceService.GetCommandHistory(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.InternalError(c, "get commands failed")
		return
	}

	response.Page(c, commands, total, page, pageSize)
}

func (h *DeviceHandler) GetTelemetry(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Forbidden(c, "permission denied")
		return
	}

	startTime := c.Query("startTime")
	endTime := c.Query("endTime")
	granularity := c.DefaultQuery("granularity", "")

	// 分页参数
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSizeParam, _ := strconv.Atoi(c.DefaultQuery("pageSize", c.DefaultQuery("page_size", "20")))
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
		rangeSizeStr := c.DefaultQuery("pageSize", "7")
		rangeSize, _ := strconv.Atoi(rangeSizeStr)
		if rangeSize <= 0 || rangeSize > 365 {
			rangeSize = 7
		}

		now := time.Now()
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
		response.InternalError(c, "获取遥测数据失败")
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
		response.Forbidden(c, "permission denied")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", c.DefaultQuery("page_size", "20")))
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}

	items, total, err := h.deviceService.GetLifecycleHistory(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		log.Printf("[GetLifecycleHistory] error: sn=%s, err=%v", sn, err)
		response.InternalError(c, "获取生命周期历史失败")
		return
	}

	response.Page(c, items, total, page, pageSize)
}

func (h *DeviceHandler) GetUnbindRequests(c *gin.Context) {
	role := middleware.GetRole(c)
	if role != 0 {
		response.Forbidden(c, "admin only")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", c.DefaultQuery("page_size", "10")))
	if pageSize < 1 {
		pageSize = 10
	}
	if pageSize > 100 {
		pageSize = 100
	}

	items, total, err := h.deviceService.GetUnbindRequests(c.Request.Context(), page, pageSize)
	if err != nil {
		response.InternalError(c, "get unbind requests failed")
		return
	}

	response.Page(c, items, total, page, pageSize)
}

func (h *DeviceHandler) ApproveUnbind(c *gin.Context) {
	role := middleware.GetRole(c)
	if role != 0 {
		response.Forbidden(c, "admin only")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid request id")
		return
	}

	userID := middleware.GetUserID(c)
	var req struct {
		Comment string `json:"comment"`
	}
	c.ShouldBindJSON(&req)

	if err := h.deviceService.ApproveUnbind(c.Request.Context(), id, userID, req.Comment); err != nil {
		log.Printf("[ApproveUnbind] error: id=%d, err=%v", id, err)
		response.InternalError(c, "操作失败，请稍后重试")
		return
	}

	response.SuccessWithMessage(c, "unbind approved", nil)
}

func (h *DeviceHandler) RejectUnbind(c *gin.Context) {
	role := middleware.GetRole(c)
	if role != 0 {
		response.Forbidden(c, "admin only")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid request id")
		return
	}

	userID := middleware.GetUserID(c)
	var req struct {
		Comment string `json:"comment"`
	}
	c.ShouldBindJSON(&req)

	if err := h.deviceService.RejectUnbind(c.Request.Context(), id, userID, req.Comment); err != nil {
		log.Printf("[RejectUnbind] error: id=%d, err=%v", id, err)
		response.InternalError(c, "操作失败，请稍后重试")
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
		response.InternalError(c, "system error")
		return
	}

	if device == nil {
		response.NotFound(c, "device not found")
		return
	}

	if !isAdmin && device.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	if err := h.deviceService.Delete(c.Request.Context(), sn); err != nil {
		response.InternalError(c, "delete device failed")
		return
	}

	response.SuccessWithMessage(c, "device deleted", nil)
}
