package handler

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NotificationHandler struct {
	db *pgxpool.Pool
}

func NewNotificationHandler(db *pgxpool.Pool) *NotificationHandler {
	return &NotificationHandler{db: db}
}

func (h *NotificationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	notifyType := c.Query("notify_type")
	stationIDStr := c.Query("station_id")
	keyword := c.Query("keyword")
	startTime := c.Query("startTime")
	endTime := c.Query("endTime")

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	isAdmin := role <= 1

	var baseQuery string
	var args []interface{}
	argIdx := 1

	if isAdmin {
		baseQuery = `FROM notifications WHERE 1=1`
	} else {
		baseQuery = `FROM notifications WHERE user_id = $1`
		args = append(args, userID)
		argIdx = 2
	}

	if notifyType != "" {
		baseQuery += fmt.Sprintf(" AND notify_type = $%d", argIdx)
		args = append(args, notifyType)
		argIdx++
	}

	if stationIDStr != "" {
		if stationID, err := strconv.ParseInt(stationIDStr, 10, 64); err == nil && stationID > 0 {
			baseQuery += fmt.Sprintf(" AND station_id = $%d", argIdx)
			args = append(args, stationID)
			argIdx++
		}
	}

	if keyword != "" {
		baseQuery += fmt.Sprintf(" AND device_sn ILIKE $%d", argIdx)
		args = append(args, "%"+keyword+"%")
		argIdx++
	}

	if startTime != "" {
		baseQuery += fmt.Sprintf(" AND created_at >= $%d", argIdx)
		args = append(args, startTime)
		argIdx++
	}

	if endTime != "" {
		baseQuery += fmt.Sprintf(" AND created_at <= $%d", argIdx)
		args = append(args, endTime+" 23:59:59")
		argIdx++
	}

	countQuery := `SELECT COUNT(*) ` + baseQuery
	var total int64
	if err := h.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		response.InternalError(c, "system error")
		return
	}

	offset := (page - 1) * pageSize
	query := `SELECT id, device_sn, station_id, user_id, notify_type, title, content, status, created_at ` +
		baseQuery + ` ORDER BY created_at DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.InternalError(c, "system error")
		return
	}
	defer rows.Close()

	type Notification struct {
		ID         int64     `json:"id"`
		DeviceSN   string    `json:"device_sn"`
		StationID  *int64    `json:"station_id"`
		UserID     int64     `json:"user_id"`
		NotifyType string    `json:"notify_type"`
		Title      string    `json:"title"`
		Content    string    `json:"content"`
		Status     int       `json:"status"`
		CreatedAt  time.Time `json:"created_at"`
	}

	items := make([]*Notification, 0)
	for rows.Next() {
		var n Notification
		var stationID *int64
		if err := rows.Scan(&n.ID, &n.DeviceSN, &stationID, &n.UserID, &n.NotifyType, &n.Title, &n.Content, &n.Status, &n.CreatedAt); err != nil {
			response.InternalError(c, "system error")
			return
		}
		n.StationID = stationID
		items = append(items, &n)
	}

	response.Page(c, items, total, page, pageSize)
}

func (h *NotificationHandler) GetStats(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	isAdmin := role <= 1

	var query string
	if isAdmin {
		query = `
			SELECT COUNT(*) as total,
				   COUNT(CASE WHEN status = 0 THEN 1 END) as unread
			FROM notifications
		`
	} else {
		query = `
			SELECT COUNT(*) as total,
				   COUNT(CASE WHEN status = 0 THEN 1 END) as unread
			FROM notifications WHERE user_id = $1
		`
	}

	var total, unread int
	if isAdmin {
		if err := h.db.QueryRow(ctx, query).Scan(&total, &unread); err != nil {
			response.InternalError(c, "system error")
			return
		}
	} else {
		if err := h.db.QueryRow(ctx, query, userID).Scan(&total, &unread); err != nil {
			response.InternalError(c, "system error")
			return
		}
	}

	response.Success(c, map[string]interface{}{
		"total":  total,
		"unread": unread,
	})
}

func (h *NotificationHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "invalid notification id")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err = h.db.Exec(ctx, `DELETE FROM notifications WHERE id = $1`, id)
	if err != nil {
		response.InternalError(c, "delete failed")
		return
	}

	response.SuccessWithMessage(c, "notification deleted", nil)
}

func (h *NotificationHandler) ClearAll(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err := h.db.Exec(ctx, `DELETE FROM notifications`)
	if err != nil {
		response.InternalError(c, "clear failed")
		return
	}

	response.SuccessWithMessage(c, "all notifications cleared", nil)
}
