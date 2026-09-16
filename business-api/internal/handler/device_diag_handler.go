package handler

import (
	"encoding/json"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// GetDiagnostics 返回设备诊断事件（device_diagnostics，V2.1 文档 14 节）。
// active 优先，按 last_at 倒序；支持 ?status=active|resolved 过滤。
func (h *DeviceHandler) GetDiagnostics(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	if !middleware.GetIsSystemAdmin(c) && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	status := c.DefaultQuery("status", "")
	if status != "" && status != "active" && status != "resolved" {
		response.Error(c, 400, "invalid status")
		return
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT rule_code, level, status, detail, first_at, last_at, count
		FROM device_diagnostics
		WHERE device_sn = $1 AND ($2 = '' OR status = $2)
		ORDER BY (status = 'active') DESC, last_at DESC
		LIMIT 100`, sn, status)
	if err != nil {
		response.Error(c, 500, "query diagnostics failed")
		return
	}
	defer rows.Close()

	type diagEvent struct {
		RuleCode string          `json:"rule_code"`
		Level    string          `json:"level"`
		Status   string          `json:"status"`
		Detail   json.RawMessage `json:"detail"`
		FirstAt  time.Time       `json:"first_at"`
		LastAt   time.Time       `json:"last_at"`
		Count    int             `json:"count"`
	}
	events := make([]diagEvent, 0)
	for rows.Next() {
		var e diagEvent
		if err := rows.Scan(&e.RuleCode, &e.Level, &e.Status, &e.Detail, &e.FirstAt, &e.LastAt, &e.Count); err != nil {
			response.Error(c, 500, "scan diagnostics failed")
			return
		}
		events = append(events, e)
	}
	response.Success(c, events)
}

// GetHealthHistory 返回设备健康度历史（device_health_history，最近 N 条，默认 24）。
func (h *DeviceHandler) GetHealthHistory(c *gin.Context) {
	sn := c.Param("sn")
	userID := middleware.GetUserID(c)
	if !middleware.GetIsSystemAdmin(c) && !h.deviceService.HasPermission(c.Request.Context(), userID, sn) {
		response.Error(c, 403, "permission denied")
		return
	}

	limit := 24
	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 100 {
			limit = n
		}
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT event_time, score, level, factors
		FROM device_health_history
		WHERE device_sn = $1
		ORDER BY event_time DESC
		LIMIT $2`, sn, limit)
	if err != nil {
		response.Error(c, 500, "query health history failed")
		return
	}
	defer rows.Close()

	type healthPoint struct {
		EventTime time.Time       `json:"event_time"`
		Score     float64         `json:"score"`
		Level     string          `json:"level"`
		Factors   json.RawMessage `json:"factors"`
	}
	points := make([]healthPoint, 0)
	for rows.Next() {
		var p healthPoint
		if err := rows.Scan(&p.EventTime, &p.Score, &p.Level, &p.Factors); err != nil {
			response.Error(c, 500, "scan health history failed")
			return
		}
		points = append(points, p)
	}
	response.Success(c, points)
}

// GetConfigSchema 返回该设备型号允许写入的配置参数 schema。
// 元数据来自全局 device_config_schema，可用性由 device_model_commands（按 model_id + is_enabled）裁剪，
// 与 /control 下发校验同源，避免 UI 展示型号不支持的参数（如 set_battery_type）。
func (h *DeviceHandler) GetConfigSchema(c *gin.Context) {
	sn := c.Param("sn")
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT s.param_key, s.group_code, COALESCE(s.sub_group, ''), s.control_type,
		       s.scale, COALESCE(s.unit, ''), s.min, s.max, COALESCE(s.enum_map, '{}'::jsonb),
		       s.step, s.permission_code, COALESCE(s.confirmation_mode, ''),
		       s.display_name_key, s.sort_order, COALESCE(s.visibility, '{}'::jsonb),
		       COALESCE(s.validation, '{}'::jsonb)
		FROM device_config_schema s
		WHERE EXISTS (
			SELECT 1 FROM devices d
			JOIN device_model_commands c ON c.model_id = COALESCE(
				d.model_id,
				(SELECT dm.id FROM device_models dm
				 WHERE dm.model_code = d.model AND dm.lifecycle_status != 'retired' LIMIT 1)
			)
			WHERE d.sn = $1 AND d.deleted_at IS NULL
			  AND c.command_code = s.param_key AND c.is_enabled
		)
		ORDER BY s.group_code, s.sort_order, s.param_key`, sn)
	if err != nil {
		response.Error(c, 500, "query config schema failed")
		return
	}
	defer rows.Close()

	type schemaItem struct {
		ParamKey         string          `json:"param_key"`
		GroupCode        string          `json:"group_code"`
		SubGroup         string          `json:"sub_group"`
		ControlType      string          `json:"control_type"`
		Scale            float64         `json:"scale"`
		Unit             string          `json:"unit"`
		Min              *float64        `json:"min"`
		Max              *float64        `json:"max"`
		EnumMap          json.RawMessage `json:"enum_map"`
		Step             *float64        `json:"step"`
		PermissionCode   string          `json:"permission_code"`
		ConfirmationMode string          `json:"confirmation_mode"`
		DisplayNameKey   string          `json:"display_name_key"`
		SortOrder        int             `json:"sort_order"`
		Visibility       json.RawMessage `json:"visibility"`
		Validation       json.RawMessage `json:"validation"`
	}
	items := make([]schemaItem, 0)
	for rows.Next() {
		var it schemaItem
		if err := rows.Scan(&it.ParamKey, &it.GroupCode, &it.SubGroup, &it.ControlType,
			&it.Scale, &it.Unit, &it.Min, &it.Max, &it.EnumMap,
			&it.Step, &it.PermissionCode, &it.ConfirmationMode,
			&it.DisplayNameKey, &it.SortOrder, &it.Visibility, &it.Validation); err != nil {
			response.Error(c, 500, "scan config schema failed")
			return
		}
		items = append(items, it)
	}
	response.Success(c, items)
}
