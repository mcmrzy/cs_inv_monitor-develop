package handler

import (
	"regexp"
	"strconv"
	"strings"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
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
	isAdmin := middleware.GetIsSystemAdmin(c)

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
		response.Error(c, 500, "system error")
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

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
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

	// 附加型号字段元数据（始终返回，保证 API 响应结构一致）
	modelFields, mfErr := h.deviceService.GetModelFieldsBySN(c.Request.Context(), sn)
	if mfErr != nil {
		logger.Warn("GetModelFieldsBySN failed",
			zap.String("sn", sn), zap.Error(mfErr))
	}
	if modelFields == nil {
		modelFields = []model.DeviceModelField{}
	}
	result["model_fields"] = modelFields

	response.Success(c, result)
}

type CreateDeviceRequest struct {
	SN              string   `json:"sn" binding:"required"`
	Model           string   `json:"model"`
	RatedPower      *float64 `json:"ratedPower"`
	FirmwareVersion string   `json:"firmwareVersion"`
	HardwareVersion string   `json:"hardwareVersion"`
}

// Create creates a new device. Only admin and installer (role <= 4) can create devices.
func (h *DeviceHandler) Create(c *gin.Context) {
	isSystemAdmin := middleware.GetIsSystemAdmin(c)
	if !isSystemAdmin {
		response.Error(c, 403, "permission denied")
		return
	}

	var req CreateDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request body")
		return
	}

	if !deviceSNRegex.MatchString(req.SN) {
		response.Error(c, 400, "invalid SN format")
		return
	}

	// Check if device already exists
	existing, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if existing != nil {
		response.Error(c, 400, "device already exists")
		return
	}

	if err := h.deviceService.Create(c.Request.Context(), req.SN, req.Model, req.RatedPower, req.FirmwareVersion, req.HardwareVersion); err != nil {
		if strings.Contains(err.Error(), "already exists") {
			response.Error(c, 400, "device already exists")
			return
		}
		response.Error(c, 500, "failed to create device")
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
	isAdmin := middleware.GetIsSystemAdmin(c)

	// Ownership check: non-admin users can only update their own devices
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

	var req UpdateDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request body")
		return
	}
	if err := h.deviceService.Update(c.Request.Context(), sn, req.Model, req.RatedPower, req.FirmwareVersion, req.HardwareVersion); err != nil {
		response.Error(c, 500, "failed to update device")
		return
	}
	response.SuccessWithMessage(c, "device updated", nil)
}

func (h *DeviceHandler) DeleteDevice(c *gin.Context) {
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

	if err := h.deviceService.Delete(c.Request.Context(), sn); err != nil {
		response.Error(c, 500, "delete device failed")
		return
	}

	response.SuccessWithMessage(c, "device deleted", nil)
}

type AddDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	StationID int64  `json:"station_id"`
}

func (h *DeviceHandler) AddToStation(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	var req AddDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), req.SN)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if device == nil {
		response.Error(c, 5001, "device not found")
		return
	}

	if !isAdmin {
		// Check device ownership
		if device.UserID != userID {
			response.Error(c, 403, "permission denied")
			return
		}
		// Check station ownership
		station, err := h.stationService.GetByID(c.Request.Context(), req.StationID)
		if err != nil || station == nil {
			response.Error(c, 400, "station not found")
			return
		}
		if station.UserID != userID {
			response.Error(c, 403, "station not owned by you")
			return
		}
	}

	if err := h.deviceService.AddToStation(c.Request.Context(), req.SN, req.StationID); err != nil {
		response.Error(c, 500, "add to station failed")
		return
	}

	response.SuccessWithMessage(c, "device added to station", nil)
}

func (h *DeviceHandler) RemoveFromStation(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	sn := c.Param("sn")
	if sn == "" {
		response.Error(c, 400, "invalid sn")
		return
	}

	device, err := h.deviceService.GetBySN(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if device == nil {
		response.Error(c, 5001, "device not found")
		return
	}

	if !isAdmin && device.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	if err := h.deviceService.RemoveFromStation(c.Request.Context(), sn); err != nil {
		response.Error(c, 500, "remove from station failed")
		return
	}

	response.SuccessWithMessage(c, "device removed from station", nil)
}

func (h *DeviceHandler) ScanLocal(c *gin.Context) {
	userID := middleware.GetUserID(c)

	devices, err := h.deviceService.ScanLocalNetwork(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, 500, "scan failed")
		return
	}

	response.Success(c, devices)
}
