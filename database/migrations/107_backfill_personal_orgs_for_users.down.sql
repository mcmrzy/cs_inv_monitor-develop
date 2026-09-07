-- Migration 107 down: 回滚 backfill 建立的个人 customer 组织身份。
-- 仅删除 code='personal-<user_id>' 标记的组织链（grants → assignments →
-- closure → memberships → organizations），不影响 075/087 等迁移建立的组织身份。
-- closure 表受 guard_organization_closure_mutation 触发器保护，
-- 使用 app.allow_closure_write 会话逃生舱（迁移 72 引入）放行维护写入。

-- 删除个人组织的默认授权（先于角色分配删除，避免外键 RESTRICT）
DELETE FROM role_permission_grants g
USING membership_role_assignments ra
JOIN organizations o
  ON o.root_tenant_id = ra.root_tenant_id
 AND o.id = ra.organization_id
WHERE g.role_assignment_id = ra.id
  AND o.code LIKE 'personal-%';

-- 删除个人组织的角色分配
DELETE FROM membership_role_assignments ra
USING organizations o
WHERE o.root_tenant_id = ra.root_tenant_id
  AND o.id = ra.organization_id
  AND o.code LIKE 'personal-%';

-- 删除个人组织相关 closure 行（个人组织均为叶子，descendant 指向个人组织）
SET app.allow_closure_write = 'true';
DELETE FROM organization_closure c
USING organizations o
WHERE o.root_tenant_id = c.root_tenant_id
  AND o.id = c.descendant_id
  AND o.code LIKE 'personal-%';
RESET app.allow_closure_write;

-- 删除个人组织的成员关系
DELETE FROM organization_memberships m
USING organizations o
WHERE o.root_tenant_id = m.root_tenant_id
  AND o.id = m.organization_id
  AND o.code LIKE 'personal-%';

-- 删除个人组织
DELETE FROM organizations WHERE code LIKE 'personal-%';
