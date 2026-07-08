package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type PermissionEntry struct {
	Resource string `json:"resource"`
	Action   string `json:"action"`
}

type cacheEntry struct {
	perms    []PermissionEntry
	cachedAt time.Time
}

type RBACMiddleware struct {
	rdb       *redis.Client
	pg        *pgxpool.Pool
	cacheTTL  time.Duration
	mu        sync.RWMutex
	roleCache map[string]cacheEntry
}

func NewRBACMiddleware(rdb *redis.Client, pg *pgxpool.Pool, cacheTTLSec int) *RBACMiddleware {
	if cacheTTLSec <= 0 {
		cacheTTLSec = 300
	}
	return &RBACMiddleware{
		rdb:       rdb,
		pg:        pg,
		cacheTTL:  time.Duration(cacheTTLSec) * time.Second,
		roleCache: make(map[string]cacheEntry),
	}
}

func (r *RBACMiddleware) getUserRole(ctx context.Context, userID string) (int, error) {
	if r.rdb != nil {
		cacheKey := "gw:user_roles:" + userID
		cached, err := r.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var roleIDs []int
			if json.Unmarshal([]byte(cached), &roleIDs) == nil && len(roleIDs) > 0 {
				return roleIDs[0], nil
			}
			role, _ := strconv.Atoi(cached)
			return role, nil
		}
	}

	if r.pg == nil {
		return -1, fmt.Errorf("no database connection")
	}

	var role int
	err := r.pg.QueryRow(ctx,
		"SELECT COALESCE(role, -1) FROM users WHERE id = $1 AND deleted_at IS NULL",
		userID).Scan(&role)
	if err != nil {
		return -1, err
	}

	if r.rdb != nil && role >= 0 {
		r.rdb.Set(ctx, "gw:user_roles:"+userID, role, r.cacheTTL)
	}

	return role, nil
}

func (r *RBACMiddleware) getRolePermissions(ctx context.Context, role int) ([]PermissionEntry, error) {
	cacheKey := fmt.Sprintf("gw:role_perms:%d", role)

	r.mu.RLock()
	if entry, ok := r.roleCache[cacheKey]; ok {
		// 检查内存缓存是否过期
		if time.Since(entry.cachedAt) < r.cacheTTL {
			r.mu.RUnlock()
			return entry.perms, nil
		}
	}
	r.mu.RUnlock()

	if r.rdb != nil {
		cached, err := r.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var perms []PermissionEntry
			if err := json.Unmarshal([]byte(cached), &perms); err == nil {
				r.mu.Lock()
				r.roleCache[cacheKey] = cacheEntry{
					perms:    perms,
					cachedAt: time.Now(),
				}
				r.mu.Unlock()
				return perms, nil
			}
		}
	}

	if r.pg == nil {
		return nil, fmt.Errorf("no database connection")
	}

	rows, err := r.pg.Query(ctx, `
		SELECT resource, action
		FROM role_permissions
		WHERE role = $1 AND is_allowed = true
	`, role)
	if err != nil {
		// role_permissions 表可能不存在（未执行迁移），记录警告并返回空列表
		log.Printf("[WARN] RBAC: 查询 role_permissions 失败 (role=%d): %v - 请执行 012_create_role_permissions 迁移", role, err)
		return []PermissionEntry{}, nil
	}
	defer rows.Close()

	var perms []PermissionEntry
	for rows.Next() {
		var p PermissionEntry
		if err := rows.Scan(&p.Resource, &p.Action); err != nil {
			continue
		}
		perms = append(perms, p)
	}

	if r.rdb != nil {
		data, _ := json.Marshal(perms)
		r.rdb.Set(ctx, cacheKey, string(data), r.cacheTTL)
	}

	r.mu.Lock()
	r.roleCache[cacheKey] = cacheEntry{
		perms:    perms,
		cachedAt: time.Now(),
	}
	r.mu.Unlock()

	return perms, nil
}

func (r *RBACMiddleware) hasPermission(userID string, resource string, action string, headerRole string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if userID == "" {
		return false
	}

	var role int
	var err error

	if headerRole != "" {
		role, err = strconv.Atoi(headerRole)
		if err != nil {
			role = -1
		}
	}

	if role < 0 {
		role, err = r.getUserRole(ctx, userID)
		if err != nil || role < 0 {
			return false
		}
	}

	if role == 0 {
		return true
	}

	perms, err := r.getRolePermissions(ctx, role)
	if err != nil {
		return false
	}

	for _, p := range perms {
		if p.Resource == resource && p.Action == action {
			return true
		}
	}

	return false
}

var resourceActionMap = map[string]string{
	"/api/v1/admin/":          "admin",
	"/api/v1/users":           "users",
	"/api/v1/users/":          "users",
	"/api/v1/ota/tasks":       "ota",
	"/api/v1/ota/firmwares":   "firmware",
	"/api/v1/ota/":            "ota",
	"/api/v1/parallel":        "parallel",
	"/api/v1/parallel/":       "parallel",
	"/api/v1/devices":         "devices",
	"/api/v1/devices/":        "devices",
	"/api/v1/alarms":          "alerts",
	"/api/v1/alarms/":         "alerts",
	"/api/v1/stations/":       "stations",
	"/api/v1/models":          "models",
	"/api/v1/models/":         "models",
	"/api/v1/dashboard":       "dashboard",
	"/api/v1/dashboard/":      "dashboard",
	"/api/v1/notifications/":  "notifications",
	"/api/v1/alert-rules":     "alert_rules",
	"/api/v1/alert-rules/":    "alert_rules",
	"/api/v1/work-orders":     "work_orders",
	"/api/v1/work-orders/":    "work_orders",
	"/api/v1/firmwares":       "firmware",
}

// appAllowedPaths 定义 APP 端接口白名单。
// 这些接口已通过 JWT 认证保护（位于 user 组），对所有登录用户开放，不需要 RBAC 细粒度权限检查。
// 在路由分组架构下，这些接口属于 user 组，会经过 RBAC 中间件，
// 因此保留此白名单以确保 APP 端 OTA 等接口不被 RBAC resourceActionMap 误拦截。
var appAllowedPaths = []string{
	"/api/v1/ota/check/",
	"/api/v1/ota/trigger",
	"/api/v1/ota/resend/",
	"/api/v1/ota/devices/",
	"/api/v1/ota/app/check",
	"/api/v1/ota/app/packages",
	"/api/v1/ota/packages/available/",
}

func isAppAllowedPath(path string) bool {
	for _, prefix := range appAllowedPaths {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

func (r *RBACMiddleware) RBACGuard() gin.HandlerFunc {
	return func(c *gin.Context) {
		if isPublicPath(c.Request.URL.Path) {
			c.Next()
			return
		}

		// APP 端接口已通 JWT 认证保护，对所有登录用户开放，跳过 RBAC
		if isAppAllowedPath(c.Request.URL.Path) {
			c.Next()
			return
		}

		userID := c.GetHeader("X-User-ID")
		if userID == "" {
			log.Printf("[DEBUG-INSTRUMENT] RBACGuard: %s %s - 无 X-User-ID 头，跳过检查", c.Request.Method, c.Request.URL.Path)
			c.Next()
			return
		}

		path := c.Request.URL.Path
		var resource string

		for prefix, res := range resourceActionMap {
			if strings.HasPrefix(path, prefix) {
				resource = res
				break
			}
		}

		if resource == "" {
			log.Printf("[DEBUG-INSTRUMENT] RBACGuard: %s %s - 无匹配资源，跳过检查", c.Request.Method, path)
			c.Next()
			return
		}

		action := r.getActionFromMethod(c.Request.Method)
		headerRole := c.GetHeader("X-User-Role")

		log.Printf("[DEBUG-INSTRUMENT] RBACGuard: %s %s - user=%s resource=%s action=%s headerRole=%s",
			c.Request.Method, path, userID, resource, action, headerRole)

		if !r.hasPermission(userID, resource, action, headerRole) {
			log.Printf("[DEBUG-INSTRUMENT] RBACGuard: %s %s - 权限拒绝!", c.Request.Method, path)
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "权限不足，无法访问该资源",
			})
			c.Abort()
			return
		}

		log.Printf("[DEBUG-INSTRUMENT] RBACGuard: %s %s - 权限通过", c.Request.Method, path)
		c.Next()
	}
}

func (r *RBACMiddleware) getActionFromMethod(method string) string {
	switch method {
	case "GET":
		return "view"
	case "POST":
		return "create"
	case "PUT", "PATCH":
		return "edit"
	case "DELETE":
		return "delete"
	default:
		return "view"
	}
}

func (r *RBACMiddleware) InvalidateUserCache(userID string) {
	if r.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		r.rdb.Del(ctx, "gw:user_roles:"+userID)
	}
}

func (r *RBACMiddleware) InvalidateRoleCache(role int) {
	cacheKey := fmt.Sprintf("gw:role_perms:%d", role)
	r.mu.Lock()
	delete(r.roleCache, cacheKey)
	r.mu.Unlock()

	if r.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		r.rdb.Del(ctx, cacheKey)
	}
}

func ParseUserID(c *gin.Context) int64 {
	userIDStr := c.GetHeader("X-User-ID")
	if userIDStr == "" {
		return 0
	}
	userID, _ := strconv.ParseInt(userIDStr, 10, 64)
	return userID
}
