package handler

import (
	"fmt"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

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
	Capacity    float64 `json:"capacity" binding:"required"`
	PanelCount  int     `json:"panel_count"`
	PeakPrice   float64 `json:"peak_price"`
	ValleyPrice float64 `json:"valley_price"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
}

func (h *StationHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req CreateStationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
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
		Status:      1,
	}

	if err := h.stationService.Create(c.Request.Context(), station); err != nil {
		response.InternalError(c, "create station failed: "+err.Error())
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
}

func (h *StationHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid station id")
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if station == nil {
		response.NotFound(c, "station not found")
		return
	}

	if station.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	var req UpdateStationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
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

	if err := h.stationService.Update(c.Request.Context(), station); err != nil {
		response.InternalError(c, "update station failed")
		return
	}

	response.Success(c, station)
}

func (h *StationHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid station id")
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if station == nil {
		response.NotFound(c, "station not found")
		return
	}

	if station.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	if err := h.stationService.Delete(c.Request.Context(), stationID); err != nil {
		response.InternalError(c, "delete station failed")
		return
	}

	response.SuccessWithMessage(c, "station deleted", nil)
}

func (h *StationHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid station id")
		return
	}

	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if station == nil {
		response.NotFound(c, "station not found")
		return
	}

	if station.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	devices, _ := h.deviceService.GetByStationID(c.Request.Context(), stationID)

	_, totalPower, _ := h.deviceService.GetStationRealtimeSummary(c.Request.Context(), stationID)
	dailyEnergy, _ := h.deviceService.GetStationTodayEnergy(c.Request.Context(), stationID)
	totalEnergy, monthEnergy := h.deviceService.GetStationEnergySummary(c.Request.Context(), stationID)
	yearEnergy := h.deviceService.GetStationYearEnergy(c.Request.Context(), stationID)

	pvPower, loadPower, gridPower, battPower, battSoc := h.deviceService.GetStationPowerBreakdown(c.Request.Context(), stationID)

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
		"status":       station.Status,
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
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	stations, total, err := h.stationService.GetByUserID(c.Request.Context(), userID, page, pageSize)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Page(c, stations, total, page, pageSize)
}

type StationSummary struct {
	StationID     int64   `json:"station_id"`
	StationName   string  `json:"station_name"`
	Province      string  `json:"province"`
	City          string  `json:"city"`
	District      string  `json:"district"`
	Capacity      float64 `json:"capacity"`
	DeviceCount   int     `json:"device_count"`
	OnlineCount   int     `json:"online_count"`
	FaultCount    int     `json:"fault_count"`
	TotalPower    float64 `json:"total_power"`
	TodayEnergy   float64 `json:"today_energy"`
	TodayIncome   float64 `json:"today_income"`
	Status        int     `json:"status"`
}

func (h *StationHandler) GetSummary(c *gin.Context) {
	userID := middleware.GetUserID(c)

	stations, _, err := h.stationService.GetByUserID(c.Request.Context(), userID, 1, 100)
	if err != nil {
		fmt.Printf("[GetSummary Error] GetByUserID failed: %v\n", err)
		response.InternalError(c, "system error")
		return
	}

	var totalEnergy, totalIncome float64
	var totalDeviceCount, totalOnlineCount, totalFaultCount int
	var grandTotalEnergy, grandMonthEnergy float64

	summaries := make([]StationSummary, 0, len(stations))
	for _, station := range stations {
		devices, _ := h.deviceService.GetByStationID(c.Request.Context(), station.ID)
		deviceCount := len(devices)
		onlineCount := 0
		faultCount := 0
		totalPower := 0.0

		for _, device := range devices {
			if device.Status == 1 {
				onlineCount++
			} else if device.Status == 2 {
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
			TodayIncome: todayIncome,
			Status:      func() int { if onlineCount > 0 { return 1 }; return 0 }(),
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
			"today_energy":   totalEnergy,
			"total_energy":   grandTotalEnergy,
			"month_energy":   grandMonthEnergy,
			"total_income":   totalIncome,
			"total_power":    float64(0),
			"device_count":   totalDeviceCount,
			"online_count":   totalOnlineCount,
			"fault_count":    totalFaultCount,
		},
	}

	response.Success(c, result)
}

func (h *StationHandler) GetStatistics(c *gin.Context) {
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid station id")
		return
	}

	userID := middleware.GetUserID(c)
	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil || station == nil || station.UserID != userID {
		response.Forbidden(c, "permission denied")
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
		response.InternalError(c, "get statistics failed")
		return
	}

	response.Success(c, data)
}
