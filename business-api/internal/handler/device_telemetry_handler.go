package handler

import (
	"encoding/csv"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
	"go.uber.org/zap"
)

// telemetryFieldNamePattern 限定可请求的遥测字段名形状（与数据库列名一致）。
var telemetryFieldNamePattern = regexp.MustCompile(`^[a-z][a-z0-9_]{0,63}$`)

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
//
// 查询参数：startTime/start_time、endTime/end_time、granularity（raw|hour|day|week|month）、
// page、page_size、sort（asc|desc）、tz、fields（逗号分隔，仅聚合粒度生效）。
// 分页在数据库侧完成，长区间的 total 是真实行数/桶数，不会因为只取一页而丢数据。
func (h *DeviceHandler) GetTelemetry(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	if !isAdmin && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	startTime := firstQueryValue(c, "startTime", "start_time")
	endTime := firstQueryValue(c, "endTime", "end_time")
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

	ctx := c.Request.Context()
	tz := c.Query("tz")
	if tz == "" {
		tz = getUserTimezone(ctx, h.db, userID)
	}
	fields := parseTelemetryFields(c.Query("fields"))
	desc := c.DefaultQuery("sort", "asc") == "desc"

	total, err := h.deviceService.CountTelemetry(ctx, sn, startTime, endTime, granularity, tz)
	if err != nil {
		logger.Error("CountTelemetry failed", zap.String("sn", sn), zap.Error(err))
		response.Error(c, 500, "获取遥测数据失败")
		return
	}

	offset := (page - 1) * pageSizeParam
	if int64(offset) > total {
		offset = int(total)
	}
	pagedData, err := h.deviceService.GetTelemetryPage(ctx, sn, startTime, endTime, granularity, tz,
		desc, offset, pageSizeParam, fields)
	if err != nil {
		logger.Error("GetTelemetryPage failed", zap.String("sn", sn), zap.Error(err))
		response.Error(c, 500, "获取遥测数据失败")
		return
	}

	response.Page(c, pagedData, total, page, pageSizeParam)
}

// firstQueryValue 返回第一个非空的查询参数值，用于兼容 camelCase 与 snake_case 两套命名。
func firstQueryValue(c *gin.Context, keys ...string) string {
	for _, key := range keys {
		if value := c.Query(key); value != "" {
			return value
		}
	}
	return ""
}

// parseTelemetryFields 解析 fields=key1,key2 形式的白名单，非法字段名直接丢弃。
// 字段名会作为 jsonb 取值参数传给数据库，不做字符串拼接，因此这里只做形状校验。
func parseTelemetryFields(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	fields := make([]string, 0, len(parts))
	seen := make(map[string]bool, len(parts))
	for _, part := range parts {
		field := strings.TrimSpace(part)
		if field == "" || seen[field] || !telemetryFieldNamePattern.MatchString(field) {
			continue
		}
		seen[field] = true
		fields = append(fields, field)
	}
	return fields
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
