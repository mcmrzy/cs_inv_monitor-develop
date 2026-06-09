package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
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

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	alarms, total, err := h.alarmService.List(c.Request.Context(), userID, stationID, status, page, pageSize)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	response.Page(c, alarms, total, page, pageSize)
}

func (h *AlarmHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid alarm id")
		return
	}

	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if alarm == nil {
		response.NotFound(c, "alarm not found")
		return
	}

	if alarm.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	response.Success(c, alarm)
}

func (h *AlarmHandler) MarkHandled(c *gin.Context) {
	userID := middleware.GetUserID(c)
	alarmID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid alarm id")
		return
	}

	alarm, err := h.alarmService.GetByID(c.Request.Context(), alarmID)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}

	if alarm == nil {
		response.NotFound(c, "alarm not found")
		return
	}

	if alarm.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	if err := h.alarmService.MarkHandled(c.Request.Context(), alarmID, userID); err != nil {
		response.InternalError(c, "mark handled failed")
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
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.alarmService.MarkRead(c.Request.Context(), req.IDs, userID); err != nil {
		response.InternalError(c, "mark read failed")
		return
	}

	response.SuccessWithMessage(c, "alarms marked as read", nil)
}

func (h *AlarmHandler) GetStats(c *gin.Context) {
	userID := middleware.GetUserID(c)

	stats, err := h.alarmService.GetStats(c.Request.Context(), userID)
	if err != nil {
		response.InternalError(c, "get stats failed")
		return
	}

	response.Success(c, stats)
}
