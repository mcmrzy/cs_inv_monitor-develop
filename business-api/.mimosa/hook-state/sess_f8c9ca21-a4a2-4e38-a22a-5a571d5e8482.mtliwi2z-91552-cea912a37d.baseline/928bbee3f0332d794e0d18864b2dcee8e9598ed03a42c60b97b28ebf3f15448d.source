package repository

import (
	"context"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"

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

// CreateUserWithOrgIdentity 在同一事务内创建用户并为其建立个人 customer
// 组织身份（organization + membership + customer 角色分配 + 默认授权）。
// 任一步失败则整体回滚，保证不产生"无组织身份"的孤儿用户。
func (r *UserRepository) CreateUserWithOrgIdentity(ctx context.Context, user *model.User) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin registration transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	if err := r.CreateWithTx(ctx, tx, user); err != nil {
		return err
	}

	if err := createPersonalCustomerOrg(ctx, tx, user.ID, user.Nickname); err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit registration transaction: %w", err)
	}
	return nil
}

// EnsureUserOrgIdentity 为已存在但无活跃组织身份的用户补建个人 customer
// 组织身份（幂等：已有活跃 membership 时直接跳过）。用于存量孤儿用户的
// 兜底场景；常规 backfill 由迁移 107 完成。
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

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin identity transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	if err := createPersonalCustomerOrg(ctx, tx, userID, nickname); err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit identity transaction: %w", err)
	}
	return nil
}

// createPersonalCustomerOrg 为用户建立个人 customer 组织身份：
// 组织挂 manufacturer 根组织下（渠道层级 manufacturer → … → customer），
// closure / tenant_roots 由 trg_organizations_insert_relations 自动维护，
// 角色固定为 customer 并写入默认授权（EnsureRoleDefaultGrants）。
// 必须在事务内调用；code 标记为 personal-<user_id> 便于精确回滚。
func createPersonalCustomerOrg(ctx context.Context, tx pgx.Tx, userID int64, nickname string) error {
	// Each user gets their own root tenant. ensure_tenant_root is idempotent:
	// if the user already has a manufacturer root org, it returns the existing one.
	rootTenantID := userID
	if _, err := tx.Exec(ctx, `SELECT ensure_tenant_root($1)`, rootTenantID); err != nil {
		return fmt.Errorf("ensure tenant root for user %d: %w", userID, err)
	}

	// The manufacturer org ID equals the root tenant ID (created by ensure_tenant_root).
	manufacturerOrgID := rootTenantID

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
