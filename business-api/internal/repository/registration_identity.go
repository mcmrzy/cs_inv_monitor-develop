package repository

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"inv-api-server/internal/model"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

// 注册身份建立：自助注册（邮箱/手机号/一键登录）与邀请挂靠用户共用
// 组织权限体系（organization_memberships + membership_role_assignments +
// role_permission_grants + v_user_station_access / v_user_device_access 视图）。
// 注册用户在建户同事务内获得个人 customer 组织身份，权限基线与邀请挂靠
// 的 customer 成员完全一致；后续接受邀请时由成员生命周期流程切换组织。

// personalOrgCodePrefix 个人 customer 组织的 code 标记前缀，
// 迁移 107 的 down 脚本据此精确回滚 backfill 建立的组织。
const personalOrgCodePrefix = "personal-"

// 共享「用户组织」：非邀请注册的用户不再各自成为租户根，而是统一挂靠到这个
// 组织（见 sharedUsersOrgChain 末级）之下，各自持有自己的 customer 子组织。
// 只共享父节点不共享数据可见范围——v_user_station_access 的组织闭包分支会包含
// 同组织成员，因此不能让注册用户直接成为同一个组织的成员，否则用户之间会互相
// 看到并操作对方的电站。
const (
	sharedUsersOrgCode = "default-users"
	sharedUsersOrgName = "用户组织"
)

// errSharedUsersOrgRootMissing 表示库里还没有任何制造商根组织（全新空库），
// 此时无法定位共享用户组织的根租户。
var errSharedUsersOrgRootMissing = errors.New("no active manufacturer root organization")

// resolveSystemManufacturerRoot 返回共享「用户组织」应挂靠的 (根租户, 制造商组织)
// id：系统制造商根组织，取最低 root_tenant_id，与迁移 075/107 的口径一致。
func (r *UserRepository) resolveSystemManufacturerRoot(ctx context.Context) (int64, int64, error) {
	var rootTenantID, manufacturerOrgID int64
	err := r.db.QueryRow(ctx, `
		SELECT root_tenant_id, id
		FROM organizations
		WHERE org_type = $1
		  AND parent_id IS NULL
		  AND deleted_at IS NULL
		  AND status = $2
		ORDER BY root_tenant_id
		LIMIT 1
	`, "manufacturer", "active").Scan(&rootTenantID, &manufacturerOrgID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, 0, errSharedUsersOrgRootMissing
	}
	if err != nil {
		return 0, 0, fmt.Errorf("resolve system manufacturer root: %w", err)
	}
	return rootTenantID, manufacturerOrgID, nil
}

// sharedUsersOrgChain 是共享「用户组织」的层级路径，按父到子排列。
// validate_org_hierarchy 的规则是 agent←manufacturer、distributor←agent、
// installer←distributor、customer←installer|manufacturer，因此承载个人
// customer 组织的共享父节点必须补齐中间层，最后一级才是「用户组织」。
// 中间层不承载任何成员，也不下挂其它渠道组织，只用于满足层级约束。
var sharedUsersOrgChain = []struct {
	OrgType string
	Code    string
	Name    string
}{
	{"agent", sharedUsersOrgCode + "-agent", "用户组织·渠道层"},
	{"distributor", sharedUsersOrgCode + "-distributor", "用户组织·分销层"},
	{"installer", sharedUsersOrgCode, sharedUsersOrgName},
}

// findOrgByCode 返回指定 code 的组织 id，不存在时返回 0。
func (r *UserRepository) findOrgByCode(ctx context.Context, rootTenantID int64, code string) (int64, error) {
	var orgID int64
	err := r.db.QueryRow(ctx, `
		SELECT id FROM organizations
		WHERE root_tenant_id = $1 AND LOWER(code) = $2 AND deleted_at IS NULL
		ORDER BY id
		LIMIT 1
	`, rootTenantID, code).Scan(&orgID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("lookup org %s: %w", code, err)
	}
	return orgID, nil
}

// ensureOrgUnder 幂等建立 parentID 之下的（code, orgType）组织并返回其 id。
func (r *UserRepository) ensureOrgUnder(ctx context.Context, rootTenantID, parentID int64, orgType, code, name string) (int64, error) {
	orgID, err := r.findOrgByCode(ctx, rootTenantID, code)
	if err != nil {
		return 0, err
	}
	if orgID != 0 {
		return orgID, nil
	}

	var pgErr *pgconn.PgError
	err = r.db.QueryRow(ctx, `
		INSERT INTO organizations (root_tenant_id, parent_id, org_type, code, name, status)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`, rootTenantID, parentID, orgType, code, name, "active").Scan(&orgID)
	if err != nil {
		if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
			return 0, fmt.Errorf("create shared org %s: %w", code, err)
		}
		// 并发注册同时创建，唯一索引挡下后重读。
		orgID, err = r.findOrgByCode(ctx, rootTenantID, code)
		if err != nil {
			return 0, err
		}
		if orgID == 0 {
			return 0, fmt.Errorf("shared org %s missing after unique violation", code)
		}
		return orgID, nil
	}

	logger.Info("created shared users org level",
		zap.Int64("root_tenant_id", rootTenantID),
		zap.String("code", code),
		zap.Int64("organization_id", orgID))
	return orgID, nil
}

// EnsureSharedUsersOrg 幂等解析（必要时创建）共享「用户组织」，返回其根租户与
// 组织 id（即链末的 installer 层，个人 customer 组织的父节点）。
// 该组织链是全局单例，故在注册事务之外用连接池建立：并发注册撞唯一索引时按
// "已被别的请求建好"处理并重读，不为此引入跨请求的串行化。
func (r *UserRepository) EnsureSharedUsersOrg(ctx context.Context) (int64, int64, error) {
	rootTenantID, parentID, err := r.resolveSystemManufacturerRoot(ctx)
	if err != nil {
		return 0, 0, err
	}

	for _, level := range sharedUsersOrgChain {
		orgID, err := r.ensureOrgUnder(ctx, rootTenantID, parentID, level.OrgType, level.Code, level.Name)
		if err != nil {
			return 0, 0, err
		}
		parentID = orgID
	}
	return rootTenantID, parentID, nil
}

// CreateUserWithOrgIdentity 在同一事务内创建用户并为其建立个人 customer
// 组织身份（organization + membership + customer 角色分配 + 默认授权）。
// 任一步失败则整体回滚，保证不产生"无组织身份"的孤儿用户。
func (r *UserRepository) CreateUserWithOrgIdentity(ctx context.Context, user *model.User) error {
	// 共享「用户组织」先在事务外就位：它是全局单例，本次注册失败也应保留。
	rootTenantID, parentOrgID, err := r.EnsureSharedUsersOrg(ctx)
	if err != nil {
		return err
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin registration transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	if err := r.CreateWithTx(ctx, tx, user); err != nil {
		return err
	}

	if err := createPersonalCustomerOrg(ctx, tx, user.ID, user.Nickname, rootTenantID, parentOrgID); err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit registration transaction: %w", err)
	}
	return nil
}

// EnsureUserOrgIdentity 为已存在但无活跃组织身份的用户补建个人 customer
// 组织身份（幂等：已有活跃 membership 时直接跳过）。用于存量孤儿用户的
// 兜底场景；常规 backfill 由迁移 115 完成。
func (r *UserRepository) EnsureUserOrgIdentity(ctx context.Context, userID int64, nickname string) error {
	var hasActive bool
	if err := r.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM organization_memberships
			WHERE user_id = $1 AND status = 'active'
		)
	`, userID).Scan(&hasActive); err != nil {
		return fmt.Errorf("check user membership: %w", err)
	}
	if hasActive {
		return nil
	}

	rootTenantID, parentOrgID, err := r.EnsureSharedUsersOrg(ctx)
	if err != nil {
		return err
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin identity transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	if err := createPersonalCustomerOrg(ctx, tx, userID, nickname, rootTenantID, parentOrgID); err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit identity transaction: %w", err)
	}
	return nil
}

// createPersonalCustomerOrg 为用户建立个人 customer 组织身份：组织挂共享
// 「用户组织」之下（渠道层级 manufacturer → 用户组织 → personal-<user_id>），
// 因此所有自助注册用户共享同一根租户，但各自持有自己的组织，组织闭包不会
// 让用户互相看到对方的电站/设备。closure / tenant_roots 由
// trg_organizations_insert_relations 自动维护，角色固定为 customer 并写入
// 默认授权（EnsureRoleDefaultGrants）。
// 必须在事务内调用；code 标记为 personal-<user_id> 便于精确回滚。
func createPersonalCustomerOrg(ctx context.Context, tx pgx.Tx, userID int64, nickname string, sharedRootTenantID, sharedParentOrgID int64) error {
	// 个人组织统一挂共享「用户组织」之下：所有自助注册用户共享同一个根租户，
	// 但各自持有自己的组织，不再为每个用户单开租户根。
	rootTenantID := sharedRootTenantID
	manufacturerOrgID := sharedParentOrgID

	orgName := nickname
	if orgName == "" {
		orgName = fmt.Sprintf("User_%d", userID)
	}
	orgCode := personalOrgCodePrefix + strconv.FormatInt(userID, 10)

	var orgID int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO organizations (root_tenant_id, parent_id, org_type, code, name, status)
		VALUES ($1, $2, 'customer', $3, $4, 'active')
		RETURNING id
	`, rootTenantID, manufacturerOrgID, orgCode, orgName).Scan(&orgID); err != nil {
		return fmt.Errorf("create personal customer org: %w", err)
	}

	var membershipID int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
		VALUES ($1, $2, $3, 'active')
		RETURNING id
	`, rootTenantID, orgID, userID).Scan(&membershipID); err != nil {
		return fmt.Errorf("create personal org membership: %w", err)
	}

	var assignmentID int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status, version)
		VALUES ($1, $2, $3, 'customer', 'active', 1)
		RETURNING id
	`, rootTenantID, orgID, membershipID).Scan(&assignmentID); err != nil {
		return fmt.Errorf("create customer role assignment: %w", err)
	}

	if err := EnsureRoleDefaultGrants(ctx, tx, rootTenantID, orgID, assignmentID, "customer"); err != nil {
		return fmt.Errorf("grant customer default permissions: %w", err)
	}

	logger.Info("created personal customer org identity",
		zap.Int64("user_id", userID),
		zap.Int64("organization_id", orgID),
		zap.Int64("membership_id", membershipID))
	return nil
}
