package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type AlertRuleHandler struct {
	db *pgxpool.Pool
}

type alertRuleRequest struct {
	Name                 string                   `json:"name"`
	Type                 string                   `json:"type"`
	StationID            *int64                   `json:"station_id"`
	DeviceSN             *string                  `json:"device_sn"`
	Description          string                   `json:"description"`
	Severity             string                   `json:"severity"`
	Level                int                      `json:"level"`
	Conditions           []map[string]interface{} `json:"conditions"`
	NotificationChannels []string                 `json:"notification_channels"`
	CooldownMinutes      int                      `json:"cooldown_minutes"`
	Enabled              *bool                    `json:"enabled"`
}

func NewAlertRuleHandler(db *pgxpool.Pool) *AlertRuleHandler {
	return &AlertRuleHandler{db: db}
}

func alertRuleDataScope(alias string, role, userArg int) string {
	userParam := "$" + strconv.Itoa(userArg)
	switch role {
	case service.RoleSuperAdmin:
		return userParam + " = " + userParam
	case service.RoleGeneralAgent, service.RoleAgent, service.RoleDealer:
		return alias + ".created_by IN (SELECT descendant_id FROM v_user_hierarchy WHERE ancestor_id = " + userParam + ")"
	case service.RoleInstaller, service.RoleEndUser:
		return alias + ".created_by = " + userParam
	default:
		return "FALSE"
	}
}

func validateAlertRuleValues(name string, level int, conditions []map[string]interface{}, deviceSN *string, stationID *int64) error {
	if name == "" || len(conditions) == 0 {
		return fmt.Errorf("name and conditions are required")
	}
	if level != 0 && (level < 1 || level > 3) {
		return fmt.Errorf("level must be between 1 and 3")
	}
	if deviceSN != nil && stationID != nil {
		return fmt.Errorf("device_sn and station_id are mutually exclusive")
	}
	return nil
}

func (h *AlertRuleHandler) canTarget(c *gin.Context, deviceSN *string, stationID *int64) (bool, error) {
	if middleware.GetRole(c) == service.RoleSuperAdmin {
		return true, nil
	}
	userID := middleware.GetUserID(c)
	var allowed bool
	switch {
	case deviceSN != nil:
		err := h.db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM v_user_device_access WHERE user_id=$1 AND device_sn=$2)`, userID, *deviceSN).Scan(&allowed)
		return allowed, err
	case stationID != nil:
		err := h.db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM v_user_station_access WHERE user_id=$1 AND station_id=$2)`, userID, *stationID).Scan(&allowed)
		return allowed, err
	default:
		return true, nil
	}
}

func (h *AlertRuleHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, 20)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	scope := alertRuleDataScope("r", role, 1)
	var total int64
	if err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM alert_rules r WHERE `+scope, userID).Scan(&total); err != nil {
		response.Error(c, 500, "list alert rules failed")
		return
	}
	rows, err := h.db.Query(ctx, `
		SELECT to_jsonb(r) || jsonb_build_object('description', COALESCE(r.conditions->0->>'description',''))
		FROM alert_rules r WHERE `+scope+`
		ORDER BY r.updated_at DESC, r.id DESC LIMIT $2 OFFSET $3`, userID, pageSize, (page-1)*pageSize)
	if err != nil {
		response.Error(c, 500, "list alert rules failed")
		return
	}
	defer rows.Close()
	items := make([]map[string]interface{}, 0)
	for rows.Next() {
		var raw []byte
		var item map[string]interface{}
		if err := rows.Scan(&raw); err != nil || json.Unmarshal(raw, &item) != nil {
			response.Error(c, 500, "decode alert rule failed")
			return
		}
		items = append(items, item)
	}
	response.Page(c, items, total, page, pageSize)
}

func (h *AlertRuleHandler) GetByID(c *gin.Context) {
	id, ok := parseRuleID(c)
	if !ok {
		return
	}
	var raw []byte
	err := h.db.QueryRow(c.Request.Context(), `SELECT to_jsonb(r) FROM alert_rules r WHERE id=$1 AND `+alertRuleDataScope("r", middleware.GetRole(c), 2), id, middleware.GetUserID(c)).Scan(&raw)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "alert rule not found")
		return
	}
	if err != nil {
		response.Error(c, 500, "get alert rule failed")
		return
	}
	var item map[string]interface{}
	if err := json.Unmarshal(raw, &item); err != nil {
		response.Error(c, 500, "decode alert rule failed")
		return
	}
	response.Success(c, item)
}

func (h *AlertRuleHandler) Create(c *gin.Context) {
	var req alertRuleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "name and conditions are required")
		return
	}
	if err := validateAlertRuleValues(req.Name, req.Level, req.Conditions, req.DeviceSN, req.StationID); err != nil {
		response.Error(c, 400, err.Error())
		return
	}
	allowed, err := h.canTarget(c, req.DeviceSN, req.StationID)
	if err != nil {
		response.Error(c, 500, "validate alert rule scope failed")
		return
	}
	if !allowed {
		response.Error(c, 403, "alert rule target is outside your scope")
		return
	}
	normalizeAlertRule(&req)
	conditions, _ := json.Marshal(req.Conditions)
	channels, _ := json.Marshal(req.NotificationChannels)
	var id int64
	err = h.db.QueryRow(c.Request.Context(), `
		INSERT INTO alert_rules(name,type,station_id,device_sn,conditions,severity,notification_channels,cooldown_minutes,enabled,created_by,created_at,updated_at)
		VALUES($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,NOW(),NOW()) RETURNING id`,
		req.Name, req.Type, req.StationID, req.DeviceSN, conditions, req.Severity, channels,
		req.CooldownMinutes, *req.Enabled, middleware.GetUserID(c)).Scan(&id)
	if err != nil {
		response.Error(c, 500, "create alert rule failed")
		return
	}
	response.SuccessWithMessage(c, "rule created", gin.H{"id": id})
}

func (h *AlertRuleHandler) Update(c *gin.Context) {
	id, ok := parseRuleID(c)
	if !ok {
		return
	}
	var req alertRuleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}
	if req.DeviceSN != nil && req.StationID != nil {
		response.Error(c, 400, "device_sn and station_id are mutually exclusive")
		return
	}
	allowed, scopeErr := h.canTarget(c, req.DeviceSN, req.StationID)
	if scopeErr != nil {
		response.Error(c, 500, "validate alert rule scope failed")
		return
	}
	if !allowed {
		response.Error(c, 403, "alert rule target is outside your scope")
		return
	}
	normalizeAlertRule(&req)
	conditions, _ := json.Marshal(req.Conditions)
	channels, _ := json.Marshal(req.NotificationChannels)
	result, err := h.db.Exec(c.Request.Context(), `
		UPDATE alert_rules SET
			name=COALESCE(NULLIF($2,''),name), type=COALESCE(NULLIF($3,''),type),
			station_id=COALESCE($4,station_id), device_sn=COALESCE($5,device_sn),
			conditions=CASE WHEN jsonb_array_length($6::jsonb)>0 THEN $6::jsonb ELSE conditions END,
			severity=COALESCE(NULLIF($7,''),severity),
			notification_channels=CASE WHEN jsonb_array_length($8::jsonb)>0 THEN $8::jsonb ELSE notification_channels END,
			cooldown_minutes=CASE WHEN $9>0 THEN $9 ELSE cooldown_minutes END,
			enabled=COALESCE($10,enabled), updated_at=NOW()
		WHERE id=$1 AND `+alertRuleDataScope("alert_rules", middleware.GetRole(c), 11), id, req.Name, req.Type, req.StationID, req.DeviceSN, conditions,
		req.Severity, channels, req.CooldownMinutes, req.Enabled, middleware.GetUserID(c))
	if err != nil {
		response.Error(c, 500, "update alert rule failed")
		return
	}
	if result.RowsAffected() == 0 {
		response.Error(c, 404, "alert rule not found")
		return
	}
	response.SuccessWithMessage(c, "rule updated", gin.H{"id": id})
}

func (h *AlertRuleHandler) Delete(c *gin.Context) {
	id, ok := parseRuleID(c)
	if !ok {
		return
	}
	result, err := h.db.Exec(c.Request.Context(), `DELETE FROM alert_rules WHERE id=$1 AND `+alertRuleDataScope("alert_rules", middleware.GetRole(c), 2), id, middleware.GetUserID(c))
	if err != nil {
		response.Error(c, 500, "delete alert rule failed")
		return
	}
	if result.RowsAffected() == 0 {
		response.Error(c, 404, "alert rule not found")
		return
	}
	response.SuccessWithMessage(c, "rule deleted", gin.H{"id": id})
}

func parseRuleID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "invalid rule id")
		return 0, false
	}
	return id, true
}

func normalizeAlertRule(req *alertRuleRequest) {
	if req.Conditions == nil {
		req.Conditions = []map[string]interface{}{}
	}
	if req.Type == "" {
		req.Type = "telemetry"
	}
	if req.Severity == "" {
		req.Severity = map[int]string{1: "info", 2: "warning", 3: "fault"}[req.Level]
		if req.Severity == "" {
			req.Severity = "warning"
		}
	}
	if req.CooldownMinutes <= 0 {
		req.CooldownMinutes = 5
	}
	if req.Enabled == nil {
		enabled := true
		req.Enabled = &enabled
	}
	if req.NotificationChannels == nil {
		req.NotificationChannels = []string{"app"}
	}
}
