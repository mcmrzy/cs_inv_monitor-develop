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

const permCachePrefix = "gw:user_perms:"

type permCacheEntry struct {
	codes    []string
	loadedAt time.Time
}

// PermChecker resolves permission codes from the organization-based permission
// system (membership_role_assignments + role_permission_grants). It replaces
// the legacy numeric-role permission checks.
type PermChecker struct {
	rdb      *redis.Client
	userRepo *repository.UserRepository
	cacheTTL time.Duration
	mu       sync.RWMutex
	memCache map[string]permCacheEntry
}

func NewPermChecker(rdb *redis.Client, userRepo *repository.UserRepository) *PermChecker {
	return &PermChecker{
		rdb:      rdb,
		userRepo: userRepo,
		cacheTTL: 5 * time.Minute,
		memCache: make(map[string]permCacheEntry),
	}
}

// CheckPermission reports whether the user holds the given "resource:action"
// permission code through the organization-based permission system.
func (c *PermChecker) CheckPermission(userID int64, resource string, action string) bool {
	if userID <= 0 {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	codes, err := c.loadUserPermissionCodes(ctx, userID)
	if err != nil {
		logger.Error("PermChecker: loadUserPermissionCodes failed",
			zap.Int64("user_id", userID), zap.Error(err))
		return false
	}

	needle := resource + ":" + action
	for _, code := range codes {
		if code == needle {
			return true
		}
	}
	return false
}

func (c *PermChecker) loadUserPermissionCodes(ctx context.Context, userID int64) ([]string, error) {
	cacheKey := permCachePrefix + fmt.Sprintf("%d", userID)

	if c.rdb != nil {
		cached, err := c.rdb.Get(ctx, cacheKey).Result()
		if err == nil {
			var codes []string
			if err := json.Unmarshal([]byte(cached), &codes); err == nil {
				c.mu.Lock()
				c.memCache[cacheKey] = permCacheEntry{codes: codes, loadedAt: time.Now()}
				c.mu.Unlock()
				return codes, nil
			}
		}
		// Redis deletion is the invalidation signal shared with the admin and
		// gateway processes. Never fall back to stale process memory after a miss.
		return c.refreshUserPermissionCodes(ctx, userID)
	}

	c.mu.RLock()
	if entry, ok := c.memCache[cacheKey]; ok && time.Since(entry.loadedAt) < c.cacheTTL {
		c.mu.RUnlock()
		return entry.codes, nil
	}
	c.mu.RUnlock()

	return c.refreshUserPermissionCodes(ctx, userID)
}

func (c *PermChecker) refreshUserPermissionCodes(ctx context.Context, userID int64) ([]string, error) {
	cacheKey := permCachePrefix + fmt.Sprintf("%d", userID)

	codes, err := c.userRepo.GetUserPermissionCodes(ctx, userID)
	if err != nil {
		return nil, err
	}

	if c.rdb != nil {
		data, _ := json.Marshal(codes)
		c.rdb.Set(ctx, cacheKey, string(data), c.cacheTTL)
	}

	c.mu.Lock()
	c.memCache[cacheKey] = permCacheEntry{codes: codes, loadedAt: time.Now()}
	c.mu.Unlock()

	return codes, nil
}

// InvalidateUser drops the cached permission codes for a user. It is called
// after membership/role/grant changes so the next check re-reads the database.
func (c *PermChecker) InvalidateUser(userID int64) {
	key := permCachePrefix + fmt.Sprintf("%d", userID)
	c.mu.Lock()
	delete(c.memCache, key)
	c.mu.Unlock()
	if c.rdb != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		c.rdb.Del(ctx, key)
	}
}
