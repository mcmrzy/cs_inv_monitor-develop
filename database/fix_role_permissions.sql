-- 修复 role_permissions 表，确保所有角色都有正确的权限
-- 执行: psql -U postgres -d inv_mqtt -f fix_role_permissions.sql

-- 确保 role_permissions 表存在
CREATE TABLE IF NOT EXISTS role_permissions (
    id BIGSERIAL PRIMARY KEY,
    role SMALLINT NOT NULL,
    resource VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    is_allowed BOOLEAN DEFAULT true,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(role, resource, action)
);

CREATE INDEX IF NOT EXISTS idx_permissions_role ON role_permissions(role);

-- 超级管理员 (0): 所有权限
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(0, 'devices', 'view', true),
(0, 'devices', 'create', true),
(0, 'devices', 'edit', true),
(0, 'devices', 'delete', true),
(0, 'devices', 'export', true),
(0, 'devices', 'control', true),
(0, 'devices', 'manage', true),
(0, 'users', 'view', true),
(0, 'users', 'create', true),
(0, 'users', 'edit', true),
(0, 'users', 'delete', true),
(0, 'users', 'manage', true),
(0, 'alerts', 'view', true),
(0, 'alerts', 'manage', true),
(0, 'alert_rules', 'view', true),
(0, 'alert_rules', 'create', true),
(0, 'alert_rules', 'edit', true),
(0, 'alert_rules', 'delete', true),
(0, 'work_orders', 'view', true),
(0, 'work_orders', 'create', true),
(0, 'work_orders', 'edit', true),
(0, 'work_orders', 'manage', true),
(0, 'firmware', 'view', true),
(0, 'firmware', 'create', true),
(0, 'firmware', 'delete', true),
(0, 'ota', 'view', true),
(0, 'ota', 'create', true),
(0, 'ota', 'control', true),
(0, 'dashboard', 'view', true),
(0, 'dashboard', 'export', true),
(0, 'stations', 'view', true),
(0, 'stations', 'create', true),
(0, 'stations', 'edit', true),
(0, 'parallel', 'view', true),
(0, 'parallel', 'create', true),
(0, 'parallel', 'control', true),
(0, 'audit', 'view', true),
(0, 'admin', 'view', true),
(0, 'admin', 'manage', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 验证超级管理员权限
SELECT role, resource, action, is_allowed 
FROM role_permissions 
WHERE role = 0 
ORDER BY resource, action;
