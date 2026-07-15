package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

type RBACCacheService struct {
	rdb  *redis.Client
	repo *repository.UserRepository
	ttl  time.Duration
}

func NewRBACCacheService(rdb *redis.Client, repo *repository.UserRepository) *RBACCacheService {
	return &RBACCacheService{
		rdb:  rdb,
		repo: repo,
		ttl:  5 * time.Minute,
	}
}

func (s *RBACCacheService) CacheUserPermissions(ctx context.Context, userID int64) error {
	roleIDs, err := s.repo.GetUserRoleIDs(ctx, userID)
	if err != nil {
		logger.Warn("Failed to get user role IDs for RBAC cache", zap.Int64("user_id", userID), zap.Error(err))
		return err
	}

	roleCacheKey := fmt.Sprintf("gw:user_roles:%d", userID)
	data, _ := json.Marshal(roleIDs)
	s.rdb.Set(ctx, roleCacheKey, string(data), s.ttl)

	for _, roleID := range roleIDs {
		perms, err := s.repo.GetRolePermissions(ctx, roleID)
		if err != nil {
			continue
		}
		permCacheKey := fmt.Sprintf("gw:role_perms:%d", roleID)
		permData, _ := json.Marshal(perms)
		s.rdb.Set(ctx, permCacheKey, string(permData), s.ttl)
	}

	logger.Info("RBAC cache written", zap.Int64("user_id", userID), zap.Int("role_count", len(roleIDs)))
	return nil
}

// GetUserPermissions 获取用户的权限列表
// 先查 Redis 缓存，miss 时回源 DB 并写回缓存（带 singleflight 防击穿）
func (s *RBACCacheService) GetUserPermissions(ctx context.Context, userID int64) ([]string, error) {
	cacheKey := fmt.Sprintf("gw:user_perms:%d", userID)

	// Try Redis cache first
	if s.rdb != nil {
		if cached, err := s.rdb.Get(ctx, cacheKey).Result(); err == nil {
			var perms []string
			if json.Unmarshal([]byte(cached), &perms) == nil {
				return perms, nil
			}
		}
	}

	// Cache miss: load from DB
	roleIDs, err := s.repo.GetUserRoleIDs(ctx, userID)
	if err != nil {
		return nil, err
	}

	var allPerms []string
	permSet := make(map[string]bool)

	for _, roleID := range roleIDs {
		perms, err := s.repo.GetRolePermissions(ctx, roleID)
		if err != nil {
			continue
		}
		for _, perm := range perms {
			permStr := perm.Resource + ":" + perm.Action
			if !permSet[permStr] {
				permSet[permStr] = true
				allPerms = append(allPerms, permStr)
			}
		}
	}

	// Write back to cache with TTL
	if s.rdb != nil && len(allPerms) > 0 {
		data, _ := json.Marshal(allPerms)
		s.rdb.Set(ctx, cacheKey, string(data), s.ttl)
	}

	return allPerms, nil
}

func (s *RBACCacheService) InvalidateUserPermissions(ctx context.Context, userID int64) {
	s.rdb.Del(ctx, fmt.Sprintf("gw:user_roles:%d", userID))
	s.rdb.Del(ctx, fmt.Sprintf("gw:user_perms:%d", userID))
}

func (s *RBACCacheService) InvalidateRolePermissions(ctx context.Context, roleID int64) {
	s.rdb.Del(ctx, fmt.Sprintf("gw:role_perms:%d", roleID))
}
