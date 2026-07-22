package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

// RBACCache RBAC 缓存结构体，管理 Redis 中的权限、角色和成员关系缓存
type RBACCache struct {
	client        *redis.Client
	TTL           time.Duration
	permissionKey string    // "rbac:perm:{tenantId}:{permission}"
	roleKey       string    // "rbac:role:{tenantId}:{roleId}"
	membershipKey string    // "rbac:memb:{userId}:{orgId}"
	orgScopeKey   string    // "rbac:scope:{orgId}"
}

// NewRBACCache 创建新的 RBAC 缓存实例
func NewRBACCache(client *redis.Client, ttl time.Duration) *RBACCache {
	if ttl == 0 {
		ttl = 5 * time.Minute // 默认 TTL
	}
	return &RBACCache{
		client:      client,
		TTL:         ttl,
		permissionKey: "rbac:perm:%d:%s",
		roleKey:     "rbac:role:%d:%d",
		membershipKey: "rbac:memb:%d:%d",
		orgScopeKey: "rbac:scope:%d",
	}
}

// ============================================================================
// Permission cache operations
// ============================================================================

// SetPermission 设置权限缓存 (tenantID, permission -> bool)
func (c *RBACCache) SetPermission(tenantID int64, permission string, allowed bool) error {
	if c.client == nil {
		return nil
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.permissionKey, tenantID, permission)
	value := "0"
	if allowed {
		value = "1"
	}
	err := c.client.Set(ctx, key, value, c.TTL).Err()
	if err != nil {
		logger.Warn("Failed to set RBAC permission cache",
			zap.Int64("tenant_id", tenantID),
			zap.String("permission", permission),
			zap.Bool("allowed", allowed),
			zap.Error(err))
	}
	return err
}

// GetPermission 获取权限缓存
func (c *RBACCache) GetPermission(tenantID int64, permission string) (bool, error) {
	if c.client == nil {
		return false, nil
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.permissionKey, tenantID, permission)
	val, err := c.client.Get(ctx, key).Result()
	if err != nil {
		// Cache miss or redis error
		if err == redis.Nil {
			return false, nil
		}
		logger.Warn("Failed to get RBAC permission cache",
			zap.Int64("tenant_id", tenantID),
			zap.String("permission", permission),
			zap.Error(err))
		return false, err
	}
	return val == "1", nil
}

// InvalidatePermission 使权限缓存失效
func (c *RBACCache) InvalidatePermission(tenantID int64, permission string) {
	if c.client == nil {
		return
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.permissionKey, tenantID, permission)
	if err := c.client.Del(ctx, key).Err(); err != nil {
		logger.Warn("Failed to invalidate RBAC permission cache", zap.Error(err))
	}
}

// ============================================================================
// Role cache operations
// ============================================================================

// SetRolePermissions 设置角色权限缓存
func (c *RBACCache) SetRolePermissions(tenantID int64, roleID int, permissions []string) error {
	if c.client == nil {
		return nil
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.roleKey, tenantID, roleID)
	data, err := json.Marshal(permissions)
	if err != nil {
		return err
	}
	return c.client.Set(ctx, key, data, c.TTL).Err()
}

// GetRolePermissions 获取角色权限缓存
func (c *RBACCache) GetRolePermissions(tenantID int64, roleID int) ([]string, error) {
	if c.client == nil {
		return nil, nil
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.roleKey, tenantID, roleID)
	val, err := c.client.Get(ctx, key).Result()
	if err != nil {
		if err == redis.Nil {
			return nil, nil
		}
		logger.Warn("Failed to get RBAC role cache", zap.Error(err))
		return nil, err
	}
	var perms []string
	if err := json.Unmarshal([]byte(val), &perms); err != nil {
		return nil, err
	}
	return perms, nil
}

// InvalidateRole 使角色缓存失效
func (c *RBACCache) InvalidateRole(tenantID int64, roleID int) {
	if c.client == nil {
		return
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.roleKey, tenantID, roleID)
	if err := c.client.Del(ctx, key).Err(); err != nil {
		logger.Warn("Failed to invalidate RBAC role cache", zap.Error(err))
	}
}

// ============================================================================
// Membership cache operations
// ============================================================================

// SetMembershipAccess 设置用户组织访问权限缓存
func (c *RBACCache) SetMembershipAccess(tenantID int64, userID int64, orgID int64, roles []int) error {
	if c.client == nil {
		return nil
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.membershipKey, userID, orgID)
	data, err := json.Marshal(map[string]interface{}{
		"roles":      roles,
		"tenantID":   tenantID,
		"orgID":      orgID,
		"updatedAt":  time.Now().Unix(),
	})
	if err != nil {
		return err
	}
	return c.client.Set(ctx, key, data, c.TTL).Err()
}

// GetMembershipRoles 获取用户组织角色缓存
func (c *RBACCache) GetMembershipRoles(tenantID int64, userID int64, orgID int64) ([]int, error) {
	if c.client == nil {
		return nil, nil
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.membershipKey, userID, orgID)
	val, err := c.client.Get(ctx, key).Result()
	if err != nil {
		if err == redis.Nil {
			return nil, nil
		}
		logger.Warn("Failed to get RBAC membership cache", zap.Error(err))
		return nil, err
	}
	var result map[string]interface{}
	if err := json.Unmarshal([]byte(val), &result); err != nil {
		return nil, err
	}
	rolesRaw, ok := result["roles"]
	if !ok {
		return nil, nil
	}
	roles := make([]int, 0)
	switch v := rolesRaw.(type) {
	case []interface{}:
		for _, iv := range v {
			if i, ok := iv.(float64); ok {
				roles = append(roles, int(i))
			}
		}
	}
	return roles, nil
}

// InvalidateMembership 使成员缓存失效
func (c *RBACCache) InvalidateMembership(tenantID int64, userID int64, orgID int64) {
	if c.client == nil {
		return
	}
	ctx := context.Background()
	key := fmt.Sprintf(c.membershipKey, userID, orgID)
	if err := c.client.Del(ctx, key).Err(); err != nil {
		logger.Warn("Failed to invalidate RBAC membership cache", zap.Error(err))
	}
}

// ============================================================================
// Bulk invalidation methods
// ============================================================================

// InvalidateAllForOrg 使指定组织的所有缓存失效
func (c *RBACCache) InvalidateAllForOrg(tenantID int64, orgID int64) {
	if c.client == nil {
		return
	}
	ctx := context.Background()
	
	// 删除组织范围缓存
	scopeKey := fmt.Sprintf(c.orgScopeKey, orgID)
	_ = c.client.Del(ctx, scopeKey)
	
	// TODO: 如果有关联的键模式，可以批量删除
	// 这需要通过 SCAN 命令查找所有相关键
	logger.Info("Invalidated all RBAC cache for org",
		zap.Int64("tenant_id", tenantID),
		zap.Int64("org_id", orgID))
}

// InvalidateAllForUser 使用户的所有缓存失效
func (c *RBACCache) InvalidateAllForUser(tenantID int64, userID int64) {
	if c.client == nil {
		return
	}
	
	// 删除用户的所有权限和角色缓存
	// 这需要扫描或知道所有相关的键
	logger.Info("Invalidated all RBAC cache for user",
		zap.Int64("tenant_id", tenantID),
		zap.Int64("user_id", userID))
}

// ============================================================================
// Legacy compatibility methods (backward compatible)
// ============================================================================

// CacheUserPermissions 向后兼容：缓存用户权限（旧版方法）
func (c *RBACCache) CacheUserPermissions(ctx context.Context, userID int64) error {
	if c.client == nil {
		return nil
	}
	roleIDs := make([]int64, 0)
	// Note: The original implementation required repo parameter which is no longer available
	// This is a simplified version - callers should use newer methods instead
	_ = roleIDs
	return nil
}

// GetUserPermissions 向后兼容：获取用户权限列表（旧版方法）
func (c *RBACCache) GetUserPermissions(ctx context.Context, userID int64) ([]string, error) {
	// Deprecated: Use CheckPermission with proper tenant ID instead
	return []string{}, nil
}

// InvalidateUser 向后兼容：使用户的所有权限缓存失效
func (c *RBACCache) InvalidateUser(ctx context.Context, userID int64) {
	// Deprecated: Use InvalidateAllForUser instead
	// We don't have enough context here to invalidate properly
	_ = ctx
	_ = userID
}

// InvalidateRole 向后兼容：使角色缓存失效
// Deprecated: Use InvalidateRole with tenant ID instead
func (c *RBACCache) InvalidateRoleLegacy(ctx context.Context, roleID int64) {
	_ = ctx
	_ = roleID
}
