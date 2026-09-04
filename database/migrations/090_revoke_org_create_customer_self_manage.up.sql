-- Migration 090: Revoke organizations:create from org_admin; add customer self-management grants
--
-- 背景：设计回退——终端用户不再通过"自动创建客户组织"方式接入，而是以
-- customer 身份直接挂在安装商（installer）组织下；组织创建回归"仅系统管理员"。
-- 因此：
--   1. 撤销迁移 089 为 org_admin 补充的 organizations:create 授权（普通管理员
--      不再允许创建任何组织，含 customer 类型）；
--   2. 为 customer 角色补充自助管理权限 devices:create/edit、stations:create/edit
--      （用户可添加设备、创建电站、更改信息；data_scope 保持 organization，
--      安装商 org_admin 通过 organization_and_descendants 天然覆盖其旗下全部用户数据）。
--
-- 幂等可重放：DELETE 无匹配行不报错；INSERT 使用 ON CONFLICT DO NOTHING。

-- 1. 撤销 org_admin 的 organizations:create（迁移 089 引入）
DELETE FROM role_permission_grants
WHERE permission_code = 'organizations:create'
  AND role_assignment_id IN (
      SELECT ra.id FROM membership_role_assignments ra
      WHERE ra.role_code = 'org_admin' AND ra.status = 'active'
  );

-- 2. 为 customer 角色补充自助管理权限（设备/电站增改）
INSERT INTO role_permission_grants
    (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
SELECT ra.root_tenant_id, ra.organization_id, ra.id, p.permission_code, p.data_scope
FROM membership_role_assignments ra
JOIN (
    VALUES
        ('customer', 'devices:create', 'organization'),
        ('customer', 'devices:edit',   'organization'),
        ('customer', 'stations:create', 'organization'),
        ('customer', 'stations:edit',   'organization')
) AS p(role_code, permission_code, data_scope) ON p.role_code = ra.role_code
WHERE ra.status = 'active'
ON CONFLICT (role_assignment_id, permission_code) DO NOTHING;
