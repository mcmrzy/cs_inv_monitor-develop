package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// 角色默认授权定义
// ----------------------------------------------------------------------------
// 每个角色分配（membership_role_assignments）在创建时必须同时写入对应的默认
// 授权（role_permission_grants），否则新成员登录后 permissions 为空、前端菜单
// 全部隐藏。本文件是"代码侧自动授权"的唯一数据源，与迁移
// 087_backfill_role_permission_grants.up.sql 中的 VALUES 表保持一致。
//
// 权限集来源：
//   - org_admin   <- 旧 role_permissions role=1（代理商全量 CRUD）+ notifications + organizations 管理
//   - agent       <- 旧 role 2（channel_manager）∪ role 3（operator）
//   - distributor <- 旧 role 3（operator）
//   - installer   <- 最小业务集（旧 role 4 无种子）
//   - customer    <- 最小查看集（旧 role 5 无种子）

// RoleDefaultPermissionScopes 角色码 → 默认 data_scope。
// 管理层角色覆盖自身及全部下级组织；执行层角色仅覆盖自身组织。
var RoleDefaultPermissionScopes = map[string]string{
	"org_admin":   "organization_and_descendants",
	"agent":       "organization_and_descendants",
	"distributor": "organization_and_descendants",
	"installer":   "organization",
	"customer":    "organization",
}

// RoleDefaultPermissions 角色码 → 默认权限码集（与迁移 087 保持一致）。
var RoleDefaultPermissions = map[string][]string{
	"org_admin": {
		"dashboard:view", "dashboard:export",
		"devices:view", "devices:create", "devices:edit", "devices:delete", "devices:export", "devices:control", "devices:manage",
		"stations:view", "stations:create", "stations:edit",
		"alerts:view", "alerts:manage",
		"alert_rules:view", "alert_rules:create", "alert_rules:edit", "alert_rules:delete",
		"work_orders:view", "work_orders:create", "work_orders:edit", "work_orders:manage",
		"users:view", "users:create", "users:edit", "users:delete", "users:manage",
		"firmware:view",
		"ota:view", "ota:create", "ota:control",
		"parallel:view", "parallel:create", "parallel:control",
		"audit:view",
		"admin:view", "admin:manage",
		"models:view", "models:create", "models:edit", "models:delete",
		"notifications:view", "notifications:create", "notifications:edit",
		"organizations:view", "organizations:manage", "organizations:invite", "organizations:manage_members",
	},
	"agent": {
		"dashboard:view",
		"devices:view", "devices:create", "devices:edit", "devices:export", "devices:control",
		"stations:view", "stations:create", "stations:edit",
		"alerts:view", "alerts:manage", "alerts:edit",
		"work_orders:view", "work_orders:create", "work_orders:edit",
		"users:view", "users:create",
		"firmware:view",
		"models:view",
		"ota:view", "ota:control",
		"admin:view", "admin:manage",
		"notifications:view", "notifications:create", "notifications:edit",
		"organizations:view",
	},
	"distributor": {
		"dashboard:view",
		"devices:view", "devices:create", "devices:edit", "devices:control",
		"stations:view", "stations:create", "stations:edit",
		"alerts:view", "alerts:edit",
		"firmware:view",
		"models:view",
		"ota:view", "ota:control",
		"admin:view", "admin:manage",
		"notifications:view",
		"organizations:view",
	},
	"installer": {
		"dashboard:view",
		"devices:view", "devices:create", "devices:edit", "devices:control",
		"stations:view", "stations:create", "stations:edit",
		"alerts:view",
		"work_orders:view", "work_orders:create", "work_orders:edit",
		"firmware:view",
		"models:view",
		"notifications:view",
	},
	"customer": {
		"dashboard:view",
		"devices:view",
		"stations:view",
		"alerts:view",
		"firmware:view",
		"notifications:view",
	},
}

// EnsureRoleDefaultGrants 在角色分配创建后，为该分配写入角色的默认授权
// （幂等：已存在的授权保持不变，不覆盖管理后台的手动配置）。
// 必须在与角色分配相同的事务中调用。
func EnsureRoleDefaultGrants(ctx context.Context, tx pgx.Tx, rootTenantID, organizationID, roleAssignmentID int64, roleCode string) error {
	perms, ok := RoleDefaultPermissions[roleCode]
	if !ok || len(perms) == 0 {
		return nil
	}
	scope := RoleDefaultPermissionScopes[roleCode]
	if scope == "" {
		scope = "organization"
	}
	for _, code := range perms {
		if _, err := tx.Exec(ctx, `
			INSERT INTO role_permission_grants
				(root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (role_assignment_id, permission_code) DO NOTHING
		`, rootTenantID, organizationID, roleAssignmentID, code, scope); err != nil {
			return fmt.Errorf("grant default permission %s: %w", code, err)
		}
	}
	return nil
}
