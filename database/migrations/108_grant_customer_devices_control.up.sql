-- Migration 108: Grant devices:control to customer role
--
-- 背景：customer（终端用户）的默认权限矩阵（迁移 087/088 与
-- role_default_grants.go）自始未包含 devices:control，导致终端用户在 App
-- 远程控制自有设备时被 RequirePermission 中间件拦截（403 权限不足:
-- devices:control），而其余四级角色均有该权限——属权限矩阵设计遗漏。
--
-- 本迁移为所有 active customer 角色分配幂等补齐 devices:control，
-- data_scope 与 customer 其他权限一致取 organization（个人组织即自有设备，
-- 数据归属由 HasDataPermission 二次校验，不会越权控制他人设备）。
--
-- 与代码侧 role_default_grants.go 的 customer 段保持一致（后者同步新增）。
-- 幂等可重放。

INSERT INTO role_permission_grants
    (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
SELECT ra.root_tenant_id, ra.organization_id, ra.id, 'devices:control', 'organization'
FROM membership_role_assignments ra
WHERE ra.role_code = 'customer'
  AND ra.status = 'active'
ON CONFLICT (role_assignment_id, permission_code) DO NOTHING;

-- 授权版本由触发器 trg_permission_grant_authorization_version 处理 INSERT，
-- 无需手动 bump。
