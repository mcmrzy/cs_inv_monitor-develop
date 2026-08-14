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

// PermissionEntry holds a single permission code and its data scope granted
// to the user through their active organization membership.
type PermissionEntry struct {
	PermissionCode string `json:"permission_code"`
	DataScope      string `json:"data_scope"`
}

type cacheEntry struct {
	perms         []PermissionEntry
	cachedAt      time.Time
	authoritative bool
}

type RBACMiddleware struct {
	rdb      *redis.Client
	pg       *pgxpool.Pool
	cacheTTL time.Duration
	mu       sync.RWMutex
	permCache map[string]cacheEntry
	// queryUserPermissions is replaceable in unit tests. Production always
	// queries membership_role_assignments + role_permission_grants.
	queryUserPermissions func(context.Context, int64, int64, int64) ([]PermissionEntry, error)
}

func NewRBACMiddleware(rdb *redis.Client, pg *pgxpool.Pool, cacheTTLSec int) *RBACMiddleware {
	if cacheTTLSec <= 0 {
		cacheTTLSec = 300
	}
	r := &RBACMiddleware{
		rdb:       rdb,
		pg:        pg,
		cacheTTL:  time.Duration(cacheTTLSec) * time.Second,
		permCache: make(map[string]cacheEntry),
	}
	r.queryUserPermissions = r.loadUserPermissionsFromDB
	return r
}

// Sentinel errors for permission resolution.
var (
	errPermsUnknown     = errors.New("user permissions not cached and no database to resolve them")
	errPermsEmpty       = errors.New("user has no permission grants")
	errNoPermSource     = errors.New("no permission resolution source available")
)

// resolveUserPermissions fetches the user's permission codes from cache or DB.
// Cache key includes organization and membership to scope permissions correctly.
func (r *RBACMiddleware) resolveUserPermissions(ctx context.Context, userID string, orgID string, membershipID string) ([]PermissionEntry, error) {
	cacheKey := fmt.Sprintf("gw:user_perms:%s:%s:%s", userID, orgID, membershipID)

	if r.rdb != nil {
		cached, err := r.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var perms []PermissionEntry
			if json.Unmarshal([]byte(cached), &perms) == nil {
				return perms, nil
			}
			// Corrupt cache entry — delete and fall through to DB.
			_ = r.rdb.Del(ctx, cacheKey).Err()
		}
		// Redis miss — fall through to queryUserPermissions.
	}

	// Database lookup
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil || uid <= 0 {
		return nil, fmt.Errorf("invalid user ID: %s", userID)
	}
	oid, _ := strconv.ParseInt(orgID, 10, 64)
	mid, _ := strconv.ParseInt(membershipID, 10, 64)

	perms, err := r.queryUserPermissions(ctx, uid, oid, mid)
	if err != nil {
		return nil, err
	}

	// Cache the result
	if r.rdb != nil {
		data, _ := json.Marshal(perms)
		r.rdb.Set(ctx, cacheKey, string(data), r.cacheTTL)
	}

	r.mu.Lock()
	r.permCache[cacheKey] = cacheEntry{
		perms:         perms,
		cachedAt:      time.Now(),
		authoritative: true,
	}
	r.mu.Unlock()

	return perms, nil
}

// loadUserPermissionsFromDB queries the new organization-based permission tables.
func (r *RBACMiddleware) loadUserPermissionsFromDB(ctx context.Context, userID, orgID, membershipID int64) ([]PermissionEntry, error) {
	if r.pg == nil {
		return nil, fmt.Errorf("no database connection")
	}

	// Build query with safe parameterized placeholders
	query := `
		SELECT DISTINCT pg.permission_code, pg.data_scope
		FROM organization_memberships m
		JOIN membership_role_assignments ra
		  ON ra.root_tenant_id = m.root_tenant_id
		 AND ra.organization_id = m.organization_id
		 AND ra.membership_id = m.id
		JOIN role_permission_grants pg
		  ON pg.root_tenant_id = ra.root_tenant_id
		 AND pg.role_assignment_id = ra.id
		WHERE m.user_id = $1 AND m.status = 'active'
	`
	args := []interface{}{userID}
	paramIdx := 2

	if orgID > 0 {
		query += fmt.Sprintf(` AND m.organization_id = $%d`, paramIdx)
		args = append(args, orgID)
		paramIdx++
	}
	if membershipID > 0 {
		query += fmt.Sprintf(` AND m.id = $%d`, paramIdx)
		args = append(args, membershipID)
	}

	rows, err := r.pg.Query(ctx, query, args...)
	if err != nil {
		log.Printf("[WARN] RBAC: 查询用户权限失败 (userID=%d): %v", userID, err)
		return nil, err
	}
	defer rows.Close()

	var perms []PermissionEntry
	for rows.Next() {
		var p PermissionEntry
		if err := rows.Scan(&p.PermissionCode, &p.DataScope); err != nil {
			continue
		}
		perms = append(perms, p)
	}

	return perms, rows.Err()
}

// isSystemAdmin checks the X-Is-System-Admin header set by the JWT middleware.
func isSystemAdmin(c *gin.Context) bool {
	v := c.GetHeader("X-Is-System-Admin")
	return v == "true" || v == "1"
}

// hasPermissionCode checks whether the user has the required permission code.
func (r *RBACMiddleware) hasPermissionCode(c *gin.Context, permissionCode string) bool {
	// System admins bypass all permission checks
	if isSystemAdmin(c) {
		return true
	}

	userID := c.GetHeader("X-User-ID")
	if userID == "" {
		return false
	}

	orgID := c.GetHeader("X-Organization-ID")
	membershipID := c.GetHeader("X-Membership-ID")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	perms, err := r.resolveUserPermissions(ctx, userID, orgID, membershipID)
	if err != nil {
		return false
	}

	for _, p := range perms {
		if p.PermissionCode == permissionCode {
			return true
		}
	}
	return false
}

// resourceActionMap maps URL path prefixes to resource names.
// The resource name is combined with the HTTP method-derived action to form
// a permission_code (e.g., "devices:view").
var resourceActionMap = map[string]string{
	"/api/v1/admin/":               "admin",
	"/api/v1/internal/":            "admin",
	"/api/v1/users":                "users",
	"/api/v1/users/":               "users",
	"/api/v1/ota/tasks":            "ota",
	"/api/v1/ota/firmware":         "firmware",
	"/api/v1/ota/firmwares":        "firmware",
	"/api/v1/ota/":                 "ota",
	"/api/v1/parallel":             "parallel",
	"/api/v1/parallel/":            "parallel",
	"/api/v1/parallel-groups":      "parallel",
	"/api/v1/parallel-groups/":     "parallel",
	"/api/v1/devices":              "devices",
	"/api/v1/devices/":             "devices",
	"/api/v1/device/":              "devices",
	"/api/v1/alarms":               "alerts",
	"/api/v1/alarms/":              "alerts",
	"/api/v1/alerts":               "alerts",
	"/api/v1/alerts/":              "alerts",
	"/api/v1/alarm-events":         "alerts",
	"/api/v1/alarm-events/":        "alerts",
	"/api/v1/stations":             "stations",
	"/api/v1/stations/":            "stations",
	"/api/v1/geocode":              "stations",
	"/api/v1/geocode/":             "stations",
	"/api/v1/models":               "models",
	"/api/v1/models/":              "models",
	"/api/v1/field-catalog":        "models",
	"/api/v1/protocol-versions":    "models",
	"/api/v1/protocol-versions/":   "models",
	"/api/v1/dashboard":            "dashboard",
	"/api/v1/dashboard/":           "dashboard",
	"/api/v1/stats/":               "dashboard",
	"/api/v1/notifications":        "notifications",
	"/api/v1/notifications/":       "notifications",
	"/api/v1/alert-rules":          "alert_rules",
	"/api/v1/alert-rules/":         "alert_rules",
	"/api/v1/work-orders":          "work_orders",
	"/api/v1/work-orders/":         "work_orders",
	"/api/v1/work-order-stats":     "work_orders",
	"/api/v1/work-order-templates": "work_orders",
	"/api/v1/firmwares":            "firmware",
	"/api/v1/organizations":        "organizations",
	"/api/v1/organizations/":       "organizations",
	"/api/v1/invitations":          "organizations",
	"/api/v1/invitations/":         "organizations",
	"/api/v1/members":              "organizations",
	"/api/v1/members/":             "organizations",
	"/api/v1/invite":               "organizations",
	"/api/v1/invite/":              "organizations",
}

// These endpoints are intentionally available to every authenticated user.
var authenticatedOnlyPaths = map[string]struct{}{
	"/api/v1/auth/logout":          {},
	"/api/v1/auth/change-password": {},
	"/api/v1/auth/profile":         {},
	"/api/v1/notify-settings":      {},
	"/api/v1/my/organizations":     {},
	// Self-service avatar upload: any authenticated user may update only
	// their own avatar; ownership is enforced by business-api.
	"/api/v1/upload/avatar": {},
	// Self-service profile change endpoints (email/phone change with code):
	// ownership and code verification are enforced by business-api.
	"/api/v1/auth/send-email-change-code": {},
	"/api/v1/auth/change-email":           {},
	"/api/v1/auth/send-phone-code":        {},
	"/api/v1/auth/change-phone":           {},
}

func isAuthenticatedOnlyPath(path string) bool {
	if _, ok := authenticatedOnlyPaths[path]; ok {
		return true
	}
	// Join request is a self-service operation: POST /api/v1/organizations/{id}/join
	// Any authenticated user may request to join an organization.
	if strings.HasPrefix(path, "/api/v1/organizations/") && strings.HasSuffix(path, "/join") {
		return true
	}
	return false
}

// appAllowedPaths defines APP-side endpoint whitelist.
var appAllowedExactPaths = map[string]struct{}{
	"/api/v1/ota/trigger":              {},
	"/api/v1/ota/app/check":            {},
	"/api/v1/ota/app/packages":         {},
	"/api/v1/ota/app/packages/install": {},
}

var appAllowedPrefixes = []string{
	"/api/v1/ota/check/",
	"/api/v1/ota/resend/",
	"/api/v1/ota/devices/",
	"/api/v1/ota/available-packages/",
}

var appAllowedMethodPaths = []struct {
	prefix string
	method string
}{
	{"/api/v1/stations", "POST"},
	// Channel organization members (non-system-admins) perform invitation
	// actions from the org-tree page; business rules (membership scope, role
	// hierarchy, inviter-only revoke) are enforced by business-api.
	{"/api/v1/invitations/create", "POST"},
	{"/api/v1/invitations", "DELETE"},
}

// basicUserGETPrefixes defines GET endpoints that any authenticated user may access
// without organization-level RBAC grants. Data scoping (showing only the user's
// own resources) is enforced by the downstream business-api service layer.
var basicUserGETPrefixes = []string{
	"/api/v1/stations",
	"/api/v1/devices",
	"/api/v1/device/",
	"/api/v1/alarms",
	"/api/v1/alerts",
	"/api/v1/alarm-events",
	"/api/v1/dashboard",
	"/api/v1/stats/",
	"/api/v1/notifications",
	"/api/v1/alert-rules",
	"/api/v1/ota/",
	"/api/v1/parallel",
	"/api/v1/parallel-groups",
	"/api/v1/work-orders",
	"/api/v1/work-order-stats",
	// 用户操作历史：按当前用户维度聚合，数据范围由 business-api 过滤
	"/api/v1/op-logs",
	// Organization tree / my-organizations / invitation records for the org
	// management page; subtree scoping is enforced by business-api.
	"/api/v1/organizations",
	"/api/v1/my",
	"/api/v1/invitations",
}

func isAppAllowedPath(path string) bool {
	if _, ok := appAllowedExactPaths[path]; ok {
		return true
	}
	for _, prefix := range appAllowedPrefixes {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

func isAppAllowedPathWithMethod(path, method string) bool {
	if isAppAllowedPath(path) {
		return true
	}
	for _, entry := range appAllowedMethodPaths {
		if entry.method == method && (path == entry.prefix || strings.HasPrefix(path, entry.prefix+"/")) {
			return true
		}
	}
	return false
}

// isSelfServiceDeviceOperation identifies device self-service operations that
// any authenticated user may initiate. Ownership/tenant checks are enforced by
// the downstream business-api service layer (bind only unbound devices,
// unbind/transfer only own devices, claim requires a valid claim code).
func isSelfServiceDeviceOperation(path, method string) bool {
	if method != http.MethodPost {
		return false
	}
	switch path {
	case "/api/v1/devices/bind", "/api/v1/devices/import-excel":
		return true
	}
	if strings.HasPrefix(path, "/api/v1/devices/claim-code/") {
		return true
	}
	const bySNPrefix = "/api/v1/devices/by-sn/"
	if strings.HasPrefix(path, bySNPrefix) {
		for _, suffix := range []string{"/unbind", "/request-unbind", "/claim", "/request-transfer"} {
			if strings.HasSuffix(path, suffix) {
				return true
			}
		}
	}
	return false
}

// isBasicUserGET checks whether the request is a GET to a common app endpoint
// that any authenticated user may access without org-level RBAC grants.
func isBasicUserGET(path, method string) bool {
	if method != http.MethodGet {
		return false
	}
	for _, prefix := range basicUserGETPrefixes {
		if path == prefix || strings.HasPrefix(path, prefix+"/") || strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

// isUserActive verifies the user account is still valid (not deleted/banned).
func (r *RBACMiddleware) isUserActive(ctx context.Context, userID string) bool {
	if r.pg == nil {
		return true // fail open when no DB configured (tests)
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil || uid <= 0 {
		return false
	}
	var exists bool
	err = r.pg.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND status = 1 AND deleted_at IS NULL)",
		uid).Scan(&exists)
	return err == nil && exists
}

func (r *RBACMiddleware) RBACGuard() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		if isPublicPath(path) {
			c.Next()
			return
		}

		userID := c.GetHeader("X-User-ID")
		if userID == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "认证上下文缺失"})
			c.Abort()
			return
		}
		if r.isTokenBlacklisted(c.Request.Context(), c.GetHeader("X-Token-JTI")) {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "token 已被撤销"})
			c.Abort()
			return
		}
		if r.isUserSessionRevoked(c.Request.Context(), userID, c.GetHeader("X-Session-ID"), c.GetHeader("X-Token-Issued-At")) {
			c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "用户会话已被撤销"})
			c.Abort()
			return
		}

		// System admins bypass all RBAC checks
		if isSystemAdmin(c) {
			c.Next()
			return
		}

		// Authentication self-service endpoints
		if isAuthenticatedOnlyPath(path) {
			c.Next()
			return
		}

		// APP endpoints do not require business RBAC, but still require an active account
		if isAppAllowedPathWithMethod(path, c.Request.Method) {
			if !r.isUserActive(c.Request.Context(), userID) {
				c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "账号不可用"})
				c.Abort()
				return
			}
			c.Next()
			return
		}

		// Basic user GET endpoints: any authenticated user can view their own data.
		// Data scoping is enforced by the downstream service layer.
		if isBasicUserGET(path, c.Request.Method) {
			if !r.isUserActive(c.Request.Context(), userID) {
				c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "账号不可用"})
				c.Abort()
				return
			}
			c.Next()
			return
		}

		// Device self-service operations (bind/unbind/claim/transfer): any
		// authenticated user may initiate them; ownership and tenant isolation
		// are enforced by the downstream service layer.
		if isSelfServiceDeviceOperation(path, c.Request.Method) {
			if !r.isUserActive(c.Request.Context(), userID) {
				c.JSON(http.StatusUnauthorized, gin.H{"code": 401, "message": "账号不可用"})
				c.Abort()
				return
			}
			c.Next()
			return
		}

		resource := resourceForPath(path)
		if resource == "" {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "权限策略缺失，拒绝访问",
			})
			c.Abort()
			return
		}

		permissionCode := r.buildPermissionCode(path, c.Request.Method, resource)
		if !r.hasPermissionCode(c, permissionCode) {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "权限不足，无法访问该资源",
			})
			c.Abort()
			return
		}
		if sn, ok := directDeviceSN(path); ok && !r.hasDeviceAccess(c.Request.Context(), userID, sn) {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "无权访问该设备",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// resourceForPath chooses the most specific matching prefix.
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

// buildPermissionCode constructs the permission code from path, method, and resource.
// Format: "{resource}:{action}" (e.g., "devices:view", "admin:manage")
func (r *RBACMiddleware) buildPermissionCode(path, method, resource string) string {
	// Admin endpoints require "manage" action
	if pathPrefixMatches(path, "/api/v1/admin/") {
		return "admin:manage"
	}
	// OTA lifecycle commands use "control" action
	if isOTAControlRequest(path, method) {
		return resource + ":control"
	}
	return resource + ":" + actionForRequest(method, path)
}

func actionForRequest(method, path string) string {
	if method == http.MethodPost {
		switch path {
		case "/api/v1/devices/batch/control",
			"/api/v1/devices/add-to-station",
			"/api/v1/devices/batch-assign-installer":
			return "edit"
		}
		if strings.HasPrefix(path, "/api/v1/devices/") &&
			(strings.HasSuffix(path, "/unbind") ||
				strings.HasSuffix(path, "/control") ||
				strings.HasSuffix(path, "/remove-from-station") ||
				strings.HasSuffix(path, "/assign-installer") ||
				strings.HasSuffix(path, "/approve") ||
				strings.HasSuffix(path, "/reject")) {
			return "edit"
		}
		if (strings.HasPrefix(path, "/api/v1/alarms/") || strings.HasPrefix(path, "/api/v1/alerts/")) &&
			(strings.HasSuffix(path, "/acknowledge") || strings.HasSuffix(path, "/ignore")) {
			return "edit"
		}
		if strings.HasPrefix(path, "/api/v1/work-orders/") &&
			(strings.HasSuffix(path, "/attachments") || strings.HasSuffix(path, "/escalate")) {
			return "edit"
		}
	}
	switch method {
	case http.MethodGet:
		return "view"
	case http.MethodPost:
		return "create"
	case http.MethodPut, http.MethodPatch:
		return "edit"
	case http.MethodDelete:
		return "delete"
	default:
		return "view"
	}
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

func (r *RBACMiddleware) isTokenBlacklisted(ctx context.Context, jti string) bool {
	if r.rdb == nil || strings.TrimSpace(jti) == "" {
		return false
	}
	checkCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	exists, err := r.rdb.Exists(checkCtx, "token_blacklist:"+jti).Result()
	return err != nil || exists > 0
}

func (r *RBACMiddleware) isUserSessionRevoked(ctx context.Context, userID, sessionID, issuedAt string) bool {
	if r.rdb == nil {
		return false
	}
	if strings.TrimSpace(sessionID) == "" && strings.TrimSpace(issuedAt) == "" {
		return false
	}
	if strings.TrimSpace(sessionID) == "" || strings.TrimSpace(issuedAt) == "" {
		return true
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil || uid <= 0 {
		return true
	}
	iat, err := strconv.ParseInt(issuedAt, 10, 64)
	if err != nil || iat <= 0 {
		return true
	}
	checkCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	exists, err := r.rdb.Exists(checkCtx, fmt.Sprintf("refresh_session:%d:%s", uid, sessionID)).Result()
	if err != nil || exists == 0 {
		return true
	}
	cutoff, err := r.rdb.Get(checkCtx, fmt.Sprintf("user_token_revoked_at:%d", uid)).Int64()
	if err == redis.Nil {
		return false
	}
	return err != nil || iat <= cutoff
}

func directDeviceSN(path string) (string, bool) {
	const prefix = "/api/v1/device/"
	if !strings.HasPrefix(path, prefix) {
		return "", false
	}
	remainder := strings.TrimPrefix(path, prefix)
	parts := strings.Split(remainder, "/")
	if len(parts) != 2 || parts[0] == "" || (parts[1] != "online" && parts[1] != "data") {
		return "", false
	}
	return parts[0], true
}

// hasDeviceAccess checks whether the user can access a specific device.
// System admins already bypassed in RBACGuard; this is for non-admin users.
func (r *RBACMiddleware) hasDeviceAccess(ctx context.Context, userID, sn string) bool {
	if r.pg == nil || sn == "" {
		return false
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil || uid <= 0 {
		return false
	}
	queryCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	var allowed bool
	// Check device access through organization memberships and device ownership
	err = r.pg.QueryRow(queryCtx, `
		SELECT EXISTS (
			SELECT 1
			FROM organization_memberships m
			JOIN role_permission_grants pg
			  ON pg.root_tenant_id = m.root_tenant_id
			 AND pg.role_assignment_id IN (
			    SELECT id FROM membership_role_assignments
			    WHERE root_tenant_id = m.root_tenant_id
			      AND organization_id = m.organization_id
			      AND membership_id = m.id
			 )
			WHERE m.user_id = $1 AND m.status = 'active'
			  AND pg.permission_code = 'devices:view'
			  AND pg.data_scope IN ('organization_and_descendants', 'organization', 'assigned_resources')
		) OR EXISTS (
			SELECT 1 FROM v_user_device_access
			WHERE user_id = $1 AND device_sn = $2
		)
	`, uid, sn).Scan(&allowed)
	return err == nil && allowed
}

// InvalidateUserPermissions clears the cached permissions for a user.
// Called when authorization_version changes (role/permission updates).
func (r *RBACMiddleware) InvalidateUserPermissions(userID, orgID, membershipID string) {
	cacheKey := fmt.Sprintf("gw:user_perms:%s:%s:%s", userID, orgID, membershipID)
	r.mu.Lock()
	delete(r.permCache, cacheKey)
	r.mu.Unlock()

	if r.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		r.rdb.Del(ctx, cacheKey)
	}
}

// InvalidateUserCache is kept for backward compatibility with admin handlers.
func (r *RBACMiddleware) InvalidateUserCache(userID string) {
	// Wildcard delete all org/membership-scoped entries for this user
	if r.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		pattern := fmt.Sprintf("gw:user_perms:%s:*", userID)
		iter := r.rdb.Scan(ctx, 0, pattern, 100).Iterator()
		for iter.Next(ctx) {
			r.rdb.Del(ctx, iter.Val())
		}
	}
	r.mu.Lock()
	for k := range r.permCache {
		if strings.HasPrefix(k, fmt.Sprintf("gw:user_perms:%s:", userID)) {
			delete(r.permCache, k)
		}
	}
	r.mu.Unlock()
}

// InvalidateRoleCache is kept for backward compatibility.
// In the new system, role changes trigger authorization_version bumps which
// invalidate per-user caches via InvalidateUserCache.
func (r *RBACMiddleware) InvalidateRoleCache(role int) {
	// No-op in the new system: permission changes are per-user, not per-role.
}

func ParseUserID(c *gin.Context) int64 {
	userIDStr := c.GetHeader("X-User-ID")
	if userIDStr == "" {
		return 0
	}
	userID, _ := strconv.ParseInt(userIDStr, 10, 64)
	return userID
}
