package handler

import (
	"context"
	"fmt"
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
	"github.com/jackc/pgx/v5/pgxpool"
)

type StationHandler struct {
	stationService *service.StationService
	deviceService  *service.DeviceService
	userService    *service.UserService
	db             *pgxpool.Pool
}

func NewStationHandler(stationService *service.StationService, deviceService *service.DeviceService, userService *service.UserService, db *pgxpool.Pool) *StationHandler {
	return &StationHandler{
		stationService: stationService,
		deviceService:  deviceService,
		userService:    userService,
		db:             db,
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

	// 记录审计日志
	logAudit(c, h.userService, "create", "station", fmt.Sprintf("%d", station.ID), fmt.Sprintf(`{"name":"%s"}`, req.Name))

	response.Success(c, station)
}

// logAudit 记录审计日志的辅助函数
func logAudit(c *gin.Context, userService *service.UserService, action, resourceType, resourceID, detail string) {
	userID := middleware.GetUserID(c)
	phone := middleware.GetPhone(c)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		userService.LogAudit(ctx, userID, phone, action, resourceType, resourceID, detail, c.ClientIP())
	}()
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
	role := middleware.GetRole(c)
	isAdmin := role == 0
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

	// 超级管理员可以修改任意电站
	if !isAdmin && station.UserID != userID {
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
	role := middleware.GetRole(c)
	isAdmin := role == 0
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

	// 超级管理员可以删除任意电站
	if !isAdmin && station.UserID != userID {
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
	role := middleware.GetRole(c)
	isAdmin := role == 0
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

	// 超级管理员可以访问任意电站
	if !isAdmin && station.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	devices, _ := h.deviceService.GetByStationID(c.Request.Context(), stationID)

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

	_, totalPower, _ := h.deviceService.GetStationRealtimeSummary(c.Request.Context(), stationID, station.Timezone)
	dailyEnergy, _ := h.deviceService.GetStationTodayEnergy(c.Request.Context(), stationID, station.Timezone)
	totalEnergy, monthEnergy := h.deviceService.GetStationEnergySummary(c.Request.Context(), stationID, station.Timezone)
	yearEnergy := h.deviceService.GetStationYearEnergy(c.Request.Context(), stationID, station.Timezone)

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
	pageSize := getPageSize(c, 20)

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

		todayEnergy, _ := h.deviceService.GetStationTodayEnergy(ctx, st.ID, st.Timezone)
		totalEnergy, _ := h.deviceService.GetStationEnergySummary(ctx, st.ID, st.Timezone)

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
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
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

		_, tp, _ := h.deviceService.GetStationRealtimeSummary(c.Request.Context(), station.ID, station.Timezone)
		totalPower = tp

		dailyEnergy, _ := h.deviceService.GetStationTodayEnergy(c.Request.Context(), station.ID, station.Timezone)
		todayData, _ := h.stationService.GetDayData(c.Request.Context(), station.ID, timezone.TodayInTimezone(station.Timezone))
		todayIncome := 0.0
		if todayData != nil {
			todayIncome = todayData.Income
		}

		stationTotal, monthEnergy := h.deviceService.GetStationEnergySummary(c.Request.Context(), station.ID, station.Timezone)

		summaries = append(summaries, StationSummary{
			StationID:   station.ID,
			StationName: station.Name,
			Province:    station.Province,
			City:        station.City,
			District:    station.District,
			Latitude:    station.Latitude,
			Longitude:   station.Longitude,
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

	tz := station.Timezone
	if startDate == "" {
		startDate = timezone.NowInTimezone(tz).AddDate(0, 0, -7).Format("2006-01-02")
	}
	if endDate == "" {
		endDate = timezone.TodayInTimezone(tz)
	}

	data, err := h.stationService.GetStatistics(c.Request.Context(), stationID, startDate, endDate, period, tz)
	if err != nil {
		response.HandleError(c, apperr.Internal("get statistics failed", err))
		return
	}

	response.Success(c, data)
}
