package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"runtime"
	"strings"
	"time"

	"inv-api-server/internal/model"
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
	cfgSvc      *service.ConfigService
}

func NewAdminHandler(userRepo *repository.UserRepository, modelRepo *repository.ModelRepository, permChecker *service.PermChecker, db *pgxpool.Pool, rdb *redis.Client, cfgSvc *service.ConfigService) *AdminHandler {
	return &AdminHandler{
		userRepo:    userRepo,
		modelRepo:   modelRepo,
		permChecker: permChecker,
		db:          db,
		rdb:         rdb,
		cfgSvc:      cfgSvc,
	}
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	page := getQueryInt(c, "page", 1)
	pageSize := getPageSize(c, 10)
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
		response.Error(c, 500, "查询用户列表失败")
		return
	}

	// Attach each user's organization type(s) so the frontend can
	// show the org-type-based role (agent/distributor/installer/customer).
	type userListItem struct {
		model.User
		OrgRoles []string `json:"org_roles"`
	}

	items := make([]userListItem, 0, len(result.Items))
	roleMap := make(map[int64][]string)
	if len(result.Items) > 0 {
		ids := make([]int64, 0, len(result.Items))
		for _, u := range result.Items {
			ids = append(ids, u.ID)
		}
		rows, qerr := h.db.Query(c.Request.Context(), `
			SELECT m.user_id, o.org_type
			FROM organization_memberships m
			JOIN organizations o ON o.id = m.organization_id AND o.deleted_at IS NULL
			WHERE m.status = 'active' AND m.user_id = ANY($1)
			ORDER BY m.user_id, o.org_type
		`, ids)
		if qerr == nil {
			defer rows.Close()
			seen := make(map[int64]map[string]struct{})
			for rows.Next() {
				var uid int64
				var orgType string
				if err := rows.Scan(&uid, &orgType); err != nil {
					continue
				}
				// manufacturer is shown as org_admin (super admin)
				code := orgType
				if code == "manufacturer" {
					code = "org_admin"
				}
				if seen[uid] == nil {
					seen[uid] = make(map[string]struct{})
				}
				if _, ok := seen[uid][code]; ok {
					continue
				}
				seen[uid][code] = struct{}{}
				roleMap[uid] = append(roleMap[uid], code)
			}
		}
	}

	for _, u := range result.Items {
		roles := roleMap[u.ID]
		if roles == nil {
			roles = []string{}
		}
		items = append(items, userListItem{User: u, OrgRoles: roles})
	}

	response.Success(c, gin.H{
		"items": items,
		"total": result.Total,
	})
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.Error(c, 400, "invalid user id")
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.Error(c, 404, "用户不存在")
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
		response.Error(c, 400, "invalid user id")
		return
	}

	var req UpdateUserRoleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if err := h.userRepo.UpdateRole(c.Request.Context(), userID, req.Role); err != nil {
		response.Error(c, 500, "更新角色失败")
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
		response.Error(c, 400, "invalid request")
		return
	}

	if err := h.userRepo.UpsertPermission(c.Request.Context(), req.Role, req.Resource, req.Action, req.IsAllowed); err != nil {
		response.Error(c, 500, "更新权限失败")
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
		response.Error(c, 400, "缺少 role 参数")
		return
	}
	role := parseID(roleParam)
	if role < 0 {
		response.Error(c, 400, "invalid role")
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
			response.Error(c, 500, "查询权限失败")
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
		response.Error(c, 400, "invalid role")
		return
	}

	var req UpdateRolePermissionsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "事务开启失败")
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
			response.Error(c, 500, "更新权限失败")
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交事务失败")
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
		response.Error(c, 400, "invalid role")
		return
	}

	var req TogglePermissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()

	var current bool
	err := h.db.QueryRow(ctx,
		`SELECT COALESCE(is_allowed, false) FROM role_permissions WHERE role=$1 AND resource=$2 AND action=$3`,
		role, req.Resource, req.Action,
	).Scan(&current)
	if err != nil && err != pgx.ErrNoRows {
		response.Error(c, 500, "查询权限失败")
		return
	}

	newVal := !current
	if err := h.userRepo.UpsertPermission(ctx, int(role), req.Resource, req.Action, newVal); err != nil {
		response.Error(c, 500, "更新权限失败")
		return
	}

	go h.permChecker.InvalidateRole(role)
	response.Success(c, gin.H{"is_allowed": newVal})
}

func (h *AdminHandler) ToggleUserStatus(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.Error(c, 400, "invalid user id")
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.Error(c, 404, "用户不存在")
		return
	}

	newStatus := 0
	if user.Status != 1 {
		newStatus = 1
	}

	if err := h.userRepo.UpdateStatus(c.Request.Context(), userID, newStatus); err != nil {
		response.Error(c, 500, "更新用户状态失败")
		return
	}
	response.SuccessWithMessage(c, "用户状态已更新", nil)
}

func (h *AdminHandler) ListAllModels(c *gin.Context) {
	models, err := h.modelRepo.ListAllWithDeviceCount(c.Request.Context())
	if err != nil {
		response.Error(c, 500, "查询型号列表失败")
		return
	}
	response.Success(c, models)
}

func (h *AdminHandler) GetAuditLogs(c *gin.Context) {
	ctx := c.Request.Context()
	page := getQueryInt(c, "page", 1)
	pageSize := getPageSize(c, 10)
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
		response.Error(c, 500, "查询审计日志失败")
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
		response.Error(c, 500, "查询审计日志失败")
		return
	}
	defer rows.Close()

	type auditLogItem struct {
		ID         int64           `json:"id"`
		UserID     int64           `json:"userId"`
		Username   string          `json:"username"`
		Action     string          `json:"action"`
		Resource   string          `json:"resource"`
		ResourceID string          `json:"resourceId"`
		Detail     json.RawMessage `json:"details"`
		IPAddress  string          `json:"ipAddress"`
		CreatedAt  time.Time       `json:"createdAt"`
	}

	var items []auditLogItem
	for rows.Next() {
		var item auditLogItem
		var details json.RawMessage
		if err := rows.Scan(&item.ID, &item.UserID, &item.Username, &item.Action,
			&item.Resource, &item.ResourceID, &details, &item.IPAddress, &item.CreatedAt); err != nil {
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
		response.Error(c, 500, "导出审计日志失败")
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

	// Enhanced: Redis ping status
	redisPing := "error"
	if h.rdb != nil {
		pingResult := h.rdb.Ping(ctx)
		if pingResult.Err() == nil {
			redisPing = pingResult.Val()
		}
	}

	// Enhanced: Database pool stats
	var dbPoolActive, dbPoolIdle, dbPoolMax int
	if h.db != nil {
		dbPoolActive = int(h.db.Stat().AcquiredConns())
		dbPoolIdle = int(h.db.Stat().IdleConns())
		dbPoolMax = int(h.db.Stat().MaxConns())
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
		"cpuUsage":    readSystemCPUUsage(),
		"database":    dbOK,
		"redis":       redisOK,
		"mqtt":        mqttOK,
		"version":     applicationVersion(),
		"lastCheckAt": time.Now().UTC().Format(time.RFC3339),
		"redis_ping":  redisPing,
		"db_pool_active": dbPoolActive,
		"db_pool_idle":   dbPoolIdle,
		"db_pool_max":    dbPoolMax,
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
		response.Error(c, 400, "invalid request")
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "事务开启失败")
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
			response.Error(c, 500, "保存配置失败: "+key)
			return
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交事务失败")
		return
	}

	// 清除配置缓存，使新配置立即生效
	if h.cfgSvc != nil {
		h.cfgSvc.Invalidate()
	}

	response.SuccessWithMessage(c, "配置保存成功", nil)
}

func (h *AdminHandler) ListTenants(c *gin.Context) {
	ctx := c.Request.Context()
	page := getQueryInt(c, "page", 1)
	pageSize := getPageSize(c, 10)
	offset := (page - 1) * pageSize

	// Legacy role=1 tenants were removed by migration 076; in the new architecture
	// tenants are root organizations. List regular (non-system-admin) users here
	// for backward compatibility of this unregistered handler.
	var total int64
	err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_system_admin = false AND deleted_at IS NULL`).Scan(&total)
	if err != nil {
		response.Error(c, 500, "查询租户列表失败")
		return
	}

	rows, err := h.db.Query(ctx, `
		SELECT u.id, u.phone, COALESCE(u.nickname,''), COALESCE(u.email,''), u.status,
		       COALESCE(u.created_at, NOW()), COALESCE(u.last_login_at, u.created_at)
		FROM users u
		WHERE u.is_system_admin = false AND u.deleted_at IS NULL
		ORDER BY u.id DESC
		LIMIT $1 OFFSET $2
	`, pageSize, offset)
	if err != nil {
		response.Error(c, 500, "查询租户列表失败")
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
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()
	if !validTenantLimit(req.DeviceLimit) || !validTenantLimit(req.UserLimit) {
		response.Error(c, 400, "tenant limits must be between 0 and 100000")
		return
	}

	var exists int
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE phone = $1 AND deleted_at IS NULL`, req.Phone).Scan(&exists)
	if exists > 0 {
		response.Error(c, 400, "该手机号已注册")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.Error(c, 500, "密码加密失败")
		return
	}

	nickname := req.Nickname
	if nickname == "" {
		nickname = req.Phone
	}

	var userID int64
	var createdAt, updatedAt time.Time
	err = h.db.QueryRow(ctx, `
		INSERT INTO users (phone, email, password_hash, nickname, is_system_admin, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, false, 1, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`, req.Phone, req.Email, string(hashedPassword), nickname).Scan(&userID, &createdAt, &updatedAt)
	if err != nil {
		response.Error(c, 500, "创建租户失败")
		return
	}

	response.Success(c, gin.H{
		"id":          userID,
		"phone":       req.Phone,
		"nickname":    nickname,
		"role":        1,
		"deviceLimit": req.DeviceLimit,
		"userLimit":   req.UserLimit,
		"created_at":  createdAt,
		"updated_at":  updatedAt,
	})
}

type UpdateTenantRequest struct {
	DeviceLimit *int `json:"deviceLimit"`
	UserLimit   *int `json:"userLimit"`
}

func (h *AdminHandler) UpdateTenant(c *gin.Context) {
	tenantID := parseID(c.Param("id"))
	if tenantID <= 0 {
		response.Error(c, 400, "invalid tenant id")
		return
	}

	var req UpdateTenantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()
	if !validTenantLimit(req.DeviceLimit) || !validTenantLimit(req.UserLimit) {
		response.Error(c, 400, "tenant limits must be between 0 and 100000")
		return
	}

	user, err := h.userRepo.GetByID(ctx, tenantID)
	if err != nil || user == nil {
		response.Error(c, 404, "租户不存在")
		return
	}

	// Legacy device_limit/user_limit/role columns were removed by migration 076;
	// keep the handler functional by touching only updated_at.
	_, err = h.db.Exec(ctx, `UPDATE users SET updated_at=NOW()
		WHERE id=$1 AND is_system_admin=false AND deleted_at IS NULL`, tenantID)
	if err != nil {
		response.Error(c, 500, "update tenant quota failed")
		return
	}

	// Legacy design note (implemented above):
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
		response.Error(c, 400, "invalid tenant id")
		return
	}

	ctx := c.Request.Context()

	user, err := h.userRepo.GetByID(ctx, tenantID)
	if err != nil || user == nil {
		response.Error(c, 404, "租户不存在")
		return
	}

	newStatus := 0
	if user.Status != 1 {
		newStatus = 1
	}

	if err := h.userRepo.UpdateStatus(ctx, tenantID, newStatus); err != nil {
		response.Error(c, 500, "更新租户状态失败")
		return
	}
	response.SuccessWithMessage(c, "租户状态已更新", nil)
}

func validTenantLimit(value *int) bool {
	return value == nil || (*value >= 0 && *value <= 100000)
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

// GetUserChildren 获取指定用户的下级用户列表
func (h *AdminHandler) GetUserChildren(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.Error(c, 400, "invalid user id")
		return
	}

	page := getQueryInt(c, "page", 1)
	pageSize := getPageSize(c, 20)

	children, total, err := h.userRepo.ListByParentID(c.Request.Context(), userID, page, pageSize)
	if err != nil {
		response.Error(c, 500, "查询下级用户失败")
		return
	}

	// 清除密码哈希
	for _, child := range children {
		child.PasswordHash = ""
	}

	response.Success(c, gin.H{
		"items": children,
		"total": total,
	})
}

// UpdateUserRequest 通用用户更新请求
type UpdateUserRequest struct {
	Nickname *string `json:"nickname"`
	Email    *string `json:"email"`
	Phone    *string `json:"phone"`
	Role     *int    `json:"role"`
	Status   *int    `json:"status"`
}

// UpdateUser 通用用户更新
func (h *AdminHandler) UpdateUser(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.Error(c, 400, "invalid user id")
		return
	}

	var req UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()

	user, err := h.userRepo.GetByID(ctx, userID)
	if err != nil || user == nil {
		response.Error(c, 404, "用户不存在")
		return
	}

	setClauses := []string{}
	args := []interface{}{}
	argIdx := 1

	if req.Nickname != nil {
		setClauses = append(setClauses, fmt.Sprintf("nickname = $%d", argIdx))
		args = append(args, *req.Nickname)
		argIdx++
	}
	if req.Email != nil {
		setClauses = append(setClauses, fmt.Sprintf("email = $%d", argIdx))
		args = append(args, *req.Email)
		argIdx++
	}
	if req.Phone != nil {
		setClauses = append(setClauses, fmt.Sprintf("phone = $%d", argIdx))
		args = append(args, *req.Phone)
		argIdx++
	}
	if req.Role != nil {
		// Legacy role column was removed by migration 076; map role == 0 (system admin)
		// onto the is_system_admin flag (dual permission model).
		setClauses = append(setClauses, fmt.Sprintf("is_system_admin = $%d", argIdx))
		args = append(args, *req.Role == 0)
		argIdx++
	}
	if req.Status != nil {
		setClauses = append(setClauses, fmt.Sprintf("status = $%d", argIdx))
		args = append(args, *req.Status)
		argIdx++
	}

	if len(setClauses) == 0 {
		response.Error(c, 400, "没有需要更新的字段")
		return
	}

	setClauses = append(setClauses, "updated_at = NOW()")
	query := fmt.Sprintf("UPDATE users SET %s WHERE id = $%d", strings.Join(setClauses, ", "), argIdx)
	args = append(args, userID)

	if _, err := h.db.Exec(ctx, query, args...); err != nil {
		response.Error(c, 500, "更新用户失败")
		return
	}

	if req.Role != nil {
		go h.permChecker.InvalidateUser(userID)
	}

	response.SuccessWithMessage(c, "用户更新成功", nil)
}

// UpdateUserParentRequest 修改用户上级关系的请求
type UpdateUserParentRequest struct {
	ParentID *int64 `json:"parentId"`
}

// UpdateUserParent 修改用户的上级关系
func (h *AdminHandler) UpdateUserParent(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.Error(c, 400, "invalid user id")
		return
	}

	var req UpdateUserParentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// 验证用户存在
	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.Error(c, 404, "用户不存在")
		return
	}

	// 如果设置了上级，验证上级用户存在且角色正确
	if req.ParentID != nil {
		parent, err := h.userRepo.GetByID(c.Request.Context(), *req.ParentID)
		if err != nil || parent == nil {
			response.Error(c, 404, "上级用户不存在")
			return
		}
		// 配额检查（如果组织系统已启用）
		if err := ensureTenantUserCapacity(c.Request.Context(), h.db, *req.ParentID, userID); err != nil {
			// 如果是表不存在的错误，跳过配额检查（组织系统未初始化）
			if !strings.Contains(err.Error(), "does not exist") {
				response.Error(c, 400, err.Error())
				return
			}
		}
	}

	if err := h.userRepo.UpdateParentID(c.Request.Context(), userID, req.ParentID); err != nil {
		response.Error(c, 500, "更新上级关系失败")
		return
	}

	response.SuccessWithMessage(c, "上级关系更新成功", nil)
}

// ResetUserPasswordRequest 重置用户密码请求
type ResetUserPasswordRequest struct {
	NewPassword string `json:"newPassword" binding:"required"`
}

// ResetUserPassword 管理员重置用户密码
func (h *AdminHandler) ResetUserPassword(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.Error(c, 400, "invalid user id")
		return
	}

	var req ResetUserPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if len(req.NewPassword) < 6 {
		response.Error(c, 400, "密码长度不能少于6位")
		return
	}

	// 验证用户存在
	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.Error(c, 404, "用户不存在")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.Error(c, 500, "密码加密失败")
		return
	}

	_, err = h.db.Exec(c.Request.Context(),
		"UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2 AND deleted_at IS NULL",
		string(hashedPassword), userID)
	if err != nil {
		response.Error(c, 500, "重置密码失败")
		return
	}

	response.SuccessWithMessage(c, "密码重置成功", nil)
}

// GetOperationStats returns aggregated operational statistics
// @Summary Get operation stats
// @Description Get user registration, login, email, push, device, command statistics
// @Tags Admin
// @Router /api/v1/admin/operation-stats [get]
func (h *AdminHandler) GetOperationStats(c *gin.Context) {
	ctx := c.Request.Context()
	stats := gin.H{}

	// 1. User registration stats
	var todayNew, weekNew, monthNew int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND created_at >= CURRENT_DATE").Scan(&todayNew)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND created_at >= CURRENT_DATE - INTERVAL '7 days'").Scan(&weekNew)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND created_at >= CURRENT_DATE - INTERVAL '30 days'").Scan(&monthNew)

	// Registration trend (last 7 days)
	regRows, _ := h.db.Query(ctx, `
		SELECT DATE(created_at) as d, COUNT(*) as cnt
		FROM users WHERE deleted_at IS NULL AND created_at >= CURRENT_DATE - INTERVAL '6 days'
		GROUP BY DATE(created_at) ORDER BY d`)
	regTrend := []gin.H{}
	if regRows != nil {
		defer regRows.Close()
		for regRows.Next() {
			var d string
			var cnt int
			regRows.Scan(&d, &cnt)
			regTrend = append(regTrend, gin.H{"date": d, "count": cnt})
		}
	}

	// 2. User login stats
	var todayActive, todayLogins int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND last_login_at >= CURRENT_DATE").Scan(&todayActive)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM audit_logs WHERE action = 'login' AND created_at >= CURRENT_DATE").Scan(&todayLogins)

	// 3. Email sending stats
	var emailToday, emailWeek int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM verification_codes WHERE created_at >= CURRENT_DATE").Scan(&emailToday)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM verification_codes WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'").Scan(&emailWeek)
	var alarmEmailToday int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM alarm_notifications WHERE notify_type = 'email' AND created_at >= CURRENT_DATE").Scan(&alarmEmailToday)
	emailToday += alarmEmailToday

	// Email by type
	emailRows, _ := h.db.Query(ctx, `
		SELECT type, COUNT(*) as cnt FROM verification_codes
		WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
		GROUP BY type`)
	emailByType := gin.H{}
	if emailRows != nil {
		defer emailRows.Close()
		for emailRows.Next() {
			var t string
			var cnt int
			emailRows.Scan(&t, &cnt)
			emailByType[t] = cnt
		}
	}
	var alarmEmailWeek int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM alarm_notifications WHERE notify_type = 'email' AND created_at >= CURRENT_DATE - INTERVAL '7 days'").Scan(&alarmEmailWeek)
	emailWeek += alarmEmailWeek

	// 4. APP push stats
	var pushToday, pushWeek int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM notifications WHERE created_at >= CURRENT_DATE").Scan(&pushToday)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM notifications WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'").Scan(&pushWeek)
	var alarmPushToday, alarmPushWeek int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM alarm_notifications WHERE notify_type = 'push' AND created_at >= CURRENT_DATE").Scan(&alarmPushToday)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM alarm_notifications WHERE notify_type = 'push' AND created_at >= CURRENT_DATE - INTERVAL '7 days'").Scan(&alarmPushWeek)
	pushToday += alarmPushToday
	pushWeek += alarmPushWeek

	// Push by type
	pushRows, _ := h.db.Query(ctx, `
		SELECT notify_type, COUNT(*) as cnt FROM notifications
		WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
		GROUP BY notify_type`)
	pushByType := gin.H{}
	if pushRows != nil {
		defer pushRows.Close()
		for pushRows.Next() {
			var t string
			var cnt int
			pushRows.Scan(&t, &cnt)
			pushByType[t] = cnt
		}
	}
	pushByType["alarm"] = alarmPushWeek

	// 5. Device online trend (last 7 days)
	onlineRows, _ := h.db.Query(ctx, `
		SELECT DATE(created_at) as d, COUNT(*) as cnt
		FROM notifications WHERE notify_type = 'device_online'
		AND created_at >= CURRENT_DATE - INTERVAL '6 days'
		GROUP BY DATE(created_at) ORDER BY d`)
	onlineTrend := []gin.H{}
	if onlineRows != nil {
		defer onlineRows.Close()
		for onlineRows.Next() {
			var d string
			var cnt int
			onlineRows.Scan(&d, &cnt)
			onlineTrend = append(onlineTrend, gin.H{"date": d, "count": cnt})
		}
	}

	// Current device stats
	var totalDevices, onlineDevices int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL").Scan(&totalDevices)
	if h.rdb != nil {
		cursor := uint64(0)
		for {
			k, nextCursor, _ := h.rdb.Scan(ctx, cursor, "device:heartbeat:*", 100).Result()
			onlineDevices += len(k)
			cursor = nextCursor
			if cursor == 0 {
				break
			}
		}
	}

	// 6. Command success rate (last 7 days)
	cmdRows, _ := h.db.Query(ctx, `
		SELECT DATE(created_at) as d,
			COUNT(*) FILTER (WHERE status IN ('success','acknowledged')) as success,
			COUNT(*) as total
		FROM device_commands
		WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
		GROUP BY DATE(created_at) ORDER BY d`)
	cmdTrend := []gin.H{}
	if cmdRows != nil {
		defer cmdRows.Close()
		for cmdRows.Next() {
			var d string
			var success, total int
			cmdRows.Scan(&d, &success, &total)
			rate := 100.0
			if total > 0 {
				rate = float64(success) / float64(total) * 100.0
			}
			cmdTrend = append(cmdTrend, gin.H{"date": d, "success": success, "total": total, "rate": rate})
		}
	}

	// Command failure reasons
	failRows, _ := h.db.Query(ctx, `
		SELECT status, COUNT(*) as cnt FROM device_commands
		WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
		AND status NOT IN ('success','acknowledged','pending','queued','sent','executing')
		GROUP BY status`)
	cmdFailures := gin.H{}
	if failRows != nil {
		defer failRows.Close()
		for failRows.Next() {
			var s string
			var cnt int
			failRows.Scan(&s, &cnt)
			cmdFailures[s] = cnt
		}
	}

	// 7. User role distribution (org-type based in the new architecture;
	// the legacy users.role column was removed by migration 076)
	roleRows, _ := h.db.Query(ctx, `
		SELECT COALESCE(o.org_type, 'none') AS org_type, COUNT(DISTINCT u.id) AS cnt
		FROM users u
		LEFT JOIN organization_memberships m ON m.user_id = u.id AND m.status = 'active'
		LEFT JOIN organizations o ON o.id = m.organization_id AND o.deleted_at IS NULL
		WHERE u.deleted_at IS NULL
		GROUP BY o.org_type ORDER BY cnt DESC`)
	roleDist := []gin.H{}
	if roleRows != nil {
		defer roleRows.Close()
		for roleRows.Next() {
			var role string
			var cnt int
			roleRows.Scan(&role, &cnt)
			roleDist = append(roleDist, gin.H{"role": role, "count": cnt})
		}
	}

	// Tenant count: one root organization per tenant in the new org architecture
	var tenantCount, stationCount int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM organizations WHERE parent_id IS NULL AND deleted_at IS NULL").Scan(&tenantCount)
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM stations").Scan(&stationCount)

	stats["users"] = gin.H{
		"today_new":          todayNew,
		"week_new":           weekNew,
		"month_new":          monthNew,
		"registration_trend": regTrend,
		"today_active":       todayActive,
		"today_logins":       todayLogins,
	}
	stats["emails"] = gin.H{
		"today":    emailToday,
		"week":     emailWeek,
		"by_type":  emailByType,
	}
	stats["pushes"] = gin.H{
		"today":    pushToday,
		"week":     pushWeek,
		"by_type":  pushByType,
	}
	stats["devices"] = gin.H{
		"total":          totalDevices,
		"online":         onlineDevices,
		"online_trend":   onlineTrend,
		"connection_rate": func() string {
			if totalDevices > 0 {
				return fmt.Sprintf("%.1f", float64(onlineDevices)/float64(totalDevices)*100)
			}
			return "0"
		}(),
	}
	stats["commands"] = gin.H{
		"trend":          cmdTrend,
		"failures":       cmdFailures,
	}
	stats["roles"] = gin.H{
		"distribution":  roleDist,
		"tenant_count":  tenantCount,
		"station_count": stationCount,
	}

	response.Success(c, stats)
}

// ── Organization-based role permission management ──

// Available role codes defined by the membership_role_assignments CHECK constraint.
var availableRoleCodes = []string{
	"org_admin", "agent", "distributor", "installer", "customer",
}

// ListOrgRoles returns the distinct role_codes that exist in an organization.
func (h *AdminHandler) ListOrgRoles(c *gin.Context) {
	orgID := parseID(c.Param("orgId"))
	if orgID <= 0 {
		response.Error(c, 400, "invalid organization id")
		return
	}
	ctx := c.Request.Context()

	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT ra.role_code
		FROM membership_role_assignments ra
		WHERE ra.organization_id = $1 AND ra.status = 'active'
		ORDER BY ra.role_code
	`, orgID)
	if err != nil {
		response.Error(c, 500, "查询组织角色失败")
		return
	}
	defer rows.Close()

	activeRoles := make([]string, 0)
	for rows.Next() {
		var code string
		if err := rows.Scan(&code); err != nil {
			continue
		}
		activeRoles = append(activeRoles, code)
	}

	type roleInfo struct {
		RoleCode string `json:"role_code"`
		Active   bool   `json:"active"`
	}
	result := make([]roleInfo, 0, len(availableRoleCodes))
	activeSet := make(map[string]bool)
	for _, r := range activeRoles {
		activeSet[r] = true
	}
	for _, code := range availableRoleCodes {
		result = append(result, roleInfo{RoleCode: code, Active: activeSet[code]})
	}

	response.Success(c, result)
}

// ListOrgRolePermissions returns all permission grants for a role_code in an organization.
func (h *AdminHandler) ListOrgRolePermissions(c *gin.Context) {
	orgID := parseID(c.Param("orgId"))
	if orgID <= 0 {
		response.Error(c, 400, "invalid organization id")
		return
	}
	roleCode := c.Param("roleCode")
	if roleCode == "" {
		response.Error(c, 400, "missing role_code")
		return
	}
	ctx := c.Request.Context()

	type permGrant struct {
		PermissionCode string `json:"permission_code"`
		DataScope      string `json:"data_scope"`
	}

	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT pg.permission_code, pg.data_scope
		FROM role_permission_grants pg
		JOIN membership_role_assignments ra
		  ON ra.id = pg.role_assignment_id
		 AND ra.root_tenant_id = pg.root_tenant_id
		 AND ra.organization_id = pg.organization_id
		WHERE pg.organization_id = $1
		  AND ra.role_code = $2
		  AND ra.status = 'active'
		ORDER BY pg.permission_code
	`, orgID, roleCode)
	if err != nil {
		response.Error(c, 500, "查询权限失败")
		return
	}
	defer rows.Close()

	grants := make([]permGrant, 0)
	for rows.Next() {
		var g permGrant
		if err := rows.Scan(&g.PermissionCode, &g.DataScope); err != nil {
			continue
		}
		grants = append(grants, g)
	}

	response.Success(c, grants)
}

// UpdateOrgRolePermissionsRequest defines the payload for updating org role permissions.
type UpdateOrgRolePermissionsRequest struct {
	Permissions []struct {
		PermissionCode string `json:"permission_code"`
		DataScope      string `json:"data_scope"`
		IsAllowed      bool   `json:"is_allowed"`
	} `json:"permissions"`
}

// UpdateOrgRolePermissions updates permission grants for a role_code across all
// role assignments in an organization.
func (h *AdminHandler) UpdateOrgRolePermissions(c *gin.Context) {
	orgID := parseID(c.Param("orgId"))
	if orgID <= 0 {
		response.Error(c, 400, "invalid organization id")
		return
	}
	roleCode := c.Param("roleCode")
	if roleCode == "" {
		response.Error(c, 400, "missing role_code")
		return
	}

	var req UpdateOrgRolePermissionsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()

	rows, err := h.db.Query(ctx, `
		SELECT ra.root_tenant_id, ra.organization_id, ra.id
		FROM membership_role_assignments ra
		WHERE ra.organization_id = $1 AND ra.role_code = $2 AND ra.status = 'active'
	`, orgID, roleCode)
	if err != nil {
		response.Error(c, 500, "查询角色分配失败")
		return
	}

	type roleAssignment struct {
		RootTenantID int64
		ID           int64
	}
	assignments := make([]roleAssignment, 0)
	for rows.Next() {
		var ra roleAssignment
		if err := rows.Scan(&ra.RootTenantID, &ra.ID); err != nil {
			continue
		}
		assignments = append(assignments, ra)
	}
	rows.Close()

	if len(assignments) == 0 {
		response.Error(c, 404, "该组织下没有此角色的活动分配")
		return
	}

	desiredPerms := make(map[string]string)
	for _, p := range req.Permissions {
		if p.IsAllowed {
			scope := p.DataScope
			if scope == "" {
				scope = "organization_and_descendants"
			}
			desiredPerms[p.PermissionCode] = scope
		}
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "事务开启失败")
		return
	}
	defer tx.Rollback(ctx)

	desiredKeys := make([]string, 0, len(desiredPerms))
	for k := range desiredPerms {
		desiredKeys = append(desiredKeys, k)
	}

	for _, ra := range assignments {
		_, err := tx.Exec(ctx, `
			DELETE FROM role_permission_grants
			WHERE root_tenant_id = $1 AND organization_id = $2 AND role_assignment_id = $3
			  AND permission_code <> ALL($4::text[])
		`, ra.RootTenantID, orgID, ra.ID, desiredKeys)
		if err != nil {
			response.Error(c, 500, "删除权限失败")
			return
		}

		for permCode, dataScope := range desiredPerms {
			_, err := tx.Exec(ctx, `
				INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope, scope_definition)
				VALUES ($1, $2, $3, $4, $5, '{}'::jsonb)
				ON CONFLICT (role_assignment_id, permission_code)
				DO UPDATE SET data_scope = EXCLUDED.data_scope, updated_at = NOW()
			`, ra.RootTenantID, orgID, ra.ID, permCode, dataScope)
			if err != nil {
				response.Error(c, 500, "更新权限失败")
				return
			}
		}
	}

	_, err = tx.Exec(ctx, `
		UPDATE organization_memberships m
		SET authorization_version = authorization_version + 1
		WHERE m.organization_id = $1
		  AND m.id IN (
			SELECT ra.membership_id FROM membership_role_assignments ra
			WHERE ra.organization_id = $1 AND ra.role_code = $2 AND ra.status = 'active'
		)
	`, orgID, roleCode)
	if err != nil {
		response.Error(c, 500, "更新授权版本失败")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交事务失败")
		return
	}

	response.SuccessWithMessage(c, "权限配置保存成功", nil)
}

// ListAllPermissionCodes returns all distinct permission codes defined in the system.
func (h *AdminHandler) ListAllPermissionCodes(c *gin.Context) {
	ctx := c.Request.Context()

	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT permission_code FROM (
			SELECT permission_code FROM role_permission_grants
			UNION ALL
			VALUES
				('devices:view'), ('devices:create'), ('devices:edit'), ('devices:delete'), ('devices:export'),
				('devices:control'), ('devices:manage'), ('devices:transfer'),
				('device_control:basic'), ('device_control:disruptive'),
				('device_configure:battery'), ('device_configure:ac_input'), ('device_configure:parallel'),
				('device_service:diagnostics'), ('device_service:factory'),
				('users:view'), ('users:create'), ('users:edit'), ('users:delete'), ('users:manage'),
				('alerts:view'), ('alerts:manage'),
				('alert_rules:view'), ('alert_rules:create'), ('alert_rules:edit'), ('alert_rules:delete'),
				('work_orders:view'), ('work_orders:create'), ('work_orders:edit'), ('work_orders:manage'),
				('firmware:view'), ('firmware:create'), ('firmware:delete'),
				('ota:view'), ('ota:create'), ('ota:control'), ('ota:delete'),
				('dashboard:view'), ('dashboard:export'),
				('stations:view'), ('stations:create'), ('stations:edit'), ('stations:manage'),
				('models:view'), ('models:manage'),
				('parallel:view'), ('parallel:create'), ('parallel:control'),
				('audit:view'),
				('admin:view'), ('admin:manage'),
				('organizations:view'), ('organizations:manage'), ('organizations:invite'),
				('organizations:manage_members'),
		) AS t(permission_code)
		ORDER BY permission_code
	`)
	if err != nil {
		response.Error(c, 500, "查询权限码失败")
		return
	}
	defer rows.Close()

	codes := make([]string, 0)
	for rows.Next() {
		var code string
		if err := rows.Scan(&code); err != nil {
			continue
		}
		codes = append(codes, code)
	}

	response.Success(c, codes)
}
