package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// DeviceDebugHandler 单设备调试模式：会话查询/开启/关闭 + 有界曲线样本。
type DeviceDebugHandler struct {
	debugService *service.DeviceDebugService
}

func NewDeviceDebugHandler(debugService *service.DeviceDebugService) *DeviceDebugHandler {
	return &DeviceDebugHandler{debugService: debugService}
}

// GetSession GET /devices/by-sn/:sn/debug-session
func (h *DeviceDebugHandler) GetSession(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	sess, online, err := h.debugService.GetSession(c.Request.Context(), userID, isAdmin, sn)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, gin.H{
		"session":       sess, // 无会话时为 null
		"device_online": online,
		"supported":     true,
		"interval_seconds": service.DebugIntervalSeconds,
	})
}

type startDebugSessionRequest struct {
	DurationSeconds int    `json:"duration_seconds"`
	RequestID       string `json:"request_id"`
	Source          string `json:"source"`
}

// StartSession POST /devices/by-sn/:sn/debug-session（路由层已挂 devices:control）
func (h *DeviceDebugHandler) StartSession(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	var req startDebugSessionRequest
	// 空请求体（App 极简调用）允许：全部走默认值
	_ = c.ShouldBindJSON(&req)
	if req.Source == "" {
		req.Source = "web"
	}

	sess, conflict, err := h.debugService.StartSession(c.Request.Context(), userID, isAdmin, sn, req.DurationSeconds, req.RequestID, req.Source)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	msg := "debug session started"
	if conflict {
		msg = "device already has an active debug session"
	}
	response.SuccessWithMessage(c, msg, gin.H{"session": sess, "conflict": conflict})
}

// StopSession DELETE /devices/by-sn/:sn/debug-session/:id
func (h *DeviceDebugHandler) StopSession(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	sessionID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || sessionID <= 0 {
		response.Error(c, 400, "invalid session id")
		return
	}

	sess, err := h.debugService.StopSession(c.Request.Context(), userID, isAdmin, sn, sessionID)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.SuccessWithMessage(c, "debug session stopping", gin.H{"session": sess})
}

// GetSamples GET /devices/by-sn/:sn/debug-samples
func (h *DeviceDebugHandler) GetSamples(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)

	sessionID, _ := strconv.ParseInt(c.Query("session_id"), 10, 64)
	windowMinutes, _ := strconv.Atoi(c.DefaultQuery("window_minutes", "60"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "200"))
	after := c.Query("after")

	items, nextCursor, sess, err := h.debugService.GetSamples(c.Request.Context(), userID, isAdmin, sn, sessionID, windowMinutes, after, limit)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	if items == nil {
		// Go nil slice 会序列化成 JSON null，打爆前端 expectedDataShape 校验
		items = []model.DebugSamplePoint{}
	}
	response.Success(c, gin.H{
		"items":       items,
		"next_cursor": nextCursor,
		"session":     sess,
	})
}
