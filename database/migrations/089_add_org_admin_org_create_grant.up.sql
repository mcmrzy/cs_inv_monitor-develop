-- Migration 089: Add organizations:create grant to org_admin role
--
-- 背景：组织树已对普通管理员（org_admin）开放"新建组织"（仅 customer 类型，
-- 挂到其管理范围内的 installer 下），后端 POST /api/v1/organizations 由网关
-- RBAC 按权限码 organizations:create 判定。但 org_admin 默认授权（087/088 及
-- role_default_grants.go）只包含 organizations:view/manage/invite/manage_members，
-- 缺少 organizations:create，导致普通管理员创建客户组织被网关 403 拦截。
--
-- 本迁移为所有 active 的 org_admin 角色分配补上 organizations:create 授权
-- （data_scope 与其余 organizations 权限一致：organization_and_descendants），
-- 幂等可重放：已存在的授权保持不变。

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
