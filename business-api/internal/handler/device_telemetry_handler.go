package handler

import (
	"encoding/csv"
	"fmt"
	"sort"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
	"go.uber.org/zap"
)

// GetRealtimeData returns the latest realtime data for a device from Redis.
func (h *DeviceHandler) GetRealtimeData(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	data, err := h.deviceService.GetRealtimeData(c.Request.Context(), sn)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if data == nil {
		response.Error(c, 404, "no data")
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

// GetTelemetry returns paginated telemetry data for a device.
func (h *DeviceHandler) GetTelemetry(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
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
		logger.Error("GetTelemetry failed", zap.String("sn", sn), zap.Error(err))
		response.Error(c, 500, "获取遥测数据失败")
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

// GetHistory returns historical data for a device.
func (h *DeviceHandler) GetHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	period := c.DefaultQuery("period", "hour")

	tz := getUserTimezone(c.Request.Context(), h.db, userID)

	data, err := h.deviceService.GetHistoryData(c.Request.Context(), sn, startDate, endDate, period, tz)
	if err != nil {
		response.Error(c, 500, "get history failed")
		return
	}

	response.Success(c, data)
}

// GetAlarms returns paginated alarm events for a device.
func (h *DeviceHandler) GetAlarms(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
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
		response.Error(c, 500, "system error")
		return
	}

	response.Page(c, alarms, total, page, pageSize)
}

// GetLifecycleHistory returns the lifecycle event history for a device.
func (h *DeviceHandler) GetLifecycleHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
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
		logger.Error("GetLifecycleHistory failed", zap.String("sn", sn), zap.Error(err))
		response.Error(c, 500, "获取生命周期历史失败")
		return
	}

	response.Page(c, items, total, page, pageSize)
}

// ExportTelemetry exports device telemetry data as CSV.
// Supports query params: start_time / startTime, end_time / endTime, granularity.
func (h *DeviceHandler) ExportTelemetry(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
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
		logger.Error("ExportTelemetry failed", zap.String("sn", sn), zap.Error(err))
		response.Error(c, 500, "获取遥测数据失败")
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

// ExportTelemetryExcel exports device telemetry data as Excel(xlsx).
// Supports query params: start_time / startTime, end_time / endTime, granularity.
func (h *DeviceHandler) ExportTelemetryExcel(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
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
		logger.Error("ExportTelemetryExcel failed", zap.String("sn", sn), zap.Error(err))
		response.Error(c, 500, "获取遥测数据失败")
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
		logger.Error("ExportTelemetryExcel write failed", zap.String("sn", sn), zap.Error(err))
	}
}
