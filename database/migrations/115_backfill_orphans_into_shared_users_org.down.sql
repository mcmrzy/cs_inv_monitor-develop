-- Migration 115 down: 回滚本次 backfill 建立的共享「用户组织」链及其下的个人组织。
--
-- 只处理 code 前缀 default-users 的组织链（agent → distributor → installer）
-- 与挂在链末 installer 之下的 personal-<user_id> 组织，不动迁移 107 等直接挂在
-- manufacturer 根组织下的存量个人组织。
-- 删除顺序：grants → assignments → closure → memberships → organizations，
-- 与 FK ON DELETE RESTRICT 一致。closure 表受 guard_organization_closure_mutation
-- 触发器保护，使用 app.allow_closure_write 会话逃生舱（迁移 72 引入）放行维护写入。

CREATE TEMP TABLE mig115_chain ON COMMIT DROP AS
SELECT id, org_type
FROM organizations
WHERE LOWER(code) LIKE 'default-users%'
  AND deleted_at IS NULL;

-- 链末的 installer 层——个人 customer 组织的父节点
CREATE TEMP TABLE mig115_users_org ON COMMIT DROP AS
SELECT id FROM mig115_chain WHERE org_type = 'installer';

-- 删除个人组织的默认授权（先于角色分配删除，避免外键 RESTRICT）
DELETE FROM role_permission_grants g
USING membership_role_assignments ra
JOIN organizations o
  ON o.root_tenant_id = ra.root_tenant_id
 AND o.id = ra.organization_id
WHERE g.role_assignment_id = ra.id
  AND o.code LIKE 'personal-%'
  AND o.parent_id IN (SELECT id FROM mig115_users_org);

-- 删除个人组织的角色分配
DELETE FROM membership_role_assignments ra
USING organizations o
WHERE o.root_tenant_id = ra.root_tenant_id
  AND o.id = ra.organization_id
  AND o.code LIKE 'personal-%'
  AND o.parent_id IN (SELECT id FROM mig115_users_org);

-- 删除个人组织相关 closure 行，以及共享链自身的 closure 行
-- （个人组织均为叶子，descendant 指向个人组织）
SET app.allow_closure_write = 'true';

DELETE FROM organization_closure c
USING organizations o
WHERE o.root_tenant_id = c.root_tenant_id
  AND o.id = c.descendant_id
  AND o.code LIKE 'personal-%'
  AND o.parent_id IN (SELECT id FROM mig115_users_org);

DELETE FROM organization_closure c
WHERE c.descendant_id IN (SELECT id FROM mig115_chain)
   OR c.ancestor_id IN (SELECT id FROM mig115_chain);

RESET app.allow_closure_write;

-- 删除个人组织的成员关系
DELETE FROM organization_memberships m
USING organizations o
WHERE o.root_tenant_id = m.root_tenant_id
  AND o.id = m.organization_id
  AND o.code LIKE 'personal-%'
  AND o.parent_id IN (SELECT id FROM mig115_users_org);

-- 删除个人组织
DELETE FROM organizations
WHERE code LIKE 'personal-%'
  AND parent_id IN (SELECT id FROM mig115_users_org);

-- 删除共享链（自下而上，满足父子外键）
DELETE FROM organizations
WHERE id IN (SELECT id FROM mig115_users_org);

DELETE FROM organizations
WHERE id IN (SELECT id FROM mig115_chain WHERE org_type = 'distributor');

DELETE FROM organizations
WHERE id IN (SELECT id FROM mig115_chain WHERE org_type = 'agent');
