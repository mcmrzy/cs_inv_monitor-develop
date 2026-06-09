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

-- SUPER_ADMIN (0): all permissions
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

-- AGENT (1): everything except admin/audit manage
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(1, 'devices', 'view', true),
(1, 'devices', 'create', true),
(1, 'devices', 'edit', true),
(1, 'devices', 'delete', true),
(1, 'devices', 'export', true),
(1, 'devices', 'control', true),
(1, 'devices', 'manage', true),
(1, 'users', 'view', true),
(1, 'users', 'create', true),
(1, 'users', 'edit', true),
(1, 'users', 'delete', true),
(1, 'users', 'manage', true),
(1, 'alerts', 'view', true),
(1, 'alerts', 'manage', true),
(1, 'alert_rules', 'view', true),
(1, 'alert_rules', 'create', true),
(1, 'alert_rules', 'edit', true),
(1, 'alert_rules', 'delete', true),
(1, 'work_orders', 'view', true),
(1, 'work_orders', 'create', true),
(1, 'work_orders', 'edit', true),
(1, 'work_orders', 'manage', true),
(1, 'firmware', 'view', true),
(1, 'firmware', 'create', true),
(1, 'firmware', 'delete', true),
(1, 'ota', 'view', true),
(1, 'ota', 'create', true),
(1, 'ota', 'control', true),
(1, 'dashboard', 'view', true),
(1, 'dashboard', 'export', true),
(1, 'stations', 'view', true),
(1, 'stations', 'create', true),
(1, 'stations', 'edit', true),
(1, 'parallel', 'view', true),
(1, 'parallel', 'create', true),
(1, 'parallel', 'control', true),
(1, 'audit', 'view', true),
(1, 'admin', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- INSTALLER (2): view devices/alerts/stations, basic device ops, create end_users
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(2, 'devices', 'view', true),
(2, 'devices', 'edit', true),
(2, 'devices', 'create', true),
(2, 'devices', 'control', true),
(2, 'devices', 'export', true),
(2, 'alerts', 'view', true),
(2, 'alerts', 'manage', true),
(2, 'work_orders', 'view', true),
(2, 'work_orders', 'create', true),
(2, 'work_orders', 'edit', true),
(2, 'stations', 'view', true),
(2, 'stations', 'create', true),
(2, 'dashboard', 'view', true),
(2, 'users', 'view', true),
(2, 'users', 'create', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- END_USER (3): view own devices/alerts/dashboard only
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(3, 'devices', 'view', true),
(3, 'alerts', 'view', true),
(3, 'dashboard', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;
