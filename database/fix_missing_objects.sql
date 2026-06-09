-- ============================================
-- 修复缺失的表、视图和列
-- 日期: 2026-06-01
-- ============================================

-- 1. devices 表补充缺失列
ALTER TABLE devices ADD COLUMN IF NOT EXISTS manufacturer VARCHAR(100);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_arm VARCHAR(50);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_esp VARCHAR(50);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_type VARCHAR(50);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_power DECIMAL(10,2);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_voltage INTEGER;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_freq DECIMAL(6,2);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_voltage DECIMAL(8,2);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_type VARCHAR(50);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS cell_count INTEGER;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS installer_id BIGINT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS last_online_at TIMESTAMP;

-- 2. users 表补充 email 列（如果缺失）
ALTER TABLE users ADD COLUMN IF NOT EXISTS email VARCHAR(255);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- 3. 用户设备关联表
CREATE TABLE IF NOT EXISTS user_device_rel (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    device_sn VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, device_sn)
);

-- 4. 设备遥测数据表
CREATE TABLE IF NOT EXISTS device_telemetry (
    id          BIGSERIAL,
    device_sn   VARCHAR(50) NOT NULL,
    model_code  VARCHAR(50),
    topic       VARCHAR(200),
    data        JSONB NOT NULL,
    total_active_power DECIMAL(12,2) DEFAULT 0,
    daily_energy       DECIMAL(14,4) DEFAULT 0,
    work_state         VARCHAR(50),
    fault_code         VARCHAR(50),
    internal_temperature DECIMAL(6,1) DEFAULT 0,
    time               TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time ON device_telemetry(device_sn, time DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_model ON device_telemetry(model_code);
CREATE INDEX IF NOT EXISTS idx_telemetry_time ON device_telemetry(time DESC);

-- 5. 设备日统计表
CREATE TABLE IF NOT EXISTS device_day_data (
    device_sn VARCHAR(50) NOT NULL,
    data_date DATE NOT NULL,
    energy_produce DECIMAL(12,4) DEFAULT 0,
    run_minutes INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (device_sn, data_date)
);
CREATE INDEX IF NOT EXISTS idx_device_day_data_date ON device_day_data(data_date);

-- 6. 电站日统计表
CREATE TABLE IF NOT EXISTS station_day_data (
    station_id BIGINT NOT NULL,
    data_date DATE NOT NULL,
    energy_produce DECIMAL(12,4) DEFAULT 0,
    income DECIMAL(12,4) DEFAULT 0,
    device_count INTEGER DEFAULT 0,
    online_count INTEGER DEFAULT 0,
    fault_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (station_id, data_date)
);
CREATE INDEX IF NOT EXISTS idx_station_day_data_date ON station_day_data(data_date);

-- 7. 设备命令日志表
CREATE TABLE IF NOT EXISTS device_cmd_logs (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    cmd VARCHAR(50) NOT NULL,
    result VARCHAR(20),
    message TEXT,
    sent_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn ON device_cmd_logs(device_sn);

-- 8. 设备告警事件表
CREATE TABLE IF NOT EXISTS device_alarms (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    event_type VARCHAR(50),
    source VARCHAR(50),
    fault_code INTEGER,
    fault_desc TEXT,
    alarm_code INTEGER,
    trigger_info JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_alarms_sn ON device_alarms(device_sn);
CREATE INDEX IF NOT EXISTS idx_device_alarms_created ON device_alarms(created_at DESC);

-- 9. 权限相关表
CREATE TABLE IF NOT EXISTS role_permissions (
    id BIGSERIAL PRIMARY KEY,
    role INTEGER NOT NULL,
    resource VARCHAR(100) NOT NULL,
    action VARCHAR(100) NOT NULL,
    is_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (role, resource, action)
);

CREATE TABLE IF NOT EXISTS sys_user_role (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    UNIQUE (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS sys_role_permission (
    id BIGSERIAL PRIMARY KEY,
    role_id BIGINT NOT NULL,
    permission_id BIGINT NOT NULL,
    UNIQUE (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS sys_permission (
    id BIGSERIAL PRIMARY KEY,
    resource VARCHAR(100) NOT NULL,
    action VARCHAR(100) NOT NULL,
    description VARCHAR(200),
    UNIQUE (resource, action)
);

-- 10. v_device_latest 视图
CREATE OR REPLACE VIEW v_device_latest AS
SELECT DISTINCT ON (dt.device_sn)
    dt.device_sn,
    dt.model_code,
    dt.topic,
    dt.data,
    dt.total_active_power,
    dt.daily_energy,
    dt.work_state,
    dt.fault_code,
    dt.internal_temperature,
    dt.time as data_time,
    dt.created_at as updated_at
FROM device_telemetry dt
ORDER BY dt.device_sn, dt.time DESC;

-- 11. v_user_device_access 视图
CREATE OR REPLACE VIEW v_user_device_access AS
SELECT
    udr.user_id,
    udr.device_sn
FROM user_device_rel udr;

-- 完成
SELECT 'Migration completed successfully' AS result;
