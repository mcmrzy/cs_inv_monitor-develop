-- Migration 090 down: rollback customer self-management grants; restore org_admin organizations:create
--
-- 与 up 相反：
--   1. 删除 customer 角色的自助管理权限（devices:create/edit、stations:create/edit）；
--   2. 恢复 org_admin 的 organizations:create 授权（与迁移 089 up 相同逻辑）。

-- 1. 删除 customer 自助管理权限
DELETE FROM role_permission_grants
WHERE permission_code IN ('devices:create', 'devices:edit', 'stations:create', 'stations:edit')
  AND role_assignment_id IN (
      SELECT ra.id FROM membership_role_assignments ra
      WHERE ra.role_code = 'customer' AND ra.status = 'active'
  );

-- 2. 恢复 org_admin 的 organizations:create（幂等：已存在则保持不变）
INSERT INTO role_permission_grants
    (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
SELECT ra.root_tenant_id, ra.organization_id, ra.id, 'organizations:create', 'organization_and_descendants'
FROM membership_role_assignments ra
WHERE ra.role_code = 'org_admin'
  AND ra.status = 'active'
  AND NOT EXISTS (
      SELECT 1 FROM role_permission_grants pg
      WHERE pg.role_assignment_id = ra.id
        AND pg.permission_code = 'organizations:create'
  );
