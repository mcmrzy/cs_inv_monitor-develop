package service

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const prefix = "gw:role_perms:"

type permCacheEntry struct {
	perms     []repository.PermissionEntry
	loadedAt  time.Time
}

type PermChecker struct {
	rdb       *redis.Client
	userRepo  *repository.UserRepository
	cacheTTL  time.Duration
	mu        sync.RWMutex
	memCache  map[string]permCacheEntry
}

func NewPermChecker(rdb *redis.Client, userRepo *repository.UserRepository) *PermChecker {
	return &PermChecker{
		rdb:       rdb,
		userRepo:  userRepo,
		cacheTTL:  5 * time.Minute,
		memCache:  make(map[string]permCacheEntry),
	}
}

func (c *PermChecker) CheckPermission(userID int64, resource string, action string) bool {
	if userID <= 0 {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	roleIDs, err := c.loadUserRoles(ctx, userID)
	if err != nil {
		logger.Error("PermChecker: loadUserRoles failed",
			zap.Int64("user_id", userID), zap.Error(err))
		return false
	}

	for _, roleID := range roleIDs {
		if roleID == 0 {
			return true
		}

		perms, err := c.loadRolePerms(ctx, roleID)
		if err != nil {
			continue
		}

		if includesPermission(perms, resource, action) {
			return true
		}

		// An additive migration can make a shared Redis entry incomplete. Refresh
		// the authoritative table before denying so a pre-migration cache never
		// causes a user to remain locked out for the cache TTL.
		perms, err = c.refreshRolePerms(ctx, roleID)
		if err == nil && includesPermission(perms, resource, action) {
			return true
		}
	}

	return false
}

func (c *PermChecker) loadUserRoles(ctx context.Context, userID int64) ([]int64, error) {
	cacheKey := fmt.Sprintf("gw:user_roles:%d", userID)

	if c.rdb != nil {
		cached, err := c.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var roleIDs []int64
			if err := json.Unmarshal([]byte(cached), &roleIDs); err == nil {
				return roleIDs, nil
			}
		}
	}

	roleIDs, err := c.userRepo.GetUserRoleIDs(ctx, userID)
	if err != nil {
		logger.Warn("PermChecker: GetUserRoleIDs failed, falling back to user.Role",
			zap.Int64("user_id", userID), zap.Error(err))
		roleIDs = nil
	}

	if len(roleIDs) == 0 {
		user, err := c.userRepo.GetByID(ctx, userID)
		if err != nil {
			return nil, err
		}
		if user != nil {
			roleIDs = []int64{int64(user.Role)}
		}
	}

	if c.rdb != nil && len(roleIDs) > 0 {
		data, _ := json.Marshal(roleIDs)
		c.rdb.Set(ctx, cacheKey, string(data), c.cacheTTL)
	}

	return roleIDs, nil
}

func (c *PermChecker) loadRolePerms(ctx context.Context, roleID int64) ([]repository.PermissionEntry, error) {
	cacheKey := prefix + fmt.Sprintf("%d", roleID)

	if c.rdb != nil {
		cached, err := c.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var perms []repository.PermissionEntry
			if err := json.Unmarshal([]byte(cached), &perms); err == nil {
				c.mu.Lock()
				c.memCache[cacheKey] = permCacheEntry{perms: perms, loadedAt: time.Now()}
				c.mu.Unlock()
				return perms, nil
			}
		}
		// Redis deletion is the invalidation signal shared with the admin and
		// gateway processes. Never fall back to stale process memory after a miss.
		return c.refreshRolePerms(ctx, roleID)
	}

	c.mu.RLock()
	if entry, ok := c.memCache[cacheKey]; ok && time.Since(entry.loadedAt) < c.cacheTTL {
		c.mu.RUnlock()
		return entry.perms, nil
	}
	c.mu.RUnlock()

	return c.refreshRolePerms(ctx, roleID)
}

func (c *PermChecker) refreshRolePerms(ctx context.Context, roleID int64) ([]repository.PermissionEntry, error) {
	cacheKey := prefix + fmt.Sprintf("%d", roleID)

	perms, err := c.userRepo.GetRolePermissions(ctx, roleID)
	if err != nil {
		return nil, err
	}

	if c.rdb != nil {
		data, _ := json.Marshal(perms)
		c.rdb.Set(ctx, cacheKey, string(data), c.cacheTTL)
	}

	c.mu.Lock()
	c.memCache[cacheKey] = permCacheEntry{perms: perms, loadedAt: time.Now()}
	c.mu.Unlock()

	return perms, nil
}

func includesPermission(perms []repository.PermissionEntry, resource, action string) bool {
	for _, p := range perms {
		if p.Resource == resource && p.Action == action {
			return true
		}
	}
	return false
}

func (c *PermChecker) InvalidateUser(userID int64) {
	if c.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		c.rdb.Del(ctx, fmt.Sprintf("gw:user_roles:%d", userID))
	}
}

func (c *PermChecker) InvalidateRole(roleID int64) {
	key := prefix + fmt.Sprintf("%d", roleID)
	c.mu.Lock()
	delete(c.memCache, key)
	c.mu.Unlock()
	if c.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		c.rdb.Del(ctx, key)
	}
}
