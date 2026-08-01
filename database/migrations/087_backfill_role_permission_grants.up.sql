-- Migration 087: Backfill default permission grants for channel roles
--
-- 背景：迁移 075 从旧 role_permissions 表向 role_permission_grants 灌入授权时，
-- 旧表已无数据（inv_full.sql 中的 88 行种子未随库迁移），导致 role_permission_grants
-- 全库 0 行。所有非系统管理员（代理商/安装商/终端用户）登录后 permissions 为空，
-- 前端菜单按 hasPermission 过滤全部隐藏。
--
-- 本迁移按角色码（org_admin/agent/distributor/installer/customer）为所有 active
-- 角色分配补齐默认授权，幂等可重放：
--   org_admin   <- 旧 role_permissions role=1（代理商全量 CRUD）+ notifications + organizations 管理
--   agent       <- 旧 role 2 ∪ role 3（安装商/分销商能力并集）
--   distributor <- 旧 role 3（分销商）
--   installer   <- 最小业务集（旧 role 4 无种子）
--   customer    <- 最小查看集（旧 role 5 无种子）

INSERT INTO role_permission_grants
    (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
SELECT ra.root_tenant_id, ra.organization_id, ra.id, p.permission_code, p.data_scope
FROM membership_role_assignments ra
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
) AS p(role_code, permission_code, data_scope) ON p.role_code = ra.role_code
WHERE ra.status = 'active'
ON CONFLICT (role_assignment_id, permission_code) DO NOTHING;

-- 同步触发 authorization_version 递增（触发器 trg_permission_grant_authorization_version
-- 已处理 INSERT，无需手动 bump）
