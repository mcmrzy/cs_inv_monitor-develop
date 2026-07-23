package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type AlarmHandler struct {
	alarmService *service.AlarmService
}

func NewAlarmHandler(alarmService *service.AlarmService) *AlarmHandler {
	return &AlarmHandler{alarmService: alarmService}
}

func (h *AlarmHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	stationIDStr := c.Query("station_id")
	statusStr := c.Query("status")
	keyword := c.Query("keyword")
	alarmLevelStr := c.Query("alarmLevel")

	var stationID int64
	if stationIDStr != "" {
		stationID, _ = strconv.ParseInt(stationIDStr, 10, 64)
	}

	var status int = -1
	if statusStr != "" {
		status, _ = strconv.Atoi(statusStr)
	}

	var alarmLevel int
	if alarmLevelStr != "" {
		alarmLevel, _ = strconv.Atoi(alarmLevelStr)
	}

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	params := repository.AlarmListParams{
		UserID:     userID,
		StationID:  stationID,
		Status:     status,
		AlarmLevel: alarmLevel,
		Keyword:    keyword,
		Page:       page,
		PageSize:   pageSize,
		Role:       role,
	}

	alarms, total, err := h.alarmService.List(c.Request.Context(), params)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	response.Page(c, alarms, total, page, pageSize)
}

func (h *AlarmHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid alarm id")
		return
	}

	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if alarm == nil {
		response.Error(c, 404, "alarm not found")
		return
	}

	// 管理员可以查看任何告警，普通用户只能查看自己的
	if role > 1 && alarm.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	response.Success(c, alarm)
}

func (h *AlarmHandler) MarkHandled(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid alarm id")
		return
	}

	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}

	if alarm == nil {
		response.Error(c, 404, "alarm not found")
		return
	}

	// 管理员可以处理任何告警，普通用户只能处理自己的
	if role > 1 && alarm.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	if err := h.alarmService.MarkHandled(c.Request.Context(), alarmID, userID); err != nil {
		response.Error(c, 500, "mark handled failed")
		return
	}

	response.SuccessWithMessage(c, "alarm handled", nil)
}

func (h *AlarmHandler) MarkRead(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		IDs []int64 `json:"ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if err := h.alarmService.MarkRead(c.Request.Context(), req.IDs, userID); err != nil {
		response.Error(c, 500, "mark read failed")
		return
	}

	response.SuccessWithMessage(c, "alarms marked as read", nil)
}

func (h *AlarmHandler) GetStats(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	stats, err := h.alarmService.GetStats(c.Request.Context(), userID, role)
	if err != nil {
		response.Error(c, 500, "get stats failed")
		return
	}

	response.Success(c, stats)
}

// Acknowledge 处理告警（前端 POST /alerts/:id/acknowledge 映射到此）
func (h *AlarmHandler) Acknowledge(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid alarm id")
		return
	}

	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if alarm == nil {
		response.Error(c, 404, "alarm not found")
		return
	}
	if role > 1 && alarm.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	if err := h.alarmService.MarkHandled(c.Request.Context(), alarmID, userID); err != nil {
		response.Error(c, 500, "mark handled failed")
		return
	}

	response.SuccessWithMessage(c, "alarm handled", nil)
}

// Ignore 忽略告警（前端 POST /alerts/:id/ignore 映射到此）
func (h *AlarmHandler) Ignore(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid alarm id")
		return
	}

	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if alarm == nil {
		response.Error(c, 404, "alarm not found")
		return
	}
	if role > 1 && alarm.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	if err := h.alarmService.MarkIgnored(c.Request.Context(), alarmID); err != nil {
		response.Error(c, 500, "mark ignored failed")
		return
	}

	response.SuccessWithMessage(c, "alarm ignored", nil)
}

func (h *AlarmHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid alarm id")
		return
	}

	// Ownership check: non-admin users can only delete their own alarms
	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	if alarm == nil {
		response.Error(c, 404, "alarm not found")
		return
	}
	if role > 1 && alarm.UserID != userID {
		response.Error(c, 403, "permission denied")
		return
	}

	if err := h.alarmService.Delete(c.Request.Context(), alarmID); err != nil {
		response.Error(c, 500, "delete failed")
		return
	}

	response.SuccessWithMessage(c, "alarm deleted", nil)
}

func (h *AlarmHandler) ClearAll(c *gin.Context) {
	// Only admin can clear all alarms
	if middleware.GetRole(c) != 0 {
		response.Error(c, 403, "admin only")
		return
	}

	if err := h.alarmService.ClearAll(c.Request.Context()); err != nil {
		response.Error(c, 500, "clear failed")
		return
	}

	response.SuccessWithMessage(c, "all alarms cleared", nil)
}
