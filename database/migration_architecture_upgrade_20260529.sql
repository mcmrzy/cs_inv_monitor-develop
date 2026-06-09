-- ============================================
-- 架构升级迁移脚本
-- 适用: PostgreSQL 15+ / TimescaleDB
-- 目标: 10w+设备 + 多型号动态字段 + 标准RBAC + 数据权限
-- 执行: psql -U postgres -d inv_mqtt -f migration_architecture_upgrade_20260529.sql
-- ============================================

BEGIN;

-- ============================================
-- 1. RBAC 升级：标准 6 表权限体系
-- ============================================

-- 1.1 角色表（独立出来，支持自定义角色）
CREATE TABLE IF NOT EXISTS sys_role (
    id BIGSERIAL PRIMARY KEY,
    role_code VARCHAR(32) NOT NULL UNIQUE,
    role_name VARCHAR(64) NOT NULL,
    role_level INT NOT NULL, -- 角色层级（数字越小权限越高）
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT false, -- 系统内置角色不可删除
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 预置系统角色
INSERT INTO sys_role (role_code, role_name, role_level, description, is_system) VALUES
('super_admin', '超级管理员', 0, '拥有所有权限，可管理所有设备和用户', true),
('agent', '代理商', 1, '可管理下属安装商和用户，查看区域设备', true),
('installer', '安装商', 2, '可管理自己安装的设备，创建终端用户', true),
('end_user', '终端用户', 3, '只能查看和操作自己名下的设备', true)
ON CONFLICT (role_code) DO NOTHING;

-- 1.2 用户-角色关联表（支持多角色）
CREATE TABLE IF NOT EXISTS sys_user_role (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL REFERENCES sys_role(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, role_id)
);
CREATE INDEX IF NOT EXISTS idx_user_role_user ON sys_user_role(user_id);
CREATE INDEX IF NOT EXISTS idx_user_role_role ON sys_user_role(role_id);

-- 迁移现有 users.role 字段数据到 sys_user_role
INSERT INTO sys_user_role (user_id, role_id)
SELECT u.id, sr.id
FROM users u
JOIN sys_role sr ON sr.role_level = (
    CASE u.role
        WHEN 0 THEN 0 -- SUPER_ADMIN
        WHEN 1 THEN 1 -- AGENT
        WHEN 2 THEN 2 -- INSTALLER
        WHEN 3 THEN 3 -- END_USER
        ELSE 3        -- 默认终端用户
    END
)
WHERE NOT EXISTS (
    SELECT 1 FROM sys_user_role sur WHERE sur.user_id = u.id
);

-- 1.3 功能权限表（独立权限定义）
CREATE TABLE IF NOT EXISTS sys_permission (
    id BIGSERIAL PRIMARY KEY,
    perm_code VARCHAR(64) NOT NULL UNIQUE,
    resource VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    perm_name VARCHAR(128) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_perm_resource ON sys_permission(resource);

-- 从 role_permissions 提取去重权限
INSERT INTO sys_permission (perm_code, resource, action, perm_name)
SELECT DISTINCT
    resource || ':' || action,
    resource,
    action,
    INITCAP(resource) || ' ' || INITCAP(action)
FROM role_permissions
WHERE NOT EXISTS (
    SELECT 1 FROM sys_permission sp WHERE sp.perm_code = role_permissions.resource || ':' || role_permissions.action
);

-- 1.4 角色-权限关联表（替代 role_permissions 的扁平设计）
CREATE TABLE IF NOT EXISTS sys_role_permission (
    id BIGSERIAL PRIMARY KEY,
    role_id BIGINT NOT NULL REFERENCES sys_role(id) ON DELETE CASCADE,
    permission_id BIGINT NOT NULL REFERENCES sys_permission(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(role_id, permission_id)
);
CREATE INDEX IF NOT EXISTS idx_role_perm_role ON sys_role_permission(role_id);
CREATE INDEX IF NOT EXISTS idx_role_perm_perm ON sys_role_permission(permission_id);

-- 迁移现有 role_permissions 数据
INSERT INTO sys_role_permission (role_id, permission_id)
SELECT sr.id, sp.id
FROM role_permissions rp
JOIN sys_role sr ON sr.role_level = rp.role
JOIN sys_permission sp ON sp.resource = rp.resource AND sp.action = rp.action
WHERE NOT EXISTS (
    SELECT 1 FROM sys_role_permission srp
    WHERE srp.role_id = sr.id AND srp.permission_id = sp.id
);

-- 1.5 设备分组表（数据权限维度）
CREATE TABLE IF NOT EXISTS device_group (
    id BIGSERIAL PRIMARY KEY,
    group_name VARCHAR(128) NOT NULL,
    parent_id BIGINT,
    group_path VARCHAR(500), -- 层级路径，如 /1/5/12/
    created_by BIGINT,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_group_parent ON device_group(parent_id);

COMMENT ON TABLE device_group IS '设备分组表 - 用于数据权限控制';

-- 1.6 用户-设备关联表（数据权限核心）
CREATE TABLE IF NOT EXISTS user_device_rel (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    device_id BIGINT NOT NULL,
    permission_level VARCHAR(20) NOT NULL DEFAULT 'view', -- view/control/manage
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_user_device_user ON user_device_rel(user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_device ON user_device_rel(device_id);

COMMENT ON TABLE user_device_rel IS '用户-设备权限关联表 - 控制用户可访问哪些设备';

-- 1.7 用户-设备组关联表（批量授权用）
CREATE TABLE IF NOT EXISTS user_device_group_rel (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    group_id BIGINT NOT NULL,
    permission_level VARCHAR(20) NOT NULL DEFAULT 'view',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, group_id)
);
CREATE INDEX IF NOT EXISTS idx_user_group_user ON user_device_group_rel(user_id);

-- ============================================
-- 2. 设备型号元数据升级
-- ============================================

-- 2.1 型号字段定义表（结构化存储，替代纯 JSONB）
CREATE TABLE IF NOT EXISTS device_model_field (
    id BIGSERIAL PRIMARY KEY,
    model_id INT NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
    field_key VARCHAR(64) NOT NULL, -- 后端唯一标识
    field_name VARCHAR(128) NOT NULL, -- 前端展示名
    field_type VARCHAR(32) NOT NULL, -- int/float/string/bool
    unit VARCHAR(32), -- 单位 V/A/kW/℃
    sort INT NOT NULL DEFAULT 0, -- 前端排序
    is_show BOOLEAN NOT NULL DEFAULT true, -- 是否默认展示
    is_control BOOLEAN NOT NULL DEFAULT false, -- 是否可控制
    parse_rule TEXT, -- 解析规则：倍率/偏移量/公式
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model_id, field_key)
);
CREATE INDEX IF NOT EXISTS idx_model_field_model ON device_model_field(model_id);

COMMENT ON TABLE device_model_field IS '型号字段定义表 - 新增型号只需配置元数据';

-- 2.2 从现有 device_models.data_fields JSONB 提取字段定义
DO $$
DECLARE
    model_record RECORD;
    field_key TEXT;
    field_def JSONB;
BEGIN
    FOR model_record IN SELECT id, data_fields FROM device_models WHERE is_active = true LOOP
        FOR field_key, field_def IN
            SELECT key, value
            FROM jsonb_each(model_record.data_fields)
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM device_model_field
                WHERE model_id = model_record.id AND field_key = field_key
            ) THEN
                INSERT INTO device_model_field (model_id, field_key, field_name, field_type, unit, sort, is_show)
                VALUES (
                    model_record.id,
                    field_key,
                    COALESCE(field_def->>'label', field_key),
                    COALESCE(field_def->>'type', 'string'),
                    field_def->>'unit',
                    0,
                    true
                );
            END IF;
        END LOOP;
    END LOOP;
END $$;

-- 2.3 设备型号协议配置表（支持不同型号的不同 topic 解析规则）
CREATE TABLE IF NOT EXISTS device_model_protocol (
    id BIGSERIAL PRIMARY KEY,
    model_id INT NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
    topic_pattern VARCHAR(200) NOT NULL, -- topic 匹配模式
    parse_type VARCHAR(32) NOT NULL DEFAULT 'json', -- json/modbus/custom
    parse_config JSONB, -- 解析配置
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model_id, topic_pattern)
);
CREATE INDEX IF NOT EXISTS idx_model_protocol_model ON device_model_protocol(model_id);

COMMENT ON TABLE device_model_protocol IS '型号协议配置表 - 不同型号可能有不同 topic 和解析规则';

-- ============================================
-- 3. 设备档案升级（适配 10w+ 设备）
-- ============================================

-- 3.1 设备表增加新字段
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model_id INT REFERENCES device_models(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS group_id BIGINT REFERENCES device_group(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS region VARCHAR(64);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS install_time TIMESTAMPTZ;

-- 3.2 设备-型号关联索引
CREATE INDEX IF NOT EXISTS idx_devices_model ON devices(model_id);
CREATE INDEX IF NOT EXISTS idx_devices_group ON devices(group_id);

-- 3.3 迁移现有设备的 model_id
UPDATE devices d
SET model_id = dm.id
FROM device_models dm
WHERE d.model = dm.model_code
  AND d.model_id IS NULL;

-- ============================================
-- 4. 时序存储优化（TimescaleDB 增强）
-- 注意：需要先安装 TimescaleDB 扩展，见 migration_timescaledb_install.sql
-- ============================================

-- 4.1 检查 TimescaleDB 是否已安装
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        CREATE EXTENSION IF NOT EXISTS timescaledb;
        RAISE NOTICE 'TimescaleDB extension installed';
    ELSE
        RAISE NOTICE 'TimescaleDB not installed, skipping hypertable setup. Please run migration_timescaledb_install.sql after installing the extension.';
        RETURN;
    END IF;
END $$;

-- 以下语句仅在 TimescaleDB 可用时执行
DO $$
BEGIN
    -- 检查超表是否已创建
    IF NOT EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_telemetry') THEN
        -- 如果表已有数据，需要 migrate_data => true
        PERFORM create_hypertable('device_telemetry', 'time', if_not_exists => TRUE, migrate_data => TRUE);
        RAISE NOTICE 'Hypertable created (with data migration)';
    END IF;
END $$;

-- 4.3 启用压缩（如果 TimescaleDB 可用且还没启用）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.hypertables
            WHERE hypertable_name = 'device_telemetry'
            AND compression_state = 'Compressed'
        ) THEN
            ALTER TABLE device_telemetry SET (
                timescaledb.compress,
                timescaledb.compress_segmentby = 'device_sn',
                timescaledb.compress_orderby = 'time DESC'
            );
        END IF;
    END IF;
END $$;

-- 4.4 压缩策略（7天前的数据自动压缩）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        PERFORM add_compression_policy('device_telemetry', INTERVAL '7 days', if_not_exists => TRUE);
    END IF;
END $$;

-- 4.5 连续聚合：1分钟降采样
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1min
        WITH (timescaledb.continuous) AS
        SELECT
            time_bucket('1 minute', time) AS bucket,
            device_sn,
            model_code,
            AVG(total_active_power) AS avg_active_power,
            MAX(total_active_power) AS max_active_power,
            MIN(total_active_power) AS min_active_power,
            AVG(internal_temperature) AS avg_temperature,
            MAX(internal_temperature) AS max_temperature,
            LAST(daily_energy, time) - FIRST(daily_energy, time) AS energy_delta,
            LAST(work_state, time) AS work_state,
            LAST(fault_code, time) AS fault_code
        FROM device_telemetry
        GROUP BY bucket, device_sn, model_code;

        PERFORM add_continuous_aggregate_policy('device_telemetry_1min',
            start_offset    => INTERVAL '2 minutes',
            end_offset      => INTERVAL '1 minute',
            schedule_interval => INTERVAL '1 minute',
            if_not_exists   => TRUE
        );
    END IF;
END $$;

-- 连续聚合：1小时降采样
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1hour
        WITH (timescaledb.continuous) AS
        SELECT
            time_bucket('1 hour', time) AS bucket,
            device_sn,
            model_code,
            AVG(total_active_power) AS avg_active_power,
            MAX(total_active_power) AS max_active_power,
            AVG(internal_temperature) AS avg_temperature,
            LAST(daily_energy, time) - FIRST(daily_energy, time) AS energy_delta,
            COUNT(*) AS sample_count,
            SUM(CASE WHEN total_active_power > 0 THEN 1 ELSE 0 END) AS run_minutes
        FROM device_telemetry
        GROUP BY bucket, device_sn, model_code;

        PERFORM add_continuous_aggregate_policy('device_telemetry_1hour',
            start_offset    => INTERVAL '2 hours',
            end_offset      => INTERVAL '1 hour',
            schedule_interval => INTERVAL '1 hour',
            if_not_exists   => TRUE
        );
    END IF;
END $$;

-- 连续聚合：1天降采样
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1day
        WITH (timescaledb.continuous) AS
        SELECT
            time_bucket('1 day', time) AS bucket,
            device_sn,
            model_code,
            AVG(total_active_power) AS avg_active_power,
            MAX(total_active_power) AS max_active_power,
            SUM(CASE WHEN total_active_power > 0 THEN 1 ELSE 0 END) AS run_minutes,
            LAST(daily_energy, time) AS daily_energy
        FROM device_telemetry
        GROUP BY bucket, device_sn, model_code;

        PERFORM add_continuous_aggregate_policy('device_telemetry_1day',
            start_offset    => INTERVAL '2 days',
            end_offset      => INTERVAL '1 day',
            schedule_interval => INTERVAL '1 day',
            if_not_exists   => TRUE
        );
    END IF;
END $$;

-- 4.6 原始数据保留策略（90天）
-- SELECT add_retention_policy('device_telemetry', INTERVAL '90 days', if_not_exists => TRUE);

-- ============================================
-- 5. 优化视图
-- ============================================

-- 5.1 设备最新数据视图（带型号字段定义）
CREATE OR REPLACE VIEW v_device_latest_with_fields AS
SELECT DISTINCT ON (dt.device_sn)
    dt.device_sn,
    dt.model_code,
    dt.data,
    dt.total_active_power,
    dt.daily_energy,
    dt.work_state,
    dt.fault_code,
    dt.internal_temperature,
    dt.time as data_time,
    d.model_id,
    d.status,
    d.station_id,
    d.user_id,
    -- 动态字段（JSONB 提取，按型号字段定义）
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'key', f.field_key,
                'name', f.field_name,
                'type', f.field_type,
                'unit', f.unit,
                'value', dt.data->f.field_key
            )
        )
        FROM device_model_field f
        WHERE f.model_id = d.model_id
          AND f.is_show = true
    ) as display_fields
FROM device_telemetry dt
JOIN devices d ON d.sn = dt.device_sn
ORDER BY dt.device_sn, dt.time DESC;

-- 5.2 用户设备权限视图（数据权限查询用）
CREATE OR REPLACE VIEW v_user_device_access AS
SELECT
    u.id as user_id,
    u.role as user_role,
    d.id as device_id,
    d.sn as device_sn,
    d.model,
    d.status as device_status,
    COALESCE(udr.permission_level, 'view') as permission_level
FROM users u
JOIN devices d ON (
    -- 管理员/代理商：看所有设备
    u.role <= 1
    OR
    -- 安装商：看自己安装的设备（installer_id）
    (u.role = 2 AND d.installer_id = u.id)
    OR
    -- 终端用户：看自己名下的设备
    (u.role = 3 AND d.user_id = u.id)
    OR
    -- 显式授权的设备
    EXISTS (
        SELECT 1 FROM user_device_rel udr2
        WHERE udr2.user_id = u.id AND udr2.device_id = d.id
    )
    OR
    -- 设备组授权
    EXISTS (
        SELECT 1 FROM user_device_group_rel udgr
        JOIN device_group dg ON dg.id = udgr.group_id
        WHERE udgr.user_id = u.id
        AND d.group_id = dg.id
    )
)
LEFT JOIN user_device_rel udr ON udr.user_id = u.id AND udr.device_id = d.id
WHERE d.deleted_at IS NULL;

-- ============================================
-- 6. 系统配置更新
-- ============================================

INSERT INTO system_configs (config_key, config_value, description) VALUES
('rbac_enabled', 'true', '是否启用标准RBAC权限体系'),
('data_retention_days', '90', '时序数据保留天数（TimescaleDB 控制）'),
('compression_age_days', '7', '数据压缩延迟天数'),
('max_telemetry_batch_size', '1000', '时序数据批量插入大小'),
('kafka_enabled', 'false', '是否启用Kafka消息队列')
ON CONFLICT (config_key) DO NOTHING;

COMMIT;

SELECT 'MIGRATION_ARCHITECTURE_UPGRADE_OK' as result;
