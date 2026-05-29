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

type PermChecker struct {
	rdb       *redis.Client
	userRepo  *repository.UserRepository
	cacheTTL  time.Duration
	mu        sync.RWMutex
	memCache  map[string][]repository.PermissionEntry
}

func NewPermChecker(rdb *redis.Client, userRepo *repository.UserRepository) *PermChecker {
	return &PermChecker{
		rdb:       rdb,
		userRepo:  userRepo,
		cacheTTL:  5 * time.Minute,
		memCache:  make(map[string][]repository.PermissionEntry),
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
		if roleID == 1 {
			return true
		}

		perms, err := c.loadRolePerms(ctx, roleID)
		if err != nil {
			continue
		}

		for _, p := range perms {
			if p.Resource == resource && p.Action == action {
				return true
			}
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
		return nil, err
	}

	if c.rdb != nil && len(roleIDs) > 0 {
		data, _ := json.Marshal(roleIDs)
		c.rdb.Set(ctx, cacheKey, string(data), c.cacheTTL)
	}

	return roleIDs, nil
}

func (c *PermChecker) loadRolePerms(ctx context.Context, roleID int64) ([]repository.PermissionEntry, error) {
	cacheKey := prefix + fmt.Sprintf("%d", roleID)

	c.mu.RLock()
	if cached, ok := c.memCache[cacheKey]; ok {
		c.mu.RUnlock()
		return cached, nil
	}
	c.mu.RUnlock()

	if c.rdb != nil {
		cached, err := c.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var perms []repository.PermissionEntry
			if err := json.Unmarshal([]byte(cached), &perms); err == nil {
				c.mu.Lock()
				c.memCache[cacheKey] = perms
				c.mu.Unlock()
				return perms, nil
			}
		}
	}

	perms, err := c.userRepo.GetRolePermissions(ctx, roleID)
	if err != nil {
		return nil, err
	}

	if c.rdb != nil {
		data, _ := json.Marshal(perms)
		c.rdb.Set(ctx, cacheKey, string(data), c.cacheTTL)
	}

	c.mu.Lock()
	c.memCache[cacheKey] = perms
	c.mu.Unlock()

	return perms, nil
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
