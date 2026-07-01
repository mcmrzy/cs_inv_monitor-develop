package handler

import (
	"log"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
)

type StationHandler struct {
	stationService *service.StationService
	deviceService  *service.DeviceService
}

func NewStationHandler(stationService *service.StationService, deviceService *service.DeviceService) *StationHandler {
	return &StationHandler{
		stationService: stationService,
		deviceService:  deviceService,
	}
}

type CreateStationRequest struct {
	Name        string  `json:"name" binding:"required"`
	Province    string  `json:"province"`
	City        string  `json:"city"`
	District    string  `json:"district"`
	Address     string  `json:"address"`
	Capacity    float64 `json:"capacity"`
	PanelCount  int     `json:"panel_count"`
	PeakPrice   float64 `json:"peak_price"`
	ValleyPrice float64 `json:"valley_price"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	Timezone    string  `json:"timezone"`
}

func (h *StationHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req CreateStationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	station := &model.Station{
		UserID:      userID,
		Name:        req.Name,
		Province:    req.Province,
		City:        req.City,
		District:    req.District,
		Address:     req.Address,
		Capacity:    req.Capacity,
		PanelCount:  req.PanelCount,
		PeakPrice:   req.PeakPrice,
		ValleyPrice: req.ValleyPrice,
		Latitude:    req.Latitude,
		Longitude:   req.Longitude,
		Timezone:    req.Timezone,
		Status:      1,
	}

	// 验证时区, 默认使用 Asia/Shanghai
	if station.Timezone == "" {
		station.Timezone = timezone.AsiaShanghai
	}
	if err := timezone.ValidateTimezone(station.Timezone); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid timezone: "+station.Timezone))
		return
	}

	if err := h.stationService.Create(c.Request.Context(), station); err != nil {
		log.Printf("[CreateStation] error: user_id=%d, err=%v", userID, err)
		response.HandleError(c, apperr.Internal("创建电站失败，请稍后重试", err))
		return
	}

	response.Success(c, station)
}

type UpdateStationRequest struct {
	Name        string  `json:"name"`
	Province    string  `json:"province"`
	City        string  `json:"city"`
	District    string  `json:"district"`
	Address     string  `json:"address"`
	Capacity    float64 `json:"capacity"`
	PanelCount  int     `json:"panel_count"`
	PeakPrice   float64 `json:"peak_price"`
	ValleyPrice float64 `json:"valley_price"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	Timezone    string  `json:"timezone"`
}

func (h *StationHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid station id"))
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if station == nil {
		response.HandleError(c, apperr.NotFound("station not found"))
		return
	}

	if station.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	var req UpdateStationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if req.Name != "" {
		station.Name = req.Name
	}
	if req.Province != "" {
		station.Province = req.Province
	}
	if req.City != "" {
		station.City = req.City
	}
	if req.District != "" {
		station.District = req.District
	}
	if req.Address != "" {
		station.Address = req.Address
	}
	if req.Capacity > 0 {
		station.Capacity = req.Capacity
	}
	if req.PanelCount > 0 {
		station.PanelCount = req.PanelCount
	}
	if req.PeakPrice > 0 {
		station.PeakPrice = req.PeakPrice
	}
	if req.ValleyPrice > 0 {
		station.ValleyPrice = req.ValleyPrice
	}
	if req.Latitude != 0 {
		station.Latitude = req.Latitude
	}
	if req.Longitude != 0 {
		station.Longitude = req.Longitude
	}
	if req.Timezone != "" {
		if err := timezone.ValidateTimezone(req.Timezone); err != nil {
			response.HandleError(c, apperr.BadRequest("invalid timezone: "+req.Timezone))
			return
		}
		station.Timezone = req.Timezone
	}

	if err := h.stationService.Update(c.Request.Context(), station); err != nil {
		response.HandleError(c, apperr.Internal("update station failed", err))
		return
	}

	response.Success(c, station)
}

func (h *StationHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid station id"))
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if station == nil {
		response.HandleError(c, apperr.NotFound("station not found"))
		return
	}

	if station.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	if err := h.stationService.Delete(c.Request.Context(), stationID); err != nil {
		response.HandleError(c, apperr.Internal("delete station failed", err))
		return
	}

	response.SuccessWithMessage(c, "station deleted", nil)
}

func (h *StationHandler) Assign(c *gin.Context) {
	role := middleware.GetRole(c)
	isAdmin := role == 0

	if !isAdmin {
		response.HandleError(c, apperr.Forbidden("only admin can assign station"))
		return
	}

	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid station id"))
		return
	}

	var req struct {
		UserID int64 `json:"user_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if req.UserID <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid user_id"))
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if station == nil {
		response.HandleError(c, apperr.NotFound("station not found"))
		return
	}

	if err := h.stationService.Assign(c.Request.Context(), stationID, req.UserID); err != nil {
		response.HandleError(c, apperr.Internal("assign station failed", err))
		return
	}

	response.SuccessWithMessage(c, "station assigned", nil)
}

func (h *StationHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid station id"))
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	if station == nil {
		response.HandleError(c, apperr.NotFound("station not found"))
		return
	}

	if station.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	devices, _ := h.deviceService.GetByStationID(c.Request.Context(), stationID)

	// 丰富设备实时数据（与设备列表API保持一致）
	for _, device := range devices {
		rtData, err := h.deviceService.GetRealtimeData(c.Request.Context(), device.SN)
		if err == nil && rtData != nil {
			// 使用 Redis 在线状态修正设备状态：离线时快速标记
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

			// 兼容扁平格式的 daily_energy
			if device.DailyEnergy == 0 {
				if v, ok := rtData["daily_energy"]; ok && v != nil {
					if f, ok := toFloat64(v); ok {
						device.DailyEnergy = f
					}
				}
			}
		}
	}

	_, totalPower, _ := h.deviceService.GetStationRealtimeSummary(c.Request.Context(), stationID)
	dailyEnergy, _ := h.deviceService.GetStationTodayEnergy(c.Request.Context(), stationID)
	totalEnergy, monthEnergy := h.deviceService.GetStationEnergySummary(c.Request.Context(), stationID)
	yearEnergy := h.deviceService.GetStationYearEnergy(c.Request.Context(), stationID)

	pvPower, loadPower, gridPower, battPower, battSoc := h.deviceService.GetStationPowerBreakdown(c.Request.Context(), stationID)

	onlineCount := 0
	for _, d := range devices {
		if d.Status == 1 || d.Status == 2 {
			onlineCount++
		}
	}

	stationMap := map[string]interface{}{
		"id":           station.ID,
		"station_name": station.Name,
		"name":         station.Name,
		"province":     station.Province,
		"city":         station.City,
		"district":     station.District,
		"address":      station.Address,
		"capacity":     station.Capacity,
		"panel_count":  station.PanelCount,
		"latitude":     station.Latitude,
		"longitude":    station.Longitude,
		"timezone":     station.Timezone,
		"status":       station.Status,
		"device_count": len(devices),
		"online_count": onlineCount,
		"today_energy": dailyEnergy,
		"total_energy": totalEnergy,
		"month_energy": monthEnergy,
		"year_energy":  yearEnergy,
		"total_power":  totalPower,
		"pv_power":     pvPower,
		"load_power":   loadPower,
		"grid_power":   gridPower,
		"batt_power":   battPower,
		"batt_soc":     battSoc,
	}

	result := map[string]interface{}{
		"station": stationMap,
		"devices": devices,
	}

	response.Success(c, result)
}

func (h *StationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var stations []*model.Station
	var total int64
	var err error

	// 超级管理员始终返回所有电站
	if isAdmin {
		stations, total, err = h.stationService.GetAll(c.Request.Context(), page, pageSize)
	} else {
		stations, total, err = h.stationService.GetByUserID(c.Request.Context(), userID, page, pageSize)
	}

	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	// 为每个电站填充设备统计和发电数据
	ctx := c.Request.Context()
	enrichedStations := make([]map[string]interface{}, 0, len(stations))
	for _, st := range stations {
		devices, _ := h.deviceService.GetByStationID(ctx, st.ID)
		deviceCount := len(devices)
		onlineCount := 0
		faultCount := 0
		for _, d := range devices {
			if d.Status == 1 || d.Status == 2 {
				onlineCount++
			}
			if d.Status == 2 {
				faultCount++
			}
		}

		todayEnergy, _ := h.deviceService.GetStationTodayEnergy(ctx, st.ID)
		totalEnergy, _ := h.deviceService.GetStationEnergySummary(ctx, st.ID)

		item := map[string]interface{}{
			"id":                 st.ID,
			"user_id":            st.UserID,
			"name":               st.Name,
			"province":           st.Province,
			"city":               st.City,
			"district":           st.District,
			"address":            st.Address,
			"capacity":           st.Capacity,
			"panel_count":        st.PanelCount,
			"latitude":           st.Latitude,
			"longitude":          st.Longitude,
			"timezone":           st.Timezone,
			"status":             st.Status,
			"created_at":         st.CreatedAt,
			"updated_at":         st.UpdatedAt,
			"device_count":       deviceCount,
			"online_count":       onlineCount,
			"fault_count":        faultCount,
			"today_generation":   todayEnergy,
			"total_generation":   totalEnergy,
		}
		enrichedStations = append(enrichedStations, item)
	}

	response.Page(c, enrichedStations, total, page, pageSize)
}

type StationSummary struct {
	StationID   int64   `json:"station_id"`
	StationName string  `json:"station_name"`
	Province    string  `json:"province"`
	City        string  `json:"city"`
	District    string  `json:"district"`
	Capacity    float64 `json:"capacity"`
	DeviceCount int     `json:"device_count"`
	OnlineCount int     `json:"online_count"`
	FaultCount  int     `json:"fault_count"`
	TotalPower  float64 `json:"total_power"`
	TodayEnergy float64 `json:"today_energy"`
	TotalEnergy float64 `json:"total_energy"`
	MonthEnergy float64 `json:"month_energy"`
	TodayIncome float64 `json:"today_income"`
	Status      int     `json:"status"`
}

func (h *StationHandler) GetSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0

	var stations []*model.Station
	var total int64
	var err error

	// 超级管理员始终返回所有电站
	if isAdmin {
		stations, total, err = h.stationService.GetAll(c.Request.Context(), 1, 9999)
	} else {
		stations, _, err = h.stationService.GetByUserID(c.Request.Context(), userID, 1, 100)
		total = int64(len(stations))
	}
	if err != nil {
		response.HandleError(c, apperr.Internal("system error", err))
		return
	}

	var totalEnergy, totalIncome float64
	var totalDeviceCount, totalOnlineCount, totalFaultCount int
	var grandTotalEnergy, grandMonthEnergy float64

	summaries := make([]StationSummary, 0, len(stations))
	for _, station := range stations {
		// 直接使用电站的状态而不是计算设备状态
		devices, _ := h.deviceService.GetByStationID(c.Request.Context(), station.ID)
		deviceCount := len(devices)
		onlineCount := 0
		faultCount := 0
		totalPower := 0.0

		// 统计设备状态：status=1(在线) 和 status=2(故障) 都算在线
		for _, device := range devices {
			if device.Status == 1 || device.Status == 2 {
				onlineCount++
			}
			if device.Status == 2 {
				faultCount++
			}
		}

		_, tp, _ := h.deviceService.GetStationRealtimeSummary(c.Request.Context(), station.ID)
		totalPower = tp

		dailyEnergy, _ := h.deviceService.GetStationTodayEnergy(c.Request.Context(), station.ID)
		todayData, _ := h.stationService.GetDayData(c.Request.Context(), station.ID, time.Now().Format("2006-01-02"))
		todayIncome := 0.0
		if todayData != nil {
			todayIncome = todayData.Income
		}

		stationTotal, monthEnergy := h.deviceService.GetStationEnergySummary(c.Request.Context(), station.ID)

		summaries = append(summaries, StationSummary{
			StationID:   station.ID,
			StationName: station.Name,
			Province:    station.Province,
			City:        station.City,
			District:    station.District,
			Capacity:    station.Capacity,
			DeviceCount: deviceCount,
			OnlineCount: onlineCount,
			FaultCount:  faultCount,
			TotalPower:  totalPower,
			TodayEnergy: dailyEnergy,
			TotalEnergy: stationTotal,
			MonthEnergy: monthEnergy,
			TodayIncome: todayIncome,
			Status:      station.Status,
		})

		totalEnergy += dailyEnergy
		totalIncome += todayIncome
		totalDeviceCount += deviceCount
		totalOnlineCount += onlineCount
		totalFaultCount += faultCount
		grandTotalEnergy += stationTotal
		grandMonthEnergy += monthEnergy
	}

	result := map[string]interface{}{
		"stations": summaries,
		"summary": map[string]interface{}{
			// 前端期望的 camelCase 字段
			"totalStations":    total,
			"totalDevices":     totalDeviceCount,
			"onlineDevices":    totalOnlineCount,
			"todayGeneration":  totalEnergy,
			"totalGeneration":  grandTotalEnergy,
			"monthGeneration":  grandMonthEnergy,
			"faultDevices":     totalFaultCount,
			"totalIncome":      totalIncome,
			// 兼容旧的 snake_case 字段
			"today_energy": totalEnergy,
			"total_energy": grandTotalEnergy,
			"month_energy": grandMonthEnergy,
			"total_income": totalIncome,
			"total_power":  float64(0),
			"device_count": totalDeviceCount,
			"online_count": totalOnlineCount,
			"fault_count":  totalFaultCount,
		},
	}

	response.Success(c, result)
}

func (h *StationHandler) GetStatistics(c *gin.Context) {
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid station id"))
		return
	}

	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	isAdmin := role == 0
	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil || station == nil {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}
	// 超级管理员可以访问任意电站的统计数据
	if !isAdmin && station.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "day")

	if startDate == "" {
		startDate = time.Now().AddDate(0, 0, -7).Format("2006-01-02")
	}
	if endDate == "" {
		endDate = time.Now().Format("2006-01-02")
	}

	data, err := h.stationService.GetStatistics(c.Request.Context(), stationID, startDate, endDate, period)
	if err != nil {
		response.HandleError(c, apperr.Internal("get statistics failed", err))
		return
	}

	response.Success(c, data)
}
