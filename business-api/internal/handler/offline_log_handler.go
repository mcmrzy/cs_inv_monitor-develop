package handler

import (
	"regexp"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// maxOfflineLogsPerBatch caps a single upload request (design doc §4.3).
const maxOfflineLogsPerBatch = 50

var offlineLogIDRegex = regexp.MustCompile(`^[0-9a-fA-F-]{8,64}$`)

// offlineActionWhitelist mirrors the App's local op log actions
// (design doc §3.5): bind/unbind, control commands, set_param, ota.
// control/param_update 为 App 本地直连（WiFi AP）链路的通用动作名，
// 携带具体命令/参数在 params 字段。
var offlineActionWhitelist = map[string]bool{
	"bind": true, "unbind": true, "power_on": true, "power_off": true,
	"set_power": true, "set_param": true, "ota": true,
	"control": true, "param_update": true,
}

// validOfflineLog validates a single offline log entry.
func validOfflineLog(log model.OfflineOpLog) bool {
	if !offlineLogIDRegex.MatchString(log.LogID) {
		return false
	}
	if log.DeviceSN == "" || len(log.DeviceSN) > 50 {
		return false
	}
	if !offlineActionWhitelist[log.Action] {
		return false
	}
	switch log.Channel {
	case "", "cloud", "ble", "wifi_ap":
	default:
		return false
	}
	if log.OpTime.IsZero() {
		return false
	}
	return true
}

func normalizeOfflineLog(log *model.OfflineOpLog) {
	if log.Channel == "" {
		log.Channel = "ble"
	}
	if log.Result == "" {
		log.Result = "unknown"
	}
	if log.Params == nil {
		log.Params = map[string]interface{}{}
	}
}

// UploadOfflineLogs receives operation logs collected by the App while
// offline (BLE local mode). Authorization is checked per device before
// insertion; the existing (user_id, log_id) unique constraint deduplicates
// authorized records.
func (h *DeviceHandler) UploadOfflineLogs(c *gin.Context) {
	actor := middleware.GetActorContext(c)
	if actor.UserID == 0 {
		// Handler tests and older internal callers may carry only user_id. The
		// JWT middleware normally provides the full actor context.
		actor.UserID = middleware.GetUserID(c)
	}

	var req struct {
		Logs []model.OfflineOpLog `json:"logs"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}
	if len(req.Logs) == 0 || len(req.Logs) > maxOfflineLogsPerBatch {
		response.Error(c, 400, "logs count must be between 1 and 50")
		return
	}
	for i := range req.Logs {
		// 归一化：缺省 channel 视为 ble；结果未知不得伪装成成功。
		normalizeOfflineLog(&req.Logs[i])
		if !validOfflineLog(req.Logs[i]) {
			response.Error(c, 400, "invalid log entry")
			return
		}
	}

	if h.deviceService == nil {
		response.Error(c, 500, "offline log service unavailable")
		return
	}
	result, err := h.deviceService.SaveOfflineLogs(c.Request.Context(), actor, req.Logs)
	if err != nil {
		response.Error(c, 500, "save offline logs failed")
		return
	}
	response.Success(c, result)
}
