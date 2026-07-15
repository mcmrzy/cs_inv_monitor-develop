package middleware

import (
	"context"
	"encoding/json"
	"errors"
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
	perms         []PermissionEntry
	cachedAt      time.Time
	authoritative bool
}

type RBACMiddleware struct {
	rdb       *redis.Client
	pg        *pgxpool.Pool
	cacheTTL  time.Duration
	mu        sync.RWMutex
	roleCache map[string]cacheEntry
	// queryRolePermissions is replaceable in unit tests. Production always uses
	// the legacy role_permissions table, which is the gateway's RBAC source of
	// truth.
	queryRolePermissions func(context.Context, int) ([]PermissionEntry, error)
}

func NewRBACMiddleware(rdb *redis.Client, pg *pgxpool.Pool, cacheTTLSec int) *RBACMiddleware {
	if cacheTTLSec <= 0 {
		cacheTTLSec = 300
	}
	r := &RBACMiddleware{
		rdb:       rdb,
		pg:        pg,
		cacheTTL:  time.Duration(cacheTTLSec) * time.Second,
		roleCache: make(map[string]cacheEntry),
	}
	r.queryRolePermissions = r.loadRolePermissionsFromDB
	return r
}

// Sentinel errors returned by getUserRole. hasPermission uses them to decide
// whether falling back to the JWT role claim is safe.
var (
	// errRoleUnknown: Redis is reachable but has not cached this user yet and
	// no database is available to confirm the role. The role is genuinely
	// unknown (not revoked), so a JWT fallback is acceptable.
	errRoleUnknown = errors.New("user role not cached and no database to resolve it")
	// errRoleExplicitlyEmpty: the cache holds an entry for the user but it
	// contains no valid role (e.g. "[]"). This is an authoritative negative
	// answer — the role was stripped — so the JWT claim must NOT override it.
	errRoleExplicitlyEmpty = errors.New("user role cache entry is empty or invalid")
	// errNoRoleSource: neither Redis nor a database is configured. The gateway
	// is fully degraded and cannot authoritatively resolve any role.
	errNoRoleSource = errors.New("no role resolution source available")
)

func (r *RBACMiddleware) getUserRole(ctx context.Context, userID string) (int, error) {
	if r.rdb != nil {
		cacheKey := "gw:user_roles:" + userID
		cached, err := r.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			// Cache HIT — parse the cached role.
			var roleIDs []int
			if json.Unmarshal([]byte(cached), &roleIDs) == nil {
				if len(roleIDs) > 0 && roleIDs[0] >= 0 {
					return roleIDs[0], nil
				}
			} else if role, parseErr := strconv.Atoi(cached); parseErr == nil && role >= 0 {
				return role, nil
			}
		}
		// Redis miss — fall through to the database when available.
		if r.pg == nil {
			// No DB to confirm: the role is genuinely unknown, not revoked.
			return -1, errRoleUnknown
		}
	} else if r.pg == nil {
		// Neither Redis nor a database is configured. The gateway is fully
		// degraded and cannot authoritatively resolve any role.
		return -1, errNoRoleSource
	}

	// Database lookup (reached when Redis missed but pg is available, or when
	// Redis is absent but pg is available).
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

func (r *RBACMiddleware) getRolePermissions(ctx context.Context, role int) ([]PermissionEntry, bool, error) {
	cacheKey := fmt.Sprintf("gw:role_perms:%d", role)

	if r.rdb != nil {
		cached, err := r.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var perms []PermissionEntry
			if err := json.Unmarshal([]byte(cached), &perms); err == nil {
				r.mu.Lock()
				r.roleCache[cacheKey] = cacheEntry{
					perms:         perms,
					cachedAt:      time.Now(),
					authoritative: false,
				}
				r.mu.Unlock()
				return perms, true, nil
			}
		}
		// A Redis miss is the cross-process invalidation signal emitted by the
		// API admin handlers. Do not reuse an in-process entry after that signal.
		perms, err := r.refreshRolePermissions(ctx, role)
		return perms, false, err
	}

	// Redis is optional in tests and degraded local deployments. In that case
	// the bounded in-process cache remains useful.
	r.mu.RLock()
	if entry, ok := r.roleCache[cacheKey]; ok && time.Since(entry.cachedAt) < r.cacheTTL {
		r.mu.RUnlock()
		return entry.perms, !entry.authoritative, nil
	}
	r.mu.RUnlock()

	perms, err := r.refreshRolePermissions(ctx, role)
	return perms, false, err
}

func (r *RBACMiddleware) loadRolePermissionsFromDB(ctx context.Context, role int) ([]PermissionEntry, error) {
	if r.pg == nil {
		return nil, fmt.Errorf("no database connection")
	}

	rows, err := r.pg.Query(ctx, `
		SELECT resource, action
		FROM role_permissions
		WHERE role = $1 AND is_allowed = true
	`, role)
	if err != nil {
		// role_permissions may not exist when migrations are incomplete. Fail
		// closed instead of turning a storage failure into an implicit allow.
		log.Printf("[WARN] RBAC: 查询 role_permissions 失败 (role=%d): %v - 请执行 012_create_role_permissions 迁移", role, err)
		return nil, err
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

	return perms, rows.Err()
}

func (r *RBACMiddleware) refreshRolePermissions(ctx context.Context, role int) ([]PermissionEntry, error) {
	if r.queryRolePermissions == nil {
		return nil, fmt.Errorf("no role permission source")
	}

	perms, err := r.queryRolePermissions(ctx, role)
	if err != nil {
		return nil, err
	}
	cacheKey := fmt.Sprintf("gw:role_perms:%d", role)
	if r.rdb != nil {
		data, _ := json.Marshal(perms)
		r.rdb.Set(ctx, cacheKey, string(data), r.cacheTTL)
	}

	r.mu.Lock()
	r.roleCache[cacheKey] = cacheEntry{
		perms:         perms,
		cachedAt:      time.Now(),
		authoritative: true,
	}
	r.mu.Unlock()

	return perms, nil
}

func (r *RBACMiddleware) hasPermission(userID string, resource string, action string) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if userID == "" {
		return false
	}

	// A signed JWT can outlive an administrator's role change. Resolve the
	// current role from the shared invalidatable cache/database so an old token
	// cannot retain elevated (especially role=0) access.
	role, err := r.getUserRole(ctx, userID)
	if err != nil || role < 0 {
		return false
	}

	if role == 0 {
		return true
	}

	perms, needsAuthorityCheck, err := r.getRolePermissions(ctx, role)
	if err != nil {
		return false
	}

	if permissionIncluded(perms, resource, action) {
		return true
	}

	// The API service and gateway historically shared the gw:role_perms:* cache
	// while loading it from different RBAC schemas. A negative/stale cache entry
	// must therefore be checked against the gateway's authoritative table before
	// rejecting an otherwise valid device owner request.
	if needsAuthorityCheck {
		perms, err = r.refreshRolePermissions(ctx, role)
		if err != nil {
			return false
		}
	}

	return permissionIncluded(perms, resource, action)
}

func permissionIncluded(perms []PermissionEntry, resource, action string) bool {
	for _, p := range perms {
		if p.Resource == resource && p.Action == action {
			return true
		}
	}
	return false
}

var resourceActionMap = map[string]string{
	"/api/v1/admin/":             "admin",
	"/api/v1/internal/":          "admin",
	"/api/v1/users":              "users",
	"/api/v1/users/":             "users",
	"/api/v1/ota/tasks":          "ota",
	"/api/v1/ota/firmwares":      "firmware",
	"/api/v1/ota/":               "ota",
	"/api/v1/parallel":           "parallel",
	"/api/v1/parallel/":          "parallel",
	"/api/v1/parallel-groups":    "parallel",
	"/api/v1/parallel-groups/":   "parallel",
	"/api/v1/devices":            "devices",
	"/api/v1/devices/":           "devices",
	"/api/v1/device/":            "devices",
	"/api/v1/alarms":             "alerts",
	"/api/v1/alarms/":            "alerts",
	"/api/v1/alerts":             "alerts",
	"/api/v1/alerts/":            "alerts",
	"/api/v1/alarm-events":       "alerts",
	"/api/v1/alarm-events/":      "alerts",
	"/api/v1/stations":           "stations",
	"/api/v1/stations/":          "stations",
	"/api/v1/models":             "models",
	"/api/v1/models/":            "models",
	"/api/v1/field-catalog":      "models",
	"/api/v1/protocol-versions":  "models",
	"/api/v1/protocol-versions/": "models",
	"/api/v1/dashboard":          "dashboard",
	"/api/v1/dashboard/":         "dashboard",
	"/api/v1/stats/":             "dashboard",
	"/api/v1/notifications":      "notifications",
	"/api/v1/notifications/":     "notifications",
	"/api/v1/alert-rules":        "alert_rules",
	"/api/v1/alert-rules/":       "alert_rules",
	"/api/v1/work-orders":        "work_orders",
	"/api/v1/work-orders/":       "work_orders",
	"/api/v1/firmwares":          "firmware",
}

// These endpoints are intentionally available to every authenticated user.
// Keep this list exact: an auth-prefixed endpoint that is not listed must not
// silently bypass RBAC.
var authenticatedOnlyPaths = map[string]struct{}{
	"/api/v1/auth/logout":          {},
	"/api/v1/auth/change-password": {},
	"/api/v1/auth/profile":         {},
}

func isAuthenticatedOnlyPath(path string) bool {
	_, ok := authenticatedOnlyPaths[path]
	return ok
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

		if isAuthenticatedOnlyPath(c.Request.URL.Path) {
			c.Next()
			return
		}

		userID := c.GetHeader("X-User-ID")
		if userID == "" {
			c.Next()
			return
		}

		path := c.Request.URL.Path
		var resource string

		resource = resourceForPath(path)

		if resource == "" {
			// Every route in this middleware is already part of an authenticated
			// route group. Missing policy is a configuration error, not permission.
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "权限策略缺失，拒绝访问",
			})
			c.Abort()
			return
		}

		action := r.getActionForRequest(path, c.Request.Method)
		if !r.hasPermission(userID, resource, action) {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "权限不足，无法访问该资源",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// resourceForPath chooses the most specific matching prefix. Iterating a Go
// map and taking the first match made overlapping routes such as ota/firmwares
// nondeterministic.
func resourceForPath(path string) string {
	resource := ""
	longest := 0
	for prefix, candidate := range resourceActionMap {
		if !pathPrefixMatches(path, prefix) {
			continue
		}
		if len(prefix) > longest {
			resource = candidate
			longest = len(prefix)
		}
	}
	return resource
}

func pathPrefixMatches(path, prefix string) bool {
	if path == prefix {
		return true
	}
	if strings.HasSuffix(prefix, "/") {
		return strings.HasPrefix(path, prefix)
	}
	return strings.HasPrefix(path, prefix+"/")
}

func (r *RBACMiddleware) getActionForRequest(path, method string) string {
	// The API protects the entire /admin group with one explicit admin:manage
	// middleware. Use the same contract at the Gateway instead of requiring an
	// additional method-derived permission for the same request.
	if pathPrefixMatches(path, "/api/v1/admin/") {
		return "manage"
	}
	// Alarm acknowledgement and ignore mutate an existing alarm even though the
	// historical API models them as POST commands.
	if method == http.MethodPost &&
		(strings.HasSuffix(path, "/acknowledge") || strings.HasSuffix(path, "/ignore")) {
		return "edit"
	}
	// OTA lifecycle commands are operational controls, not resource creation or
	// ordinary edits.  Keep the Gateway action aligned with the API's explicit
	// RequirePermission(..., "ota", "control") checks.
	if isOTAControlRequest(path, method) {
		return "control"
	}
	// Device control commands are operational controls, not resource creation.
	// Keep the Gateway action aligned with the API's RequirePermission(..., "devices", "control") checks.
	if method == http.MethodPost && pathPrefixMatches(path, "/api/v1/devices/") && strings.HasSuffix(path, "/control") {
		return "control"
	}
	return r.getActionFromMethod(method)
}

func isOTAControlRequest(path, method string) bool {
	if !pathPrefixMatches(path, "/api/v1/ota") {
		return false
	}

	if method == http.MethodPost {
		if path == "/api/v1/ota/rollback" || path == "/api/v1/ota/rollback-to-published" {
			return true
		}
		for _, suffix := range []string{"/retry", "/cancel", "/execute", "/rollback", "/restore"} {
			if strings.HasSuffix(path, suffix) {
				return true
			}
		}
	}

	if method == http.MethodPatch && strings.HasSuffix(path, "/publish") {
		return true
	}
	return method == http.MethodPut && strings.HasSuffix(path, "/rollout")
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
