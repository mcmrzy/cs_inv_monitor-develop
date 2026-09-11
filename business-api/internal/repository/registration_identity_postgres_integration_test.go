//go:build integration

package repository

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

// setupIdentityTestDB 为注册身份测试创建独立临时库并加载 squash schema。
func setupIdentityTestDB(t *testing.T) (*pgxpool.Pool, func()) {
	t.Helper()
	ctx := context.Background()
	host := envOrFallback("TEST_DB_HOST", "localhost")
	port := envOrFallback("TEST_DB_PORT", "15432")
	user := envOrFallback("TEST_DB_USER", "testuser")
	password := envOrFallback("TEST_DB_PASSWORD", "testpass")
	admin, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable", user, password, host, port))
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))

	dbName := fmt.Sprintf("reg_identity_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err)
	pool, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, password, host, port, dbName))
	require.NoError(t, err)

	repoRoot := filepath.Clean(filepath.Join("..", "..", ".."))
	schemaBytes, err := os.ReadFile(filepath.Join(repoRoot, "database", "schema.sql"))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(schemaBytes))
	require.NoError(t, err, "load schema.sql")

	// manufacturer 根组织（id=root_tenant_id，closure/tenant_roots 由触发器维护）
	_, err = pool.Exec(ctx, `
		INSERT INTO organizations (id, root_tenant_id, parent_id, org_type, name, status)
		VALUES (9100, 9100, NULL, 'manufacturer', 'Test Manufacturer', 'active')
	`)
	require.NoError(t, err)

	// admin 连接池由 cleanup 末尾关闭：先断开测试库连接再删库
	return pool, func() {
		pool.Close()
		_, _ = admin.Exec(ctx, `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1`, dbName)
		_, dropErr := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+dbName)
		assert.NoError(t, dropErr)
		admin.Close()
	}
}

func execMigrationFile(t *testing.T, pool *pgxpool.Pool, name string) {
	t.Helper()
	repoRoot := filepath.Clean(filepath.Join("..", "..", ".."))
	content, err := os.ReadFile(filepath.Join(repoRoot, "database", "migrations", name))
	require.NoError(t, err)
	_, err = pool.Exec(context.Background(), string(content))
	require.NoError(t, err, "execute migration %s", name)
}

// assertCustomerIdentity 断言用户拥有完整的个人 customer 组织身份：
// customer 组织（code 标记）+ 活跃 membership + customer 角色分配 +
// RoleDefaultPermissions["customer"] 全量授权。
// expectedParent：个人组织应当挂靠的父组织 id——现行注册路径是共享「用户组织」，
// 迁移 107 回填路径是 manufacturer 根组织。
// expectedRootTenant：个人组织与父组织所属的根租户。
func assertCustomerIdentity(t *testing.T, pool *pgxpool.Pool, userID, expectedParent, expectedRootTenant int64) {
	t.Helper()
	ctx := context.Background()

	var orgID, membershipID int64
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT o.id, m.id
		FROM organization_memberships m
		JOIN organizations o ON o.root_tenant_id = m.root_tenant_id AND o.id = m.organization_id
		WHERE m.user_id = $1 AND m.status = 'active'
		  AND o.org_type = 'customer' AND o.deleted_at IS NULL
	`, userID).Scan(&orgID, &membershipID), "user %d must have an active customer org membership", userID)

	var orgCode string
	var parentID, rootTenantID int64
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT code, parent_id, root_tenant_id FROM organizations WHERE id = $1
	`, orgID).Scan(&orgCode, &parentID, &rootTenantID))
	assert.Equal(t, fmt.Sprintf("personal-%d", userID), orgCode, "personal org must be tagged with code")
	assert.Equal(t, expectedParent, parentID, "personal org parent must match the expected anchor")
	assert.Equal(t, expectedRootTenant, rootTenantID, "personal org must live in the shared root tenant")

	var roleCode, roleStatus string
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT ra.role_code, ra.status
		FROM membership_role_assignments ra
		WHERE ra.membership_id = $1 AND ra.status = 'active'
	`, membershipID).Scan(&roleCode, &roleStatus))
	assert.Equal(t, "customer", roleCode)
	assert.Equal(t, "active", roleStatus)

	var grantCount int
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM role_permission_grants pg
		JOIN membership_role_assignments ra ON ra.id = pg.role_assignment_id
		WHERE ra.membership_id = $1
	`, membershipID).Scan(&grantCount))
	assert.Equal(t, len(RoleDefaultPermissions["customer"]), grantCount,
		"grants must match RoleDefaultPermissions[customer]")

	var closureDepth int
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT depth FROM organization_closure
		WHERE root_tenant_id = $1 AND ancestor_id = $2 AND descendant_id = $3
	`, expectedRootTenant, expectedParent, orgID).Scan(&closureDepth))
	assert.Equal(t, 1, closureDepth, "personal org must be a direct child of its parent org")
}

// sharedUsersOrgID 返回共享「用户组织」的 id，不存在时 fail。
func sharedUsersOrgID(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var orgID int64
	require.NoError(t, pool.QueryRow(context.Background(), `
		SELECT id FROM organizations
		WHERE LOWER(code) = 'default-users' AND deleted_at IS NULL
		ORDER BY id LIMIT 1
	`).Scan(&orgID), "shared users org must exist")
	return orgID
}

func TestCreateUserWithOrgIdentityGrantsCustomerBaseline(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()

	repo := NewUserRepository(pool, nil)
	user := &model.User{
		Email:        "register-test@example.com",
		PasswordHash: "$2a$10$examplehash",
		Nickname:     "Register Tester",
		Status:       1,
	}
	require.NoError(t, repo.CreateUserWithOrgIdentity(context.Background(), user))
	assert.NotZero(t, user.ID)
	// 个人组织挂在共享「用户组织」之下，根租户是系统制造商根组织
	assertCustomerIdentity(t, pool, user.ID, sharedUsersOrgID(t, pool), 9100)

	// 权限码与登录链路（GetUserPermissionCodes）一致
	codes, err := repo.GetUserPermissionCodes(context.Background(), user.ID)
	require.NoError(t, err)
	assert.ElementsMatch(t, RoleDefaultPermissions["customer"], codes)
}

// 共享父组织不等于共享数据可见范围：两个自助注册用户的组织必须互为兄弟，
// 组织闭包不能让他们互相看到对方的电站。
func TestSharedUsersOrgKeepsCustomersIsolated(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()
	ctx := context.Background()

	repo := NewUserRepository(pool, nil)
	first := &model.User{Email: "first@example.com", PasswordHash: "hash", Nickname: "First", Status: 1}
	second := &model.User{Email: "second@example.com", PasswordHash: "hash", Nickname: "Second", Status: 1}
	require.NoError(t, repo.CreateUserWithOrgIdentity(ctx, first))
	require.NoError(t, repo.CreateUserWithOrgIdentity(ctx, second))

	var firstOrg, secondOrg int64
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT organization_id FROM organization_memberships WHERE user_id = $1 AND status = 'active'
	`, first.ID).Scan(&firstOrg))
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT organization_id FROM organization_memberships WHERE user_id = $1 AND status = 'active'
	`, second.ID).Scan(&secondOrg))
	require.NotEqual(t, firstOrg, secondOrg, "each customer must keep its own org")
	assert.Equal(t, sharedUsersOrgID(t, pool), orgParent(t, pool, firstOrg))
	assert.Equal(t, sharedUsersOrgID(t, pool), orgParent(t, pool, secondOrg))

	// first 拥有一个电站，second 不能通过组织闭包访问到
	_, err := pool.Exec(ctx, `
		INSERT INTO stations (user_id, name, province, city, address, capacity)
		VALUES ($1, 'First Station', '湖南省', '长沙市', '麓谷', 10.0)
	`, first.ID)
	require.NoError(t, err)

	var leaked bool
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM v_user_station_access v
			JOIN stations s ON s.id = v.station_id
			WHERE v.user_id = $1 AND s.user_id = $2
		)
	`, second.ID, first.ID).Scan(&leaked))
	assert.False(t, leaked, "sharing the parent org must not leak stations between customers")
}

// 生产上见过这样的形态：库里存在 manufacturer 组织，但 tenant_roots 里没有对应
// 行。此时若不 JOIN tenant_roots，就会选中一个"未注册"的根租户，建子组织时被
// trg_organizations_insert_relations 以 "root tenant N is not registered" (23503)
// 拒绝——迁移 115 首次上生产就是这么炸的。
func TestSharedUsersOrgSkipsUnregisteredRootTenant(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()
	ctx := context.Background()

	// 造一个 root_tenant_id 更低、但没有 tenant_roots 行的 manufacturer 组织。
	// INSERT 触发器会自动登记 tenant_roots + 自闭包，这里按
	// closure → tenant_roots 顺序清掉（closure 受 guard，需走逃生舱）。
	_, err := pool.Exec(ctx, `
		INSERT INTO organizations (id, root_tenant_id, parent_id, org_type, name, status)
		VALUES (9001, 9001, NULL, 'manufacturer', 'Unregistered Root', 'active')
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		SET app.allow_closure_write = 'true';
		DELETE FROM organization_closure WHERE root_tenant_id = 9001;
		RESET app.allow_closure_write;
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM tenant_roots WHERE root_tenant_id = 9001`)
	require.NoError(t, err)

	// 前置确认：它确实没有 tenant_roots 行，且 id 比已注册的 9100 更低
	var registered bool
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM tenant_roots WHERE root_tenant_id = 9001)`).Scan(&registered))
	require.False(t, registered, "test precondition: 9001 must be unregistered")

	repo := NewUserRepository(pool, nil)
	rootTenantID, _, err := repo.EnsureSharedUsersOrg(ctx)
	require.NoError(t, err, "must not pick an unregistered root tenant")
	assert.Equal(t, int64(9100), rootTenantID, "must pick the registered manufacturer root")
}

func orgParent(t *testing.T, pool *pgxpool.Pool, orgID int64) int64 {
	t.Helper()
	var parentID int64
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT parent_id FROM organizations WHERE id = $1`, orgID).Scan(&parentID))
	return parentID
}

func TestEnsureUserOrgIdentityIdempotent(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()

	repo := NewUserRepository(pool, nil)
	user := &model.User{
		Email:        "idempotent-test@example.com",
		PasswordHash: "$2a$10$examplehash",
		Nickname:     "Idempotent Tester",
		Status:       1,
	}
	require.NoError(t, repo.CreateUserWithOrgIdentity(context.Background(), user))

	// 已有身份时再次补建必须无副作用
	require.NoError(t, repo.EnsureUserOrgIdentity(context.Background(), user.ID, user.Nickname))
	var membershipCount int
	require.NoError(t, pool.QueryRow(context.Background(), `
		SELECT COUNT(*) FROM organization_memberships WHERE user_id = $1
	`, user.ID).Scan(&membershipCount))
	assert.Equal(t, 1, membershipCount)
}

func TestMigration107BackfillsOrphanUsers(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()
	ctx := context.Background()

	// 两个孤儿用户（模拟迁移前的自助注册残留）+ 一个已有组织身份的用户
	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, phone, email, password_hash, nickname, status) VALUES
			(9201, '13800009201', 'orphan1@example.com', 'hash', 'Orphan One', 1),
			(9202, NULL, 'orphan2@example.com', 'hash', '', 1)
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO organizations (id, root_tenant_id, parent_id, org_type, name, status)
		VALUES (9210, 9100, 9100, 'customer', 'Existing Org', 'active')
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO users (id, phone, password_hash, nickname, status)
		VALUES (9203, '13800009203', 'hash', 'Existing Member', 1)
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
		VALUES (9100, 9210, 9203, 'active')
	`)
	require.NoError(t, err)

	// 生产迁移序列：107 建身份（授权清单为 107 时代硬编码的 10 项），
	// 108 为存量 customer 分配补授 devices:control，两级叠加后与代码侧
	// RoleDefaultPermissions[customer] 一致。
	execMigrationFile(t, pool, "107_backfill_personal_orgs_for_users.up.sql")
	execMigrationFile(t, pool, "108_grant_customer_devices_control.up.sql")

	assertCustomerIdentity(t, pool, 9201, 9100, 9100)
	assertCustomerIdentity(t, pool, 9202, 9100, 9100) // 空昵称用户兜底为 User_<id>

	// 已有身份的用户保持原组织，不被 backfill 改写
	var existingOrgID int64
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT organization_id FROM organization_memberships
		WHERE user_id = 9203 AND status = 'active'
	`).Scan(&existingOrgID))
	assert.Equal(t, int64(9210), existingOrgID)

	// 幂等重放不产生重复身份与重复授权
	execMigrationFile(t, pool, "107_backfill_personal_orgs_for_users.up.sql")
	execMigrationFile(t, pool, "108_grant_customer_devices_control.up.sql")
	var totalMemberships int
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM organization_memberships
		WHERE user_id IN (9201, 9202, 9203)
	`).Scan(&totalMemberships))
	assert.Equal(t, 3, totalMemberships)
}

// 迁移 115：没有活跃组织身份的存量用户被补建到共享「用户组织」之下，
// 已有组织身份的用户保持原样；重复执行不产生重复身份。
func TestMigration115BackfillsOrphansIntoSharedUsersOrg(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()
	ctx := context.Background()

	// 两个孤儿用户（例如管理后台直接建户）+ 一个已有组织身份的用户
	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, phone, email, password_hash, nickname, status) VALUES
			(9401, '13800009401', 'orphan-a@example.com', 'hash', 'Orphan A', 1),
			(9402, NULL, 'orphan-b@example.com', 'hash', '', 1)
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO organizations (id, root_tenant_id, parent_id, org_type, name, status)
		VALUES (9410, 9100, 9100, 'customer', 'Existing Org', 'active')
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO users (id, phone, password_hash, nickname, status)
		VALUES (9403, '13800009403', 'hash', 'Existing Member', 1)
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
		VALUES (9100, 9410, 9403, 'active')
	`)
	require.NoError(t, err)

	// 生产形态：存在一个 root_tenant_id 更低、但没有 tenant_roots 行的
	// manufacturer 组织。迁移必须跳过它，否则建子组织会被触发器以 23503 拒绝。
	_, err = pool.Exec(ctx, `
		INSERT INTO organizations (id, root_tenant_id, parent_id, org_type, name, status)
		VALUES (9001, 9001, NULL, 'manufacturer', 'Unregistered Root', 'active')
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		SET app.allow_closure_write = 'true';
		DELETE FROM organization_closure WHERE root_tenant_id = 9001;
		RESET app.allow_closure_write;
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM tenant_roots WHERE root_tenant_id = 9001`)
	require.NoError(t, err)

	// 115 自带的授权清单已含 devices:control，无需再跑 108
	execMigrationFile(t, pool, "115_backfill_orphans_into_shared_users_org.up.sql")

	usersOrg := sharedUsersOrgID(t, pool)
	assertCustomerIdentity(t, pool, 9401, usersOrg, 9100)
	assertCustomerIdentity(t, pool, 9402, usersOrg, 9100) // 空昵称用户兜底为 User_<id>

	// 已有身份的用户保持原组织，不被 backfill 改写
	var existingOrgID int64
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT organization_id FROM organization_memberships
		WHERE user_id = 9403 AND status = 'active'
	`).Scan(&existingOrgID))
	assert.Equal(t, int64(9410), existingOrgID)

	// 共享「用户组织」是一条 agent → distributor → installer 的链，每一级只有一份，
	// 且链首挂在制造商根组织下（validate_org_hierarchy 只允许 customer 挂在
	// installer / manufacturer 之下，所以链不能省）。
	var agentID, distributorID, installerID int64
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT id FROM organizations WHERE code = 'default-users-agent' AND deleted_at IS NULL`,
	).Scan(&agentID))
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT id FROM organizations WHERE code = 'default-users-distributor' AND deleted_at IS NULL`,
	).Scan(&distributorID))
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT id FROM organizations WHERE code = 'default-users' AND deleted_at IS NULL`,
	).Scan(&installerID))

	assert.Equal(t, int64(9100), orgParent(t, pool, agentID), "chain must hang under the manufacturer root")
	assert.Equal(t, agentID, orgParent(t, pool, distributorID))
	assert.Equal(t, distributorID, orgParent(t, pool, installerID))

	var chainCount int64
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM organizations
		WHERE LOWER(code) LIKE 'default-users%' AND deleted_at IS NULL
	`).Scan(&chainCount))
	assert.Equal(t, int64(3), chainCount, "shared users org chain must be a singleton")

	// 幂等重放不产生重复身份与重复授权
	execMigrationFile(t, pool, "115_backfill_orphans_into_shared_users_org.up.sql")
	var totalMemberships, totalGrants int
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM organization_memberships WHERE user_id IN (9401, 9402, 9403)
	`).Scan(&totalMemberships))
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM role_permission_grants g
		JOIN membership_role_assignments ra ON ra.id = g.role_assignment_id
		JOIN organization_memberships m ON m.id = ra.membership_id
		WHERE m.user_id IN (9401, 9402)
	`).Scan(&totalGrants))
	assert.Equal(t, 3, totalMemberships, "replay must not duplicate memberships")
	assert.Equal(t, 2*len(RoleDefaultPermissions["customer"]), totalGrants, "replay must not duplicate grants")
}

func TestMigration106OwnerBranchGrantsStationAccess(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()
	ctx := context.Background()

	// 孤儿用户 + 其自建电站（无任何组织身份）
	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, phone, email, password_hash, nickname, status)
		VALUES (9301, NULL, 'owner@example.com', 'hash', 'Owner', 1)
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO stations (id, user_id, name, province, city, address, capacity)
		VALUES (9301, 9301, 'Owner Station', '湖南省', '长沙市', '麓谷', 10.0)
	`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO users (id, phone, email, password_hash, nickname, status)
		VALUES (9302, NULL, 'stranger@example.com', 'hash', 'Stranger', 1)
	`)
	require.NoError(t, err)

	// 迁移 106 后 owner 分支生效：持有者可访问自己的电站，无关用户不可访问
	execMigrationFile(t, pool, "106_add_owner_access_to_permission_views.up.sql")

	var ownerAccess, strangerAccess bool
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM v_user_station_access WHERE user_id = 9301 AND station_id = 9301)
	`).Scan(&ownerAccess))
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM v_user_station_access WHERE user_id = 9302 AND station_id = 9301)
	`).Scan(&strangerAccess))
	assert.True(t, ownerAccess, "owner branch must grant access to own stations without org identity")
	assert.False(t, strangerAccess, "strangers must not gain access through the owner branch")
}

// TestResolveSessionContextHandlesNullPhone 迁移 104 允许 users.phone 为 NULL
// （海外用户纯邮箱注册）。授权会话上下文查询必须容忍 NULL phone，
// 否则此类用户登录在 generate token 阶段 scan 失败直接 500。
func TestResolveSessionContextHandlesNullPhone(t *testing.T) {
	pool, cleanup := setupIdentityTestDB(t)
	defer cleanup()
	ctx := context.Background()

	repo := NewUserRepository(pool, nil)
	user := &model.User{
		Email:        "null-phone@example.com",
		PasswordHash: "$2a$10$examplehash",
		Nickname:     "Null Phone Tester",
		Status:       1,
	}
	require.NoError(t, repo.CreateUserWithOrgIdentity(ctx, user))

	// 前置确认：纯邮箱注册的 phone 落库为 NULL（空串由 userCreateInsertSQL 转 NULL）
	var phoneNull bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT phone IS NULL FROM users WHERE id=$1`, user.ID).Scan(&phoneNull))
	require.True(t, phoneNull, "test precondition: users.phone must be NULL for email-only registration")

	authRepo := NewAuthorizationRepository(pool)

	resolved, err := authRepo.ResolveDefaultSessionContext(ctx, user.ID)
	require.NoError(t, err, "default session context must resolve for NULL-phone users")
	assert.True(t, resolved.Valid())
	// 注册用户挂在共享「用户组织」下，根租户是系统制造商根组织（9100），
	// 不再是"每个用户自建租户根"的孤岛
	assert.Equal(t, int64(9100), resolved.Actor.RootTenantID)

	explicit, err := authRepo.ResolveAuthorizationSessionContext(ctx, user.ID, resolved.Actor.OrganizationID)
	require.NoError(t, err, "explicit session context must resolve for NULL-phone users")
	assert.True(t, explicit.Valid())
	assert.Empty(t, explicit.Phone)
}

func envOrFallback(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
