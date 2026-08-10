package handler

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NotificationHandler struct {
	db           *pgxpool.Pool
	jpushService *service.JPushService
	notifyPrefs  *repository.NotifyPrefsRepository
}

func NewNotificationHandler(db *pgxpool.Pool, jpushService *service.JPushService, notifyPrefs *repository.NotifyPrefsRepository) *NotificationHandler {
	return &NotificationHandler{db: db, jpushService: jpushService, notifyPrefs: notifyPrefs}
}

func notificationDataScope(alias string, isSystemAdmin bool, userIDArg int) string {
	if isSystemAdmin {
		return "1=1"
	}
	return fmt.Sprintf(`(%[1]s.user_id = $%[2]d OR (
		%[1]s.device_sn <> 'system' AND %[1]s.device_sn IN (
			SELECT device_sn FROM v_user_device_access WHERE user_id = $%[2]d
		)
	))`, alias, userIDArg)
}

// notificationMutationScope is deliberately narrower than the read scope.
// A user may inspect device notifications within their business data scope, but
// deleting a notification is a personal mailbox operation and must not erase a
// notification that belongs to another user who can access the same device.
func notificationMutationScope(alias string, isSystemAdmin bool, userIDArg int) string {
	if isSystemAdmin {
		return "1=1"
	}
	return fmt.Sprintf("%s.user_id = $%d", alias, userIDArg)
}

func (h *NotificationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isSystemAdmin := middleware.GetIsSystemAdmin(c)
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

	var baseQuery string
	var args []interface{}
	argIdx := 1

	if isSystemAdmin {
		baseQuery = `FROM notifications n WHERE 1=1`
	} else {
		baseQuery = `FROM notifications n WHERE ` + notificationDataScope("n", isSystemAdmin, 1)
		args = append(args, userID)
		argIdx = 2
	}

	if notifyType != "" {
		baseQuery += fmt.Sprintf(" AND n.notify_type = $%d", argIdx)
		args = append(args, notifyType)
		argIdx++
	}

	if stationIDStr != "" {
		if stationID, err := strconv.ParseInt(stationIDStr, 10, 64); err == nil && stationID > 0 {
			baseQuery += fmt.Sprintf(" AND n.station_id = $%d", argIdx)
			args = append(args, stationID)
			argIdx++
		}
	}

	if keyword != "" {
		baseQuery += fmt.Sprintf(" AND n.device_sn ILIKE $%d", argIdx)
		args = append(args, "%"+keyword+"%")
		argIdx++
	}

	if startTime != "" {
		baseQuery += fmt.Sprintf(" AND n.created_at >= $%d", argIdx)
		args = append(args, startTime)
		argIdx++
	}

	if endTime != "" {
		baseQuery += fmt.Sprintf(" AND n.created_at <= $%d", argIdx)
		args = append(args, endTime+" 23:59:59")
		argIdx++
	}

	countQuery := `SELECT COUNT(*) ` + baseQuery
	var total int64
	if err := h.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		response.Error(c, 500, "system error")
		return
	}

	offset := (page - 1) * pageSize
	query := `SELECT n.id, n.device_sn, n.station_id, n.user_id, n.notify_type, n.title, n.content, n.status, n.created_at ` +
		baseQuery + ` ORDER BY n.created_at DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.Error(c, 500, "system error")
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
			response.Error(c, 500, "system error")
			return
		}
		n.StationID = stationID
		items = append(items, &n)
	}
	if err := rows.Err(); err != nil {
		response.Error(c, 500, "system error")
		return
	}

	response.Page(c, items, total, page, pageSize)
}

func (h *NotificationHandler) GetStats(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isSystemAdmin := middleware.GetIsSystemAdmin(c)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	query := `SELECT COUNT(*) AS total,
		COUNT(CASE WHEN n.status = 0 THEN 1 END) AS unread
		FROM notifications n WHERE ` + notificationDataScope("n", isSystemAdmin, 1)

	var total, unread int
	if isSystemAdmin {
		if err := h.db.QueryRow(ctx, query).Scan(&total, &unread); err != nil {
			response.Error(c, 500, "system error")
			return
		}
	} else {
		if err := h.db.QueryRow(ctx, query, userID).Scan(&total, &unread); err != nil {
			response.Error(c, 500, "system error")
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
		response.Error(c, 400, "invalid notification id")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	isSystemAdmin := middleware.GetIsSystemAdmin(c)
	var tag interface{ RowsAffected() int64 }
	if isSystemAdmin {
		tag, err = h.db.Exec(ctx, `DELETE FROM notifications WHERE id = $1`, id)
	} else {
		tag, err = h.db.Exec(ctx, `DELETE FROM notifications n WHERE n.id = $1 AND `+
			notificationMutationScope("n", isSystemAdmin, 2), id, middleware.GetUserID(c))
	}
	if err != nil {
		response.Error(c, 500, "delete failed")
		return
	}
	if tag.RowsAffected() != 1 {
		response.Error(c, 403, "notification is outside your data scope")
		return
	}

	response.SuccessWithMessage(c, "notification deleted", nil)
}

func (h *NotificationHandler) ClearAll(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	isSystemAdmin := middleware.GetIsSystemAdmin(c)
	var err error
	if isSystemAdmin {
		_, err = h.db.Exec(ctx, `DELETE FROM notifications`)
	} else {
		_, err = h.db.Exec(ctx, `DELETE FROM notifications n WHERE `+
			notificationMutationScope("n", isSystemAdmin, 1), middleware.GetUserID(c))
	}
	if err != nil {
		response.Error(c, 500, "clear failed")
		return
	}

	response.SuccessWithMessage(c, "all notifications cleared", nil)
}

type pushAnnouncementRequest struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Target  string `json:"target"`
}

// PushAnnouncement 向指定范围用户推送系统公告。
// target 支持："all"、"station_{id}"、"user_{id}"。
func (h *NotificationHandler) PushAnnouncement(c *gin.Context) {
	var req pushAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request body")
		return
	}

	req.Title = strings.TrimSpace(req.Title)
	req.Content = strings.TrimSpace(req.Content)
	if req.Title == "" || req.Content == "" {
		response.Error(c, 400, "title and content are required")
		return
	}
	if len(req.Title) > 200 || len(req.Content) > 10000 {
		response.Error(c, 400, "title or content is too long")
		return
	}
	if strings.TrimSpace(req.Target) == "" {
		response.Error(c, 400, "target is required")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	const notifyType = "system_announcement"
	const deviceSN = "system"
	adminID := middleware.GetUserID(c)
	isSystemAdmin := middleware.GetIsSystemAdmin(c)

	switch {
	case req.Target == "all":
		if !isSystemAdmin {
			response.Error(c, 403, "only super administrators can broadcast to all users")
			return
		}
		if err := h.saveBroadcastAnnouncement(ctx, deviceSN, notifyType, req.Title, req.Content); err != nil {
			response.Error(c, 500, "failed to save announcement")
			return
		}
		// 按用户通知偏好过滤后逐用户推送（notify_system + push_enabled + 勿扰）
		userIDs, err := h.allActiveUserIDs(ctx)
		if err != nil {
			response.Error(c, 500, "failed to query target users")
			return
		}
		if len(userIDs) == 0 {
			response.SuccessWithMessage(c, "announcement pushed", nil)
			return
		}
		jpushIDs, _ := filterPushUsersByPrefs(ctx, h.db, h.notifyPrefs, userIDs, notifyType, 0)
		if len(jpushIDs) > 0 {
			h.jpushService.SendNotificationAsync(ctx, jpushIDs, notifyType, deviceSN, req.Title, req.Content)
		}

	case strings.HasPrefix(req.Target, "station_"):
		stationIDStr := strings.TrimPrefix(req.Target, "station_")
		stationID, err := strconv.ParseInt(stationIDStr, 10, 64)
		if err != nil || stationID <= 0 {
			response.Error(c, 400, "invalid station target")
			return
		}
		if !isSystemAdmin {
			var allowed bool
			err = h.db.QueryRow(ctx, `
				SELECT EXISTS(
					SELECT 1 FROM stations s
					JOIN users actor ON actor.id = $1 AND actor.deleted_at IS NULL
					WHERE s.id = $2 AND s.deleted_at IS NULL
					  AND s.user_id IN (
						SELECT descendant_id FROM v_user_hierarchy WHERE ancestor_id = actor.id
					  )
				)
			`, adminID, stationID).Scan(&allowed)
			if err != nil {
				response.Error(c, 500, "failed to check station scope")
				return
			}
			if !allowed {
				response.Error(c, 403, "station is outside your management scope")
				return
			}
		}

		userIDs, err := h.getUserIDsByStation(ctx, stationID)
		if err != nil {
			response.Error(c, 500, "failed to query station users")
			return
		}
		if len(userIDs) == 0 {
			response.Error(c, 400, "no users found in station")
			return
		}

		if err := h.saveAnnouncements(ctx, deviceSN, &stationID, userIDs, notifyType, req.Title, req.Content); err != nil {
			response.Error(c, 500, "failed to save announcement")
			return
		}
		jpushIDs, _ := filterPushUsersByPrefs(ctx, h.db, h.notifyPrefs, userIDs, notifyType, 0)
		if len(jpushIDs) > 0 {
			h.jpushService.SendNotificationAsync(ctx, jpushIDs, notifyType, deviceSN, req.Title, req.Content)
		}

	case strings.HasPrefix(req.Target, "user_"):
		userIDStr := strings.TrimPrefix(req.Target, "user_")
		userID, err := strconv.ParseInt(userIDStr, 10, 64)
		if err != nil || userID <= 0 {
			response.Error(c, 400, "invalid user target")
			return
		}
		var active bool
		if err = h.db.QueryRow(ctx, `SELECT EXISTS(
			SELECT 1 FROM users WHERE id = $1 AND status = 1 AND deleted_at IS NULL
		)`, userID).Scan(&active); err != nil {
			response.Error(c, 500, "failed to query target user")
			return
		}
		if !active {
			response.Error(c, 400, "target user not found or disabled")
			return
		}
		if !isSystemAdmin {
			var allowed bool
			err = h.db.QueryRow(ctx, `SELECT EXISTS(
				SELECT 1 FROM v_user_hierarchy h
				JOIN users u ON u.id = h.descendant_id AND u.status = 1 AND u.deleted_at IS NULL
				WHERE h.ancestor_id = $1 AND h.descendant_id = $2
			)`, adminID, userID).Scan(&allowed)
			if err != nil {
				response.Error(c, 500, "failed to check user scope")
				return
			}
			if !allowed {
				response.Error(c, 403, "user is outside your management scope")
				return
			}
		}

		if err := h.saveAnnouncement(ctx, deviceSN, nil, userID, notifyType, req.Title, req.Content); err != nil {
			response.Error(c, 500, "failed to save announcement")
			return
		}
		jpushIDs, _ := filterPushUsersByPrefs(ctx, h.db, h.notifyPrefs, []int64{userID}, notifyType, 0)
		if len(jpushIDs) > 0 {
			h.jpushService.SendNotificationAsync(ctx, jpushIDs, notifyType, deviceSN, req.Title, req.Content)
		}

	default:
		response.Error(c, 400, "invalid target")
		return
	}

	response.SuccessWithMessage(c, "announcement pushed", nil)
}

// allActiveUserIDs 查询所有启用且未删除的用户（系统公告广播推送目标）。
func (h *NotificationHandler) allActiveUserIDs(ctx context.Context) ([]int64, error) {
	rows, err := h.db.Query(ctx, `SELECT id FROM users WHERE status = 1 AND deleted_at IS NULL`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var userIDs []int64
	for rows.Next() {
		var uid int64
		if err := rows.Scan(&uid); err != nil {
			return nil, err
		}
		userIDs = append(userIDs, uid)
	}
	return userIDs, rows.Err()
}

func (h *NotificationHandler) getUserIDsByStation(ctx context.Context, stationID int64) ([]int64, error) {
	rows, err := h.db.Query(ctx, `
		SELECT target.user_id
		FROM (
			SELECT s.user_id FROM stations s WHERE s.id = $1 AND s.deleted_at IS NULL
			UNION
			SELECT d.user_id FROM devices d WHERE d.station_id = $1 AND d.deleted_at IS NULL
		) target
		JOIN users u ON u.id = target.user_id AND u.status = 1 AND u.deleted_at IS NULL
	`, stationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var userIDs []int64
	for rows.Next() {
		var uid int64
		if err := rows.Scan(&uid); err != nil {
			return nil, err
		}
		userIDs = append(userIDs, uid)
	}
	return userIDs, rows.Err()
}

func (h *NotificationHandler) saveAnnouncements(
	ctx context.Context,
	deviceSN string,
	stationID *int64,
	userIDs []int64,
	notifyType, title, content string,
) error {
	_, err := h.db.Exec(ctx, `
		INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
		SELECT $1, $2, target.user_id, $4, $5, $6, NOW()
		FROM unnest($3::bigint[]) AS target(user_id)
	`, deviceSN, stationID, userIDs, notifyType, title, content)
	return err
}

func (h *NotificationHandler) saveAnnouncement(
	ctx context.Context,
	deviceSN string,
	stationID *int64,
	userID int64,
	notifyType, title, content string,
) error {
	return h.saveAnnouncements(ctx, deviceSN, stationID, []int64{userID}, notifyType, title, content)
}

func (h *NotificationHandler) saveBroadcastAnnouncement(
	ctx context.Context,
	deviceSN, notifyType, title, content string,
) error {
	_, err := h.db.Exec(ctx, `
		INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
		SELECT $1, NULL, u.id, $2, $3, $4, NOW()
		FROM users u WHERE u.deleted_at IS NULL AND u.status = 1
	`, deviceSN, notifyType, title, content)
	return err
}
