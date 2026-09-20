package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// 调试采样 SSE 的推送节奏：固件采样周期 5s，2s 取一次增量保证「点一到就画」；
// 心跳 15s 防止反代/浏览器把空闲连接掐掉；无新点时最多 10s 补推一次会话状态。
const (
	debugStreamPollInterval      = 2 * time.Second
	debugStreamHeartbeatInterval = 15 * time.Second
	debugStreamEnvelopeInterval  = 10 * time.Second
	debugStreamSampleLimit       = 200
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

// debugSessionSignature 把「会话是否变化」压缩成可比字符串：状态/最后采样时间一变就重推。
func debugSessionSignature(sess *model.DeviceDebugSession) string {
	if sess == nil {
		return "none"
	}
	last := ""
	if sess.LastSampleAt != nil {
		last = sess.LastSampleAt.UTC().Format(time.RFC3339)
	}
	return fmt.Sprintf("%d|%s|%s", sess.ID, sess.Status, last)
}

// StreamSamples GET /devices/by-sn/:sn/debug-stream（SSE）
//
// 与 GetSamples 同源同鉴权（服务层 authorize 仍按设备数据归属校验），区别是把
// 「前端每 10s 轮询」换成服务端推送：
//   - 首帧 snapshot：设备在线状态 + 当前会话 + 时间窗内已有采样，前端立即出图；
//   - 每 2s 取一次增量（after=游标），有新采样点立刻推 samples 事件（含会话）；
//   - 无新点时，会话状态变化或每 10s 补推一次 session 事件（含 device_online），
//     前端因此不再需要轮询会话与采样；
//   - 会话结束不关闭连接（EventSource 会在连接关闭后自动重连，主动关闭会造成重连风暴），
//     新会话开始时会自动切换会话并重置游标，前端据 session.id 变化清空本地累积点。
func (h *DeviceDebugHandler) StreamSamples(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetIsSystemAdmin(c)
	ctx := c.Request.Context()

	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	// 关掉反代缓冲：否则事件会被攒着批量下发，实时性归零
	c.Header("X-Accel-Buffering", "no")

	flusher, ok := c.Writer.(http.Flusher)
	if !ok {
		response.Error(c, http.StatusInternalServerError, "streaming unsupported")
		return
	}

	windowMinutes, _ := strconv.Atoi(c.DefaultQuery("window_minutes", "60"))
	currentSessionID, _ := strconv.ParseInt(c.Query("session_id"), 10, 64)

	writeEvent := func(event string, payload interface{}) bool {
		raw, err := json.Marshal(payload)
		if err != nil {
			return false
		}
		if _, err := fmt.Fprintf(c.Writer, "event: %s\ndata: %s\n\n", event, raw); err != nil {
			return false
		}
		flusher.Flush()
		return true
	}

	// 首帧：设备在线状态 + 会话 + 时间窗内已有采样，省掉前端首屏的那次全量拉取。
	sess, online, err := h.debugService.GetSession(ctx, userID, isAdmin, sn)
	if err != nil {
		// 鉴权失败/设备不存在都走这里：推一帧错误后收尾，避免前端无提示地空转
		writeEvent("stream_error", gin.H{"message": "debug session unavailable"})
		return
	}
	if sess != nil {
		currentSessionID = sess.ID
	}
	items, nextCursor, _, err := h.debugService.GetSamples(ctx, userID, isAdmin, sn, currentSessionID, windowMinutes, "", debugStreamSampleLimit)
	if err != nil {
		writeEvent("stream_error", gin.H{"message": "debug samples unavailable"})
		return
	}
	if !writeEvent("snapshot", gin.H{
		"session":       sess,
		"device_online": online,
		"supported":     true,
		"items":         items,
		"next_cursor":   nextCursor,
	}) {
		return
	}

	cursor := nextCursor
	lastSignature := debugSessionSignature(sess)
	lastEnvelope := time.Now()

	sampleTicker := time.NewTicker(debugStreamPollInterval)
	defer sampleTicker.Stop()
	heartbeatTicker := time.NewTicker(debugStreamHeartbeatInterval)
	defer heartbeatTicker.Stop()

	for {
		select {
		case <-ctx.Done():
			// 客户端断开（切 Tab/关页面）：直接收尾，不做任何清理动作
			return
		case <-heartbeatTicker.C:
			if _, err := fmt.Fprint(c.Writer, ": ping\n\n"); err != nil {
				return
			}
			flusher.Flush()
		case <-sampleTicker.C:
			items, nextCursor, sess, err := h.debugService.GetSamples(
				ctx, userID, isAdmin, sn, currentSessionID, windowMinutes, cursor, debugStreamSampleLimit)
			if err != nil {
				writeEvent("stream_error", gin.H{"message": "debug samples unavailable"})
				return
			}
			if sess != nil && sess.ID != currentSessionID {
				// 换了会话（上一次已结束、又开了新的一次）：游标失效，下一轮重拉整个时间窗
				currentSessionID = sess.ID
				cursor = ""
			} else if sess == nil {
				currentSessionID = 0
			}
			if nextCursor != "" {
				cursor = nextCursor
			}

			signature := debugSessionSignature(sess)
			if len(items) > 0 {
				if !writeEvent("samples", gin.H{"items": items, "next_cursor": cursor, "session": sess}) {
					return
				}
				lastSignature, lastEnvelope = signature, time.Now()
				continue
			}
			if signature != lastSignature || time.Since(lastEnvelope) >= debugStreamEnvelopeInterval {
				_, online, envelopeErr := h.debugService.GetSession(ctx, userID, isAdmin, sn)
				if envelopeErr != nil {
					writeEvent("stream_error", gin.H{"message": "debug session unavailable"})
					return
				}
				if !writeEvent("session", gin.H{"session": sess, "device_online": online, "supported": true}) {
					return
				}
				lastSignature, lastEnvelope = signature, time.Now()
			}
		}
	}
}
