package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"time"

	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

var serverStartTime = time.Now()

type AdminHandler struct {
	userRepo    *repository.UserRepository
	modelRepo   *repository.ModelRepository
	permChecker *service.PermChecker
	db          *pgxpool.Pool
	rdb         *redis.Client
}

func NewAdminHandler(userRepo *repository.UserRepository, modelRepo *repository.ModelRepository, permChecker *service.PermChecker, db *pgxpool.Pool, rdb *redis.Client) *AdminHandler {
	return &AdminHandler{
		userRepo:    userRepo,
		modelRepo:   modelRepo,
		permChecker: permChecker,
		db:          db,
		rdb:         rdb,
	}
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "pageSize", 10)
	keyword := c.Query("keyword")
	role := getQueryInt(c, "role", -1)
	status := getQueryInt(c, "status", -1)

	result, err := h.userRepo.List(c.Request.Context(), repository.ListUsersParams{
		Page:     page,
		PageSize: pageSize,
		Keyword:  keyword,
		Role:     role,
		Status:   status,
	})
	if err != nil {
		response.InternalError(c, "查询用户列表失败")
		return
	}

	response.Success(c, gin.H{
		"items": result.Items,
		"total": result.Total,
	})
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.BadRequest(c, "invalid user id")
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.NotFound(c, "用户不存在")
		return
	}
	user.PasswordHash = ""
	response.Success(c, user)
}

type UpdateUserRoleRequest struct {
	Role int `json:"role" binding:"required"`
}

func (h *AdminHandler) UpdateUserRole(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.BadRequest(c, "invalid user id")
		return
	}

	var req UpdateUserRoleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.userRepo.UpdateRole(c.Request.Context(), userID, req.Role); err != nil {
		response.InternalError(c, "更新角色失败")
		return
	}

	go h.permChecker.InvalidateUser(userID)
	response.SuccessWithMessage(c, "角色更新成功", nil)
}

type UpdatePermissionRequest struct {
	Role      int    `json:"role" binding:"required"`
	Resource  string `json:"resource" binding:"required"`
	Action    string `json:"action" binding:"required"`
	IsAllowed bool   `json:"is_allowed"`
}

func (h *AdminHandler) UpdatePermission(c *gin.Context) {
	var req UpdatePermissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.userRepo.UpsertPermission(c.Request.Context(), req.Role, req.Resource, req.Action, req.IsAllowed); err != nil {
		response.InternalError(c, "更新权限失败")
		return
	}

	go h.permChecker.InvalidateRole(int64(req.Role))
	response.SuccessWithMessage(c, "权限更新成功", nil)
}

func (h *AdminHandler) ListRolePermissions(c *gin.Context) {
	roleParam := c.Param("role")
	if roleParam == "" {
		roleParam = c.Query("role")
	}
	if roleParam == "" {
		response.BadRequest(c, "缺少 role 参数")
		return
	}
	role := parseID(roleParam)
	if role < 0 {
		response.BadRequest(c, "invalid role")
		return
	}

	ctx := c.Request.Context()

	type permRow struct {
		Resource  string `json:"resource"`
		Action    string `json:"action"`
		IsAllowed bool   `json:"is_allowed"`
	}

	rows, err := h.db.Query(ctx, `
		SELECT resource, action, is_allowed
		FROM role_permissions
		WHERE role = $1
		ORDER BY resource, action
	`, role)
	if err != nil {
		rows, err = h.db.Query(ctx, `
			SELECT COALESCE(p.resource,''), COALESCE(p.action,''), COALESCE(rp.is_allowed, false)
			FROM admin_permissions p
			LEFT JOIN role_permissions rp ON rp.role = $1 AND rp.resource = p.resource AND rp.action = p.action
			ORDER BY p.resource, p.action
		`, role)
		if err != nil {
			response.InternalError(c, "查询权限失败")
			return
		}
	}
	defer rows.Close()

	var perms []permRow
	for rows.Next() {
		var p permRow
		if err := rows.Scan(&p.Resource, &p.Action, &p.IsAllowed); err != nil {
			continue
		}
		perms = append(perms, p)
	}
	if perms == nil {
		perms = []permRow{}
	}

	response.Success(c, perms)
}

type UpdateRolePermissionsRequest struct {
	Permissions []struct {
		Resource  string `json:"resource"`
		Action    string `json:"action"`
		IsAllowed bool   `json:"is_allowed"`
	} `json:"permissions"`
}

func (h *AdminHandler) UpdateRolePermissions(c *gin.Context) {
	roleParam := c.Param("role")
	role := parseID(roleParam)
	if role < 0 {
		response.BadRequest(c, "invalid role")
		return
	}

	var req UpdateRolePermissionsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.InternalError(c, "事务开启失败")
		return
	}
	defer tx.Rollback(ctx)

	for _, p := range req.Permissions {
		_, err := tx.Exec(ctx, `
			INSERT INTO role_permissions (role, resource, action, is_allowed, updated_at)
			VALUES ($1, $2, $3, $4, NOW())
			ON CONFLICT (role, resource, action) DO UPDATE SET is_allowed = $4, updated_at = NOW()
		`, role, p.Resource, p.Action, p.IsAllowed)
		if err != nil {
			response.InternalError(c, "更新权限失败")
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.InternalError(c, "提交事务失败")
		return
	}

	go h.permChecker.InvalidateRole(role)
	response.SuccessWithMessage(c, "权限配置保存成功", nil)
}

type TogglePermissionRequest struct {
	Resource string `json:"resource" binding:"required"`
	Action   string `json:"action" binding:"required"`
}

func (h *AdminHandler) TogglePermission(c *gin.Context) {
	roleParam := c.Param("role")
	role := parseID(roleParam)
	if role < 0 {
		response.BadRequest(c, "invalid role")
		return
	}

	var req TogglePermissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	ctx := c.Request.Context()

	var current bool
	err := h.db.QueryRow(ctx,
		`SELECT COALESCE(is_allowed, false) FROM role_permissions WHERE role=$1 AND resource=$2 AND action=$3`,
		role, req.Resource, req.Action,
	).Scan(&current)
	if err != nil && err != pgx.ErrNoRows {
		response.InternalError(c, "查询权限失败")
		return
	}

	newVal := !current
	if err := h.userRepo.UpsertPermission(ctx, int(role), req.Resource, req.Action, newVal); err != nil {
		response.InternalError(c, "更新权限失败")
		return
	}

	go h.permChecker.InvalidateRole(role)
	response.Success(c, gin.H{"is_allowed": newVal})
}

func (h *AdminHandler) ToggleUserStatus(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.BadRequest(c, "invalid user id")
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.NotFound(c, "用户不存在")
		return
	}

	newStatus := 0
	if user.Status != 1 {
		newStatus = 1
	}

	if err := h.userRepo.UpdateStatus(c.Request.Context(), userID, newStatus); err != nil {
		response.InternalError(c, "更新用户状态失败")
		return
	}
	response.SuccessWithMessage(c, "用户状态已更新", nil)
}

func (h *AdminHandler) ListAllModels(c *gin.Context) {
	models, err := h.modelRepo.ListAllWithDeviceCount(c.Request.Context())
	if err != nil {
		response.InternalError(c, "查询型号列表失败")
		return
	}
	response.Success(c, models)
}

func (h *AdminHandler) GetAuditLogs(c *gin.Context) {
	ctx := c.Request.Context()
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "pageSize", 10)
	if pageSize > 100 {
		pageSize = 100
	}
	offset := (page - 1) * pageSize

	userID := c.Query("userId")
	action := c.Query("action")
	startDate := c.Query("startDate")
	endDate := c.Query("endDate")

	where := "WHERE 1=1"
	args := []interface{}{}
	argIdx := 1

	if userID != "" {
		where += fmt.Sprintf(" AND operator_name ILIKE $%d", argIdx)
		args = append(args, "%"+userID+"%")
		argIdx++
	}
	if action != "" {
		where += fmt.Sprintf(" AND action = $%d", argIdx)
		args = append(args, action)
		argIdx++
	}
	if startDate != "" {
		where += fmt.Sprintf(" AND created_at >= $%d", argIdx)
		args = append(args, startDate+" 00:00:00")
		argIdx++
	}
	if endDate != "" {
		where += fmt.Sprintf(" AND created_at <= $%d", argIdx)
		args = append(args, endDate+" 23:59:59")
		argIdx++
	}

	var total int64
	countQuery := "SELECT COUNT(*) FROM audit_logs " + where
	countArgs := make([]interface{}, len(args))
	copy(countArgs, args)
	if err := h.db.QueryRow(ctx, countQuery, countArgs...).Scan(&total); err != nil {
		response.InternalError(c, "查询审计日志失败")
		return
	}

	query := fmt.Sprintf(`
		SELECT id, COALESCE(operator_id, 0), COALESCE(operator_name,''), COALESCE(action,''),
		       COALESCE(resource_type,''), COALESCE(resource_id::text,''), COALESCE(detail,'{}'),
		       COALESCE(ip,''), created_at
		FROM audit_logs %s
		ORDER BY created_at DESC
		LIMIT $%d OFFSET $%d
	`, where, argIdx, argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.InternalError(c, "查询审计日志失败")
		return
	}
	defer rows.Close()

	type auditLogItem struct {
		ID         int64           `json:"id"`
		UserID     int64           `json:"userId"`
		Username   string          `json:"username"`
		Action     string          `json:"action"`
		Resource   string          `json:"resourceType"`
		ResourceID string          `json:"resourceId"`
		Detail     json.RawMessage `json:"detail"`
		IPAddress  string          `json:"ip"`
		Timestamp  time.Time       `json:"timestamp"`
	}

	var items []auditLogItem
	for rows.Next() {
		var item auditLogItem
		var details json.RawMessage
		if err := rows.Scan(&item.ID, &item.UserID, &item.Username, &item.Action,
			&item.Resource, &item.ResourceID, &details, &item.IPAddress, &item.Timestamp); err != nil {
			continue
		}
		item.Detail = details
		items = append(items, item)
	}
	if items == nil {
		items = []auditLogItem{}
	}

	response.Success(c, gin.H{
		"items": items,
		"total": total,
	})
}

func (h *AdminHandler) ExportAuditLogs(c *gin.Context) {
	ctx := c.Request.Context()
	startDate := c.Query("startDate")
	endDate := c.Query("endDate")

	where := "WHERE 1=1"
	args := []interface{}{}
	argIdx := 1

	if startDate != "" {
		where += fmt.Sprintf(" AND created_at >= $%d", argIdx)
		args = append(args, startDate+" 00:00:00")
		argIdx++
	}
	if endDate != "" {
		where += fmt.Sprintf(" AND created_at <= $%d", argIdx)
		args = append(args, endDate+" 23:59:59")
		argIdx++
	}

	query := fmt.Sprintf(`
		SELECT id, COALESCE(operator_id,0), COALESCE(operator_name,''), COALESCE(action,''),
		       COALESCE(resource_type,''), COALESCE(resource_id::text,''), COALESCE(ip,''), created_at
		FROM audit_logs %s ORDER BY created_at DESC
	`, where)

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.InternalError(c, "导出审计日志失败")
		return
	}
	defer rows.Close()

	csvContent := "ID,用户ID,用户名,操作,资源类型,资源ID,IP地址,时间\n"
	for rows.Next() {
		var id, userID int64
		var username, action, resource, resourceID, ip string
		var createdAt time.Time
		if err := rows.Scan(&id, &userID, &username, &action, &resource, &resourceID, &ip, &createdAt); err != nil {
			continue
		}
		csvContent += fmt.Sprintf("%d,%d,%s,%s,%s,%s,%s,%s\n",
			id, userID, username, action, resource, resourceID, ip, createdAt.Format("2006-01-02 15:04:05"))
	}

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", "attachment; filename=audit_logs.csv")
	c.String(http.StatusOK, csvContent)
}

func (h *AdminHandler) GetSystemHealth(c *gin.Context) {
	ctx := c.Request.Context()

	uptime := time.Since(serverStartTime).Seconds()

	dbOK := false
	if h.db != nil {
		pingCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		dbOK = h.db.Ping(pingCtx) == nil
	}

	redisOK := false
	if h.rdb != nil {
		pingCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		defer cancel()
		redisOK = h.rdb.Ping(pingCtx).Err() == nil
	}

	mqttOK := false
	if h.rdb != nil {
		val, err := h.rdb.Get(ctx, "mqtt:broker:health").Result()
		mqttOK = err == nil && val == "ok"
	}

	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)
	memUsage := float64(memStats.Alloc) / float64(memStats.Sys) * 100
	if memStats.Sys == 0 {
		memUsage = 0
	}

	response.Success(c, gin.H{
		"uptime":      int64(uptime),
		"memoryUsage": memUsage,
		"cpuUsage":    0.0,
		"database":    dbOK,
		"redis":       redisOK,
		"mqtt":        mqttOK,
		"version":     "1.0.0",
		"lastCheckAt": time.Now().Format(time.RFC3339),
	})
}

func (h *AdminHandler) GetSystemConfig(c *gin.Context) {
	ctx := c.Request.Context()

	rows, err := h.db.Query(ctx, `SELECT config_key, config_value FROM system_configs`)
	if err != nil {
		rows, err = h.db.Query(ctx, `SELECT config_key, config_value FROM system_config`)
		if err != nil {
			response.Success(c, map[string]interface{}{})
			return
		}
	}
	defer rows.Close()

	config := make(map[string]interface{})
	for rows.Next() {
		var key, value string
		if err := rows.Scan(&key, &value); err != nil {
			continue
		}
		var v interface{}
		if json.Unmarshal([]byte(value), &v) == nil {
			config[key] = v
		} else {
			config[key] = value
		}
	}

	response.Success(c, config)
}

func (h *AdminHandler) UpdateSystemConfig(c *gin.Context) {
	ctx := c.Request.Context()

	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.InternalError(c, "事务开启失败")
		return
	}
	defer tx.Rollback(ctx)

	for key, val := range body {
		valueBytes, _ := json.Marshal(val)
		_, err := tx.Exec(ctx, `
			INSERT INTO system_configs (config_key, config_value, updated_at)
			VALUES ($1, $2, NOW())
			ON CONFLICT (config_key) DO UPDATE SET config_value = $2, updated_at = NOW()
		`, key, string(valueBytes))
		if err != nil {
			response.InternalError(c, "保存配置失败: "+key)
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.InternalError(c, "提交事务失败")
		return
	}

	response.SuccessWithMessage(c, "配置保存成功", nil)
}

func (h *AdminHandler) ListTenants(c *gin.Context) {
	ctx := c.Request.Context()
	page := getQueryInt(c, "page", 1)
	pageSize := getQueryInt(c, "pageSize", 10)
	offset := (page - 1) * pageSize

	var total int64
	err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE role = 1 AND deleted_at IS NULL`).Scan(&total)
	if err != nil {
		response.InternalError(c, "查询租户列表失败")
		return
	}

	rows, err := h.db.Query(ctx, `
		SELECT u.id, u.phone, COALESCE(u.nickname,''), COALESCE(u.email,''), u.status,
		       COALESCE(u.created_at, NOW()), COALESCE(u.last_login_at, u.created_at)
		FROM users u
		WHERE u.role = 1 AND u.deleted_at IS NULL
		ORDER BY u.id DESC
		LIMIT $1 OFFSET $2
	`, pageSize, offset)
	if err != nil {
		response.InternalError(c, "查询租户列表失败")
		return
	}
	defer rows.Close()

	type tenantItem struct {
		ID           int64      `json:"id"`
		Phone        string     `json:"phone"`
		Nickname     string     `json:"nickname"`
		Email        string     `json:"email"`
		Status       int        `json:"status"`
		SubUserCount int        `json:"subUserCount"`
		DeviceCount  int        `json:"deviceCount"`
		DeviceLimit  *int       `json:"deviceLimit"`
		UserLimit    *int       `json:"userLimit"`
		CreatedAt    time.Time  `json:"createdAt"`
		LastLoginAt  *time.Time `json:"lastLoginAt"`
	}

	var items []tenantItem
	for rows.Next() {
		var t tenantItem
		var lastLoginAt *time.Time
		if err := rows.Scan(&t.ID, &t.Phone, &t.Nickname, &t.Email, &t.Status, &t.CreatedAt, &lastLoginAt); err != nil {
			continue
		}
		t.LastLoginAt = lastLoginAt

		h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE parent_id = $1 AND deleted_at IS NULL`, t.ID).Scan(&t.SubUserCount)
		h.db.QueryRow(ctx, `SELECT COUNT(*) FROM devices WHERE user_id = $1 AND deleted_at IS NULL`, t.ID).Scan(&t.DeviceCount)

		items = append(items, t)
	}
	if items == nil {
		items = []tenantItem{}
	}

	response.Success(c, gin.H{
		"items": items,
		"total": total,
	})
}

type CreateTenantRequest struct {
	Phone       string `json:"phone" binding:"required"`
	Nickname    string `json:"nickname"`
	Email       string `json:"email"`
	Password    string `json:"password" binding:"required"`
	DeviceLimit *int   `json:"deviceLimit"`
	UserLimit   *int   `json:"userLimit"`
}

func (h *AdminHandler) CreateTenant(c *gin.Context) {
	var req CreateTenantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	ctx := c.Request.Context()

	var exists int
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE phone = $1 AND deleted_at IS NULL`, req.Phone).Scan(&exists)
	if exists > 0 {
		response.BadRequest(c, "该手机号已注册")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.InternalError(c, "密码加密失败")
		return
	}

	nickname := req.Nickname
	if nickname == "" {
		nickname = req.Phone
	}

	var userID int64
	var createdAt, updatedAt time.Time
	err = h.db.QueryRow(ctx, `
		INSERT INTO users (phone, email, password_hash, nickname, role, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, 1, 1, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`, req.Phone, req.Email, string(hashedPassword), nickname).Scan(&userID, &createdAt, &updatedAt)
	if err != nil {
		response.InternalError(c, "创建租户失败")
		return
	}

	// TODO: If device_limit and user_limit columns exist in users table, update them here:
	// if req.DeviceLimit != nil || req.UserLimit != nil {
	//     h.db.Exec(ctx, `UPDATE users SET device_limit = $1, user_limit = $2 WHERE id = $3`, req.DeviceLimit, req.UserLimit, userID)
	// }

	response.Success(c, gin.H{
		"id":         userID,
		"phone":      req.Phone,
		"nickname":   nickname,
		"role":       1,
		"created_at": createdAt,
		"updated_at": updatedAt,
	})
}

type UpdateTenantRequest struct {
	DeviceLimit *int `json:"deviceLimit"`
	UserLimit   *int `json:"userLimit"`
}

func (h *AdminHandler) UpdateTenant(c *gin.Context) {
	tenantID := parseID(c.Param("id"))
	if tenantID <= 0 {
		response.BadRequest(c, "invalid tenant id")
		return
	}

	var req UpdateTenantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	ctx := c.Request.Context()

	user, err := h.userRepo.GetByID(ctx, tenantID)
	if err != nil || user == nil {
		response.NotFound(c, "租户不存在")
		return
	}

	// TODO: If device_limit and user_limit columns exist in users table, update them:
	// query := `UPDATE users SET device_limit = $1, user_limit = $2, updated_at = NOW() WHERE id = $3`
	// _, err = h.db.Exec(ctx, query, req.DeviceLimit, req.UserLimit, tenantID)
	// if err != nil {
	//     response.InternalError(c, "更新租户配额失败")
	//     return
	// }

	response.SuccessWithMessage(c, "配额更新成功", gin.H{
		"id": tenantID,
	})
}

func (h *AdminHandler) ToggleTenant(c *gin.Context) {
	tenantID := parseID(c.Param("id"))
	if tenantID <= 0 {
		response.BadRequest(c, "invalid tenant id")
		return
	}

	ctx := c.Request.Context()

	user, err := h.userRepo.GetByID(ctx, tenantID)
	if err != nil || user == nil {
		response.NotFound(c, "租户不存在")
		return
	}

	newStatus := 0
	if user.Status != 1 {
		newStatus = 1
	}

	if err := h.userRepo.UpdateStatus(ctx, tenantID, newStatus); err != nil {
		response.InternalError(c, "更新租户状态失败")
		return
	}
	response.SuccessWithMessage(c, "租户状态已更新", nil)
}

func (h *AdminHandler) GetMetrics(c *gin.Context) {
	ctx := c.Request.Context()

	var userCount, deviceCount, onlineCount int
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`).Scan(&userCount)
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL`).Scan(&deviceCount)
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM devices WHERE status = 1 AND deleted_at IS NULL`).Scan(&onlineCount)

	response.Success(c, gin.H{
		"user_count":   userCount,
		"device_count": deviceCount,
		"online_count": onlineCount,
		"uptime":       int64(time.Since(serverStartTime).Seconds()),
	})
}
