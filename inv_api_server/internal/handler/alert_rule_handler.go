package handler

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/apperr"
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
	isAdmin := middleware.GetRole(c) == 0
	var total int64
	if err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM alert_rules WHERE $1 OR created_by=$2`, isAdmin, userID).Scan(&total); err != nil {
		response.HandleError(c, apperr.Internal("list alert rules failed", err))
		return
	}
	rows, err := h.db.Query(ctx, `
		SELECT to_jsonb(r) || jsonb_build_object('description', COALESCE(r.conditions->0->>'description',''))
		FROM alert_rules r WHERE $1 OR r.created_by=$2
		ORDER BY r.updated_at DESC, r.id DESC LIMIT $3 OFFSET $4`, isAdmin, userID, pageSize, (page-1)*pageSize)
	if err != nil {
		response.HandleError(c, apperr.Internal("list alert rules failed", err))
		return
	}
	defer rows.Close()
	items := make([]map[string]interface{}, 0)
	for rows.Next() {
		var raw []byte
		var item map[string]interface{}
		if err := rows.Scan(&raw); err != nil || json.Unmarshal(raw, &item) != nil {
			response.HandleError(c, apperr.Internal("decode alert rule failed", err))
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
	err := h.db.QueryRow(c.Request.Context(), `SELECT to_jsonb(r) FROM alert_rules r WHERE id=$1`, id).Scan(&raw)
	if err == pgx.ErrNoRows {
		response.HandleError(c, apperr.NotFound("alert rule not found"))
		return
	}
	if err != nil {
		response.HandleError(c, apperr.Internal("get alert rule failed", err))
		return
	}
	var item map[string]interface{}
	if err := json.Unmarshal(raw, &item); err != nil {
		response.HandleError(c, apperr.Internal("decode alert rule failed", err))
		return
	}
	response.Success(c, item)
}

func (h *AlertRuleHandler) Create(c *gin.Context) {
	var req alertRuleRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Name == "" || len(req.Conditions) == 0 {
		response.HandleError(c, apperr.BadRequest("name and conditions are required"))
		return
	}
	normalizeAlertRule(&req)
	conditions, _ := json.Marshal(req.Conditions)
	channels, _ := json.Marshal(req.NotificationChannels)
	var id int64
	err := h.db.QueryRow(c.Request.Context(), `
		INSERT INTO alert_rules(name,type,station_id,device_sn,conditions,severity,notification_channels,cooldown_minutes,enabled,created_by,created_at,updated_at)
		VALUES($1,$2,$3,$4,$5::jsonb,$6,$7::jsonb,$8,$9,$10,NOW(),NOW()) RETURNING id`,
		req.Name, req.Type, req.StationID, req.DeviceSN, conditions, req.Severity, channels,
		req.CooldownMinutes, *req.Enabled, middleware.GetUserID(c)).Scan(&id)
	if err != nil {
		response.HandleError(c, apperr.Internal("create alert rule failed", err))
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
		response.HandleError(c, apperr.BadRequest("invalid request"))
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
		WHERE id=$1`, id, req.Name, req.Type, req.StationID, req.DeviceSN, conditions,
		req.Severity, channels, req.CooldownMinutes, req.Enabled)
	if err != nil {
		response.HandleError(c, apperr.Internal("update alert rule failed", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.NotFound("alert rule not found"))
		return
	}
	response.SuccessWithMessage(c, "rule updated", gin.H{"id": id})
}

func (h *AlertRuleHandler) Delete(c *gin.Context) {
	id, ok := parseRuleID(c)
	if !ok {
		return
	}
	result, err := h.db.Exec(c.Request.Context(), `DELETE FROM alert_rules WHERE id=$1`, id)
	if err != nil {
		response.HandleError(c, apperr.Internal("delete alert rule failed", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.NotFound("alert rule not found"))
		return
	}
	response.SuccessWithMessage(c, "rule deleted", gin.H{"id": id})
}

func parseRuleID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid rule id"))
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
