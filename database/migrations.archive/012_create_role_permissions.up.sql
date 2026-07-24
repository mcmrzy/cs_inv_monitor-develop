-- 012_create_role_permissions: RBAC角色权限表
-- 创建角色权限映射表，用于API网关RBAC中间件的权限校验
CREATE TABLE IF NOT EXISTS role_permissions (
    id BIGSERIAL PRIMARY KEY,
    role SMALLINT NOT NULL,
    resource VARCHAR(50) NOT NULL,
    action VARCHAR(20) NOT NULL,
    is_allowed BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(role, resource, action)
);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role ON role_permissions(role);

-- 角色定义 (来自 users 表 role 字段注释):
--   0: 原厂(超级管理员) - 代码中硬编码跳过RBAC检查，无需配置
--   1: 总代理
--   2: 经销商
--   3: 经销商 (与role=2相同权限)
--   4: 安装商
--   5: 普通用户(终端用户)

-- 资源列表 (来自 rbac.go resourceActionMap):
--   stations, devices, alerts, ota, firmware, users, admin, parallel

-- 总代理 (role=1): 拥有除admin外的所有资源完整权限
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(1, 'stations', 'view', true),
(1, 'stations', 'create', true),
(1, 'stations', 'edit', true),
(1, 'stations', 'delete', true),
(1, 'devices', 'view', true),
(1, 'devices', 'create', true),
(1, 'devices', 'edit', true),
(1, 'devices', 'delete', true),
(1, 'alerts', 'view', true),
(1, 'alerts', 'edit', true),
(1, 'ota', 'view', true),
(1, 'ota', 'create', true),
(1, 'ota', 'edit', true),
(1, 'firmware', 'view', true),
(1, 'firmware', 'create', true),
(1, 'users', 'view', true),
(1, 'users', 'create', true),
(1, 'users', 'edit', true),
(1, 'admin', 'view', true),
(1, 'parallel', 'view', true),
(1, 'parallel', 'create', true),
(1, 'parallel', 'edit', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 经销商 (role=2): 管理自己下属的电站/设备/告警
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(2, 'stations', 'view', true),
(2, 'stations', 'create', true),
(2, 'stations', 'edit', true),
(2, 'devices', 'view', true),
(2, 'devices', 'create', true),
(2, 'devices', 'edit', true),
(2, 'alerts', 'view', true),
(2, 'alerts', 'edit', true),
(2, 'ota', 'view', true),
(2, 'ota', 'create', true),
(2, 'firmware', 'view', true),
(2, 'users', 'view', true),
(2, 'parallel', 'view', true),
(2, 'parallel', 'create', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 经销商 (role=3): 与role=2权限相同
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(3, 'stations', 'view', true),
(3, 'stations', 'create', true),
(3, 'stations', 'edit', true),
(3, 'devices', 'view', true),
(3, 'devices', 'create', true),
(3, 'devices', 'edit', true),
(3, 'alerts', 'view', true),
(3, 'alerts', 'edit', true),
(3, 'ota', 'view', true),
(3, 'ota', 'create', true),
(3, 'firmware', 'view', true),
(3, 'users', 'view', true),
(3, 'parallel', 'view', true),
(3, 'parallel', 'create', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 安装商 (role=4): 设备安装和基本查看权限
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(4, 'stations', 'view', true),
(4, 'devices', 'view', true),
(4, 'devices', 'create', true),
(4, 'devices', 'edit', true),
(4, 'alerts', 'view', true),
(4, 'ota', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;

-- 普通用户/终端用户 (role=5): 只读权限
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
(5, 'stations', 'view', true),
(5, 'devices', 'view', true),
(5, 'alerts', 'view', true),
(5, 'ota', 'view', true)
ON CONFLICT (role, resource, action) DO NOTHING;
