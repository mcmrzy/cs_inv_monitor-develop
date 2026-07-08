-- 020_backfill_rbac_new_resources: 为新增的5个RBAC资源补充种子数据
-- 资源: notifications, alert_rules, work_orders, models, dashboard

BEGIN;

-- 总代理 (role=1): 所有资源完整权限
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(1, 'notifications', 'view', true),
(1, 'notifications', 'create', true),
(1, 'notifications', 'edit', true),
(1, 'notifications', 'delete', true),
(1, 'alert_rules', 'view', true),
(1, 'alert_rules', 'create', true),
(1, 'alert_rules', 'edit', true),
(1, 'alert_rules', 'delete', true),
(1, 'work_orders', 'view', true),
(1, 'work_orders', 'create', true),
(1, 'work_orders', 'edit', true),
(1, 'work_orders', 'delete', true),
(1, 'models', 'view', true),
(1, 'models', 'create', true),
(1, 'models', 'edit', true),
(1, 'models', 'delete', true),
(1, 'dashboard', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 经销商 (role=2): notifications/alert_rules/work_orders CRO, models/dashboard 只读
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(2, 'notifications', 'view', true),
(2, 'notifications', 'create', true),
(2, 'notifications', 'edit', true),
(2, 'alert_rules', 'view', true),
(2, 'alert_rules', 'create', true),
(2, 'alert_rules', 'edit', true),
(2, 'work_orders', 'view', true),
(2, 'work_orders', 'create', true),
(2, 'work_orders', 'edit', true),
(2, 'models', 'view', true),
(2, 'dashboard', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 经销商 (role=3): 与role=2权限相同
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(3, 'notifications', 'view', true),
(3, 'notifications', 'create', true),
(3, 'notifications', 'edit', true),
(3, 'alert_rules', 'view', true),
(3, 'alert_rules', 'create', true),
(3, 'alert_rules', 'edit', true),
(3, 'work_orders', 'view', true),
(3, 'work_orders', 'create', true),
(3, 'work_orders', 'edit', true),
(3, 'models', 'view', true),
(3, 'dashboard', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 安装商 (role=4): work_orders CRO, 其余只读
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(4, 'notifications', 'view', true),
(4, 'alert_rules', 'view', true),
(4, 'work_orders', 'view', true),
(4, 'work_orders', 'create', true),
(4, 'work_orders', 'edit', true),
(4, 'models', 'view', true),
(4, 'dashboard', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 普通用户 (role=5): 全部只读
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(5, 'notifications', 'view', true),
(5, 'alert_rules', 'view', true),
(5, 'work_orders', 'view', true),
(5, 'dashboard', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

INSERT INTO schema_migrations (version, name) VALUES (20, 'backfill_rbac_new_resources') ON CONFLICT DO NOTHING;

COMMIT;
