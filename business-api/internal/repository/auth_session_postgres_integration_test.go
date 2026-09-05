//go:build integration

package repository

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 认证会话上下文与 RBAC 权限码真库回归：
// 1. ResolveDefaultSessionContext 必须把 users.is_system_admin 带入会话上下文
//    （登录后 JWT 的 is_system_admin claim 数据源；2026-09 超管判定链回归）
// 2. 无组织成员关系的纯超管账号返回 ErrNoRows，由调用方回退系统级上下文
// 3. GetUserPermissionCodes 只聚合 active 成员关系的授权（PermChecker 的数据源）

func TestResolveDefaultSessionContextCarriesSystemAdminFlag(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	seedSessionContextUsers(t, pool)

	repo := NewAuthorizationRepository(pool)

	adminCtx, err := repo.ResolveDefaultSessionContext(ctx, 310)
	require.NoError(t, err)
	assert.True(t, adminCtx.IsSystemAdmin, "is_system_admin 必须进入会话上下文")
	assert.Equal(t, "sa-310", adminCtx.Phone)
	assert.Equal(t, int64(310), adminCtx.Actor.UserID)

	userCtx, err := repo.ResolveDefaultSessionContext(ctx, 311)
	require.NoError(t, err)
	assert.False(t, userCtx.IsSystemAdmin, "普通用户不得误标超管")

	// 无成员关系的超管：调用方依赖 ErrNoRows 回退系统级上下文
	_, err = repo.ResolveDefaultSessionContext(ctx, 312)
	assert.True(t, errors.Is(err, pgx.ErrNoRows), "无成员关系的账号应返回 ErrNoRows 而非静默给空上下文")
}

func TestGetUserPermissionCodesReflectsActiveGrants(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	seedSessionContextUsers(t, pool)

	// user 313 挂在 active 成员关系下带两条授权；user 314 的成员关系为 disabled
	_, err := pool.Exec(ctx, `
		INSERT INTO membership_role_assignments(id, root_tenant_id, organization_id, membership_id, role_code, status) VALUES
			(4111, 410, 411, 4103, 'agent', 'active'),
			(4112, 410, 411, 4104, 'agent', 'active');
		INSERT INTO role_permission_grants(root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope, scope_definition) VALUES
			(410, 411, 4111, 'devices:control', 'organization_and_descendants', '{}'::jsonb),
			(410, 411, 4111, 'station:view', 'organization_and_descendants', '{}'::jsonb),
			(410, 411, 4112, 'devices:control', 'organization_and_descendants', '{}'::jsonb);
	`)
	require.NoError(t, err)

	userRepo := NewUserRepository(pool, nil)

	codes, err := userRepo.GetUserPermissionCodes(ctx, 313)
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"devices:control", "station:view"}, codes)

	// disabled 成员关系的授权不得泄入
	codes314, err := userRepo.GetUserPermissionCodes(ctx, 314)
	require.NoError(t, err)
	assert.Empty(t, codes314, "disabled 成员关系的授权必须被排除")
}

func seedSessionContextUsers(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO users(id, phone, password_hash, is_system_admin, status) VALUES
			(310, 'sa-310', 'hash', true, 1),
			(311, 'u-311', 'hash', false, 1),
			(312, 'sa-312', 'hash', true, 1),
			(313, 'u-313', 'hash', false, 1),
			(314, 'u-314', 'hash', false, 1);
		INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, code, name, status) VALUES
			(410, 410, NULL, 'manufacturer', 'CTX-M', 'Ctx Manufacturer', 'active'),
			(411, 410, 410, 'agent', 'CTX-A', 'Ctx Agent', 'active');
		INSERT INTO organization_memberships(id, root_tenant_id, organization_id, user_id, status, version) VALUES
			(4101, 410, 411, 310, 'active', 1),
			(4102, 410, 411, 311, 'active', 1),
			(4103, 410, 411, 313, 'active', 1),
			(4104, 410, 411, 314, 'disabled', 1);
	`)
	require.NoError(t, err)
}
