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

// UploadOfflineLogs receives operation logs collected by the App while
// offline (BLE local mode). Deduplication is enforced by the
// (user_id, log_id) unique constraint.
func (h *DeviceHandler) UploadOfflineLogs(c *gin.Context) {
	userID := middleware.GetUserID(c)

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
		// 归一化：缺省 channel 视为 ble、缺省 result 视为 ok
		if req.Logs[i].Channel == "" {
			req.Logs[i].Channel = "ble"
		}
		if req.Logs[i].Result == "" {
			req.Logs[i].Result = "ok"
		}
		if req.Logs[i].Params == nil {
			req.Logs[i].Params = map[string]interface{}{}
		}
		if !validOfflineLog(req.Logs[i]) {
			response.Error(c, 400, "invalid log entry")
			return
		}
	}

	accepted, duplicates, err := h.deviceService.SaveOfflineLogs(c.Request.Context(), userID, req.Logs)
	if err != nil {
		response.Error(c, 500, "save offline logs failed")
		return
	}
	response.Success(c, gin.H{
		"accepted":   accepted,
		"duplicates": duplicates,
	})
}
