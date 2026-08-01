-- Migration 088: Fix member identity roles to match organization types
--
-- 背景：存量数据中存在"组织类型与成员身份不匹配"的角色分配（如 agent 组织内的
-- customer 角色、installer 角色）。在新邀请模型（身份=组织类型，org_admin 为唯一
-- 可叠加的管理角色）下，这些记录会绕过 validateRoleOrgMatch 校验，必须修正。
--
-- 修正规则（与代码 orgTypeIdentityRoles 保持一致）：
--   agent 组织       -> 身份 agent
--   distributor 组织 -> 身份 distributor
--   installer 组织   -> 身份 installer
--   customer 组织    -> 身份 customer
--   manufacturer 组织 -> 身份 org_admin（manufacturer 无独立身份码，等同 org_admin）
-- org_admin 作为可叠加的管理角色原样保留（任意组织类型均合法）。
--
-- 同时重建受影响分配的角色默认授权（删除旧角色 grants，按新身份默认权限重插，
-- 与迁移 087 / role_default_grants.go 的默认权限表保持一致）。幂等可重放。
--
-- 注意：必须分步执行（临时表 + 独立语句），不可用 data-modifying CTE 链——
-- 同一语句内的 CTE 共享同一快照，后续 CTE 的 ON CONFLICT 检测看不到前面
-- DELETE 的效果，会导致与旧权限重叠的权限码被跳过（缺失授权）。
--
-- 说明：授权版本由触发器 trg_role_assignment_authorization_version /
-- trg_permission_grant_authorization_version 自动递增，无需手动 bump。

-- Step 1：收集受影响的角色分配（组织类型与身份不匹配的非 org_admin 记录）
CREATE TEMP TABLE _m088_corrected AS
SELECT ra.id, ra.root_tenant_id, ra.organization_id,
       CASE o.org_type
           WHEN 'manufacturer' THEN 'org_admin'
           ELSE o.org_type
       END AS new_role_code
FROM membership_role_assignments ra
JOIN organizations o ON o.id = ra.organization_id
WHERE o.deleted_at IS NULL
  AND o.org_type IN ('manufacturer', 'agent', 'distributor', 'installer', 'customer')
  AND ra.role_code <> 'org_admin'
  AND ra.role_code <> CASE o.org_type
        WHEN 'manufacturer' THEN 'org_admin'
        ELSE o.org_type
    END;

-- Step 2：修正角色码为组织类型身份
UPDATE membership_role_assignments ra
SET role_code = c.new_role_code
FROM _m088_corrected c
WHERE c.id = ra.id;

-- Step 3：清除受影响分配的旧角色授权
DELETE FROM role_permission_grants g
WHERE g.role_assignment_id IN (SELECT id FROM _m088_corrected);

-- Step 4：按新身份默认权限重插（与 087 的 VALUES 表完全一致）
INSERT INTO role_permission_grants
    (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
SELECT c.root_tenant_id, c.organization_id, c.id, p.permission_code, p.data_scope
FROM _m088_corrected c
JOIN (
    VALUES
        -- org_admin：组织全量管理（旧 role 1 + 通知 + 组织管理）
        ('org_admin', 'dashboard:view',          'organization_and_descendants'),
        ('org_admin', 'dashboard:export',        'organization_and_descendants'),
        ('org_admin', 'devices:view',            'organization_and_descendants'),
        ('org_admin', 'devices:create',          'organization_and_descendants'),
        ('org_admin', 'devices:edit',            'organization_and_descendants'),
        ('org_admin', 'devices:delete',          'organization_and_descendants'),
        ('org_admin', 'devices:export',          'organization_and_descendants'),
        ('org_admin', 'devices:control',         'organization_and_descendants'),
        ('org_admin', 'devices:manage',          'organization_and_descendants'),
        ('org_admin', 'stations:view',           'organization_and_descendants'),
        ('org_admin', 'stations:create',         'organization_and_descendants'),
        ('org_admin', 'stations:edit',           'organization_and_descendants'),
        ('org_admin', 'alerts:view',             'organization_and_descendants'),
        ('org_admin', 'alerts:manage',           'organization_and_descendants'),
        ('org_admin', 'alert_rules:view',        'organization_and_descendants'),
        ('org_admin', 'alert_rules:create',      'organization_and_descendants'),
        ('org_admin', 'alert_rules:edit',        'organization_and_descendants'),
        ('org_admin', 'alert_rules:delete',      'organization_and_descendants'),
        ('org_admin', 'work_orders:view',        'organization_and_descendants'),
        ('org_admin', 'work_orders:create',      'organization_and_descendants'),
        ('org_admin', 'work_orders:edit',        'organization_and_descendants'),
        ('org_admin', 'work_orders:manage',      'organization_and_descendants'),
        ('org_admin', 'users:view',              'organization_and_descendants'),
        ('org_admin', 'users:create',            'organization_and_descendants'),
        ('org_admin', 'users:edit',              'organization_and_descendants'),
        ('org_admin', 'users:delete',            'organization_and_descendants'),
        ('org_admin', 'users:manage',            'organization_and_descendants'),
        ('org_admin', 'firmware:view',           'organization_and_descendants'),
        ('org_admin', 'ota:view',                'organization_and_descendants'),
        ('org_admin', 'ota:create',              'organization_and_descendants'),
        ('org_admin', 'ota:control',             'organization_and_descendants'),
        ('org_admin', 'parallel:view',           'organization_and_descendants'),
        ('org_admin', 'parallel:create',         'organization_and_descendants'),
        ('org_admin', 'parallel:control',        'organization_and_descendants'),
        ('org_admin', 'audit:view',              'organization_and_descendants'),
        ('org_admin', 'admin:view',              'organization_and_descendants'),
        ('org_admin', 'admin:manage',            'organization_and_descendants'),
        ('org_admin', 'models:view',             'organization_and_descendants'),
        ('org_admin', 'models:create',           'organization_and_descendants'),
        ('org_admin', 'models:edit',             'organization_and_descendants'),
        ('org_admin', 'models:delete',           'organization_and_descendants'),
        ('org_admin', 'notifications:view',      'organization_and_descendants'),
        ('org_admin', 'notifications:create',    'organization_and_descendants'),
        ('org_admin', 'notifications:edit',      'organization_and_descendants'),
        ('org_admin', 'organizations:view',      'organization_and_descendants'),
        ('org_admin', 'organizations:manage',    'organization_and_descendants'),
        ('org_admin', 'organizations:invite',    'organization_and_descendants'),
        ('org_admin', 'organizations:manage_members', 'organization_and_descendants'),

        -- agent：旧 role 2（channel_manager）∪ role 3（operator）
        ('agent', 'dashboard:view',              'organization_and_descendants'),
        ('agent', 'devices:view',                'organization_and_descendants'),
        ('agent', 'devices:create',              'organization_and_descendants'),
        ('agent', 'devices:edit',                'organization_and_descendants'),
        ('agent', 'devices:export',              'organization_and_descendants'),
        ('agent', 'devices:control',             'organization_and_descendants'),
        ('agent', 'stations:view',               'organization_and_descendants'),
        ('agent', 'stations:create',             'organization_and_descendants'),
        ('agent', 'stations:edit',               'organization_and_descendants'),
        ('agent', 'alerts:view',                 'organization_and_descendants'),
        ('agent', 'alerts:manage',               'organization_and_descendants'),
        ('agent', 'alerts:edit',                 'organization_and_descendants'),
        ('agent', 'work_orders:view',            'organization_and_descendants'),
        ('agent', 'work_orders:create',          'organization_and_descendants'),
        ('agent', 'work_orders:edit',            'organization_and_descendants'),
        ('agent', 'users:view',                  'organization_and_descendants'),
        ('agent', 'users:create',                'organization_and_descendants'),
        ('agent', 'firmware:view',               'organization_and_descendants'),
        ('agent', 'models:view',                 'organization_and_descendants'),
        ('agent', 'ota:view',                    'organization_and_descendants'),
        ('agent', 'ota:control',                 'organization_and_descendants'),
        ('agent', 'admin:view',                  'organization_and_descendants'),
        ('agent', 'admin:manage',                'organization_and_descendants'),
        ('agent', 'notifications:view',          'organization_and_descendants'),
        ('agent', 'notifications:create',        'organization_and_descendants'),
        ('agent', 'notifications:edit',          'organization_and_descendants'),
        ('agent', 'organizations:view',          'organization_and_descendants'),

        -- distributor：旧 role 3（operator）
        ('distributor', 'dashboard:view',        'organization_and_descendants'),
        ('distributor', 'devices:view',          'organization_and_descendants'),
        ('distributor', 'devices:create',        'organization_and_descendants'),
        ('distributor', 'devices:edit',          'organization_and_descendants'),
        ('distributor', 'devices:control',       'organization_and_descendants'),
        ('distributor', 'stations:view',         'organization_and_descendants'),
        ('distributor', 'stations:create',       'organization_and_descendants'),
        ('distributor', 'stations:edit',         'organization_and_descendants'),
        ('distributor', 'alerts:view',           'organization_and_descendants'),
        ('distributor', 'alerts:edit',           'organization_and_descendants'),
        ('distributor', 'firmware:view',         'organization_and_descendants'),
        ('distributor', 'models:view',           'organization_and_descendants'),
        ('distributor', 'ota:view',              'organization_and_descendants'),
        ('distributor', 'ota:control',           'organization_and_descendants'),
        ('distributor', 'admin:view',            'organization_and_descendants'),
        ('distributor', 'admin:manage',          'organization_and_descendants'),
        ('distributor', 'notifications:view',    'organization_and_descendants'),
        ('distributor', 'organizations:view',    'organization_and_descendants'),

        -- installer：最小业务集（旧 role 4 无种子）
        ('installer', 'dashboard:view',          'organization'),
        ('installer', 'devices:view',            'organization'),
        ('installer', 'devices:create',          'organization'),
        ('installer', 'devices:edit',            'organization'),
        ('installer', 'devices:control',         'organization'),
        ('installer', 'stations:view',           'organization'),
        ('installer', 'stations:create',         'organization'),
        ('installer', 'stations:edit',           'organization'),
        ('installer', 'alerts:view',             'organization'),
        ('installer', 'work_orders:view',        'organization'),
        ('installer', 'work_orders:create',      'organization'),
        ('installer', 'work_orders:edit',        'organization'),
        ('installer', 'firmware:view',           'organization'),
        ('installer', 'models:view',             'organization'),
        ('installer', 'notifications:view',      'organization'),

        -- customer：最小查看集（旧 role 5 无种子）
        ('customer', 'dashboard:view',           'organization'),
        ('customer', 'devices:view',             'organization'),
        ('customer', 'stations:view',            'organization'),
        ('customer', 'alerts:view',              'organization'),
        ('customer', 'firmware:view',            'organization'),
        ('customer', 'notifications:view',       'organization')
) AS p(role_code, permission_code, data_scope) ON p.role_code = c.new_role_code
ON CONFLICT (role_assignment_id, permission_code) DO NOTHING;

-- Step 5：清理临时表
DROP TABLE _m088_corrected;
