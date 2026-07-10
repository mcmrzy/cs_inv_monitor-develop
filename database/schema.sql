-- 辰烁科技光伏逆变器APP数据库设计
-- 数据库: PostgreSQL 15+
-- 字符集: UTF-8

-- ============================================
-- 1. 用户相关表
-- ============================================

-- 用户表
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(100),
    password_hash VARCHAR(255) NOT NULL,
    nickname VARCHAR(50),
    avatar VARCHAR(500),
    role SMALLINT NOT NULL DEFAULT 5, -- 1:原厂 2:总代理 3:经销商 4:安装商 5:用户
    region_id BIGINT, -- 所属区域(代理商/经销商)
    parent_id BIGINT, -- 上级用户ID
    timezone VARCHAR(50) DEFAULT 'Asia/Shanghai',
    status SMALLINT NOT NULL DEFAULT 1, -- 1:正常 0:禁用
    last_login_at TIMESTAMPTZ,
    last_login_ip VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_email_col ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_region ON users(region_id);
CREATE INDEX idx_users_parent ON users(parent_id);

-- 用户操作日志表
CREATE TABLE user_operation_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    device_sn VARCHAR(50),
    operation_type VARCHAR(50) NOT NULL, -- login/logout/device_control/param_modify/ota_upgrade
    operation_detail JSONB,
    result VARCHAR(20) NOT NULL, -- success/failed
    error_message TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_operation_logs_user ON user_operation_logs(user_id);
CREATE INDEX idx_operation_logs_device ON user_operation_logs(device_sn);
CREATE INDEX idx_operation_logs_time ON user_operation_logs(created_at);

-- 用户会话表
CREATE TABLE user_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    device_type VARCHAR(20), -- ios/android/web
    device_id VARCHAR(100),
    ip_address VARCHAR(45),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(token_hash);

-- 验证码表
CREATE TABLE verification_codes (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    code VARCHAR(6) NOT NULL,
    type VARCHAR(20) NOT NULL, -- register/reset_password/login
    expires_at TIMESTAMPTZ NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verify_code_phone_type ON verification_codes(phone, type);

-- ============================================
-- 2. 电站相关表
-- ============================================

-- 区域表(省市区)
CREATE TABLE regions (
    id BIGSERIAL PRIMARY KEY,
    parent_id BIGINT,
    name VARCHAR(50) NOT NULL,
    level SMALLINT NOT NULL, -- 1:省 2:市 3:区
    code VARCHAR(20) NOT NULL UNIQUE
);

CREATE INDEX idx_regions_parent ON regions(parent_id);

-- 电站表
CREATE TABLE stations (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    name VARCHAR(100) NOT NULL,
    province VARCHAR(50) NOT NULL,
    city VARCHAR(50) NOT NULL,
    district VARCHAR(50),
    address VARCHAR(200) NOT NULL,
    capacity DECIMAL(10,2) NOT NULL, -- 装机容量(kW)
    panel_count INTEGER,
    peak_price DECIMAL(10,4), -- 峰电价
    valley_price DECIMAL(10,4), -- 谷电价
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),
    timezone VARCHAR(50) NOT NULL DEFAULT 'Asia/Shanghai', -- 电站所在时区, IANA 时区标识符
    status SMALLINT NOT NULL DEFAULT 1, -- 1:正常 0:禁用
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_stations_user ON stations(user_id);
CREATE INDEX idx_stations_location ON stations(province, city, district);
CREATE INDEX idx_stations_timezone ON stations(timezone);

-- ============================================
-- 3. 设备相关表
-- ============================================

-- 设备表
CREATE TABLE devices (
    id BIGSERIAL PRIMARY KEY,
    sn VARCHAR(50) NOT NULL UNIQUE,
    model VARCHAR(100),
    manufacturer VARCHAR(100) DEFAULT '',       -- 制造商
    firmware_arm VARCHAR(50) DEFAULT '',        -- ARM固件版本
    firmware_esp VARCHAR(50) DEFAULT '',        -- ESP固件版本
    firmware_dsp VARCHAR(50) DEFAULT '',        -- DSP固件版本
    firmware_bms VARCHAR(50) DEFAULT '',        -- BMS固件版本
    main_version VARCHAR(50) DEFAULT '',        -- 主版本号
    device_type VARCHAR(50) DEFAULT '',         -- 设备类型
    rated_power DECIMAL(10,2),                  -- 额定功率(kW)
    rated_voltage DECIMAL(10,2) DEFAULT 0,      -- 额定电压(V)
    rated_freq DECIMAL(5,2) DEFAULT 0,          -- 额定频率(Hz)
    battery_voltage DECIMAL(10,2) DEFAULT 0,    -- 电池电压(V)
    battery_type VARCHAR(50) DEFAULT '',        -- 电池类型
    cell_count INTEGER DEFAULT 0,               -- 电池节数
    firmware_version VARCHAR(50),
    hardware_version VARCHAR(50),
    mac_address VARCHAR(17),
    station_id BIGINT,
    user_id BIGINT NOT NULL,
    timezone VARCHAR(50) NOT NULL DEFAULT 'Asia/Shanghai', -- 设备所在时区, 继承自所属电站
    status SMALLINT NOT NULL DEFAULT 0, -- 0:离线 1:在线 2:故障
    last_online_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_devices_sn ON devices(sn);
CREATE INDEX idx_devices_station ON devices(station_id);
CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_status ON devices(status);
CREATE INDEX idx_devices_timezone ON devices(timezone);

-- [已废弃] 设备实时数据表 - 已由 device_telemetry 超表替代
-- CREATE TABLE device_realtime_data (...);

-- [已废弃] 设备历史数据表(分钟级) - 已由 TimescaleDB device_telemetry_1min 连续聚合替代
-- CREATE TABLE device_minute_data (...);

-- [已废弃] 设备历史数据表(小时级) - 已由 TimescaleDB device_telemetry_1hour 连续聚合替代
-- CREATE TABLE device_hour_data (...);

-- [已废弃] 设备历史数据表(日级) - 已由 TimescaleDB device_telemetry_1day 连续聚合替代
-- CREATE TABLE device_day_data (...);

-- [已废弃] 设备参数设置表 - 改用 MQTT 直接配置
-- CREATE TABLE device_params (...);

-- ============================================
-- 4. 告警相关表
-- ============================================

-- 告警表
CREATE TABLE alarms (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    station_id BIGINT,
    user_id BIGINT NOT NULL,
    alarm_level SMALLINT NOT NULL, -- 1:提示(info) 2:警告(warning) 3:严重(fault)
    fault_code VARCHAR(20) NOT NULL,
    fault_message VARCHAR(200) NOT NULL,
    fault_detail TEXT,
    status SMALLINT NOT NULL DEFAULT 0, -- 0:未处理 1:已处理 2:已忽略
    occurred_at TIMESTAMPTZ NOT NULL,
    recovered_at TIMESTAMPTZ,
    handled_at TIMESTAMPTZ,
    handled_by BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alarms_device ON alarms(device_sn);
CREATE INDEX idx_alarms_station ON alarms(station_id);
CREATE INDEX idx_alarms_user ON alarms(user_id);
CREATE INDEX idx_alarms_status ON alarms(status);
CREATE INDEX idx_alarms_time ON alarms(occurred_at);

-- 告警通知记录表
CREATE TABLE alarm_notifications (
    id BIGSERIAL PRIMARY KEY,
    alarm_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    notify_type VARCHAR(20) NOT NULL, -- push/sms/email
    notify_status VARCHAR(20) NOT NULL, -- pending/sent/failed
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alarm_notify_alarm ON alarm_notifications(alarm_id);
CREATE INDEX idx_alarm_notify_user ON alarm_notifications(user_id);

-- 系统通知表（设备上下线等）
CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    station_id BIGINT,
    user_id BIGINT NOT NULL,
    notify_type VARCHAR(30) NOT NULL, -- device_online, device_offline, ota_available
    title VARCHAR(200) NOT NULL,
    content TEXT,
    status SMALLINT NOT NULL DEFAULT 0, -- 0:未读 1:已读
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_sn ON notifications(device_sn);
CREATE INDEX idx_notifications_type ON notifications(notify_type);
CREATE INDEX idx_notifications_time ON notifications(created_at);

-- ============================================
-- 5. [已废弃] 设备分享表 - 功能已移除
-- ============================================

-- ============================================
-- 6. [已废弃] station_day_data - 已由 TimescaleDB 连续聚合替代
-- ============================================

-- ============================================
-- 7. [已废弃] 消息推送表 - user_notify_settings / messages 已移除
-- ============================================

-- ============================================
-- 8. OTA升级相关表
-- ============================================

-- 固件版本表
CREATE TABLE firmware_versions (
    id BIGSERIAL PRIMARY KEY,
    model VARCHAR(100) NOT NULL,
    version VARCHAR(50) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size BIGINT,
    file_md5 VARCHAR(32),
    changelog TEXT,
    is_force BOOLEAN DEFAULT FALSE,
    status SMALLINT DEFAULT 1, -- 1:正常 0:禁用
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model, version)
);

CREATE INDEX idx_firmware_model ON firmware_versions(model);

-- OTA升级记录表
CREATE TABLE ota_records (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    firmware_id BIGINT NOT NULL,
    old_version VARCHAR(50),
    new_version VARCHAR(50),
    status VARCHAR(20) NOT NULL, -- pending/downloading/upgrading/success/failed
    progress INTEGER DEFAULT 0,
    error_message TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ota_device ON ota_records(device_sn);
CREATE INDEX idx_ota_status ON ota_records(status);

-- ============================================
-- 9. 系统配置表
-- ============================================

-- 系统配置表
CREATE TABLE system_configs (
    id BIGSERIAL PRIMARY KEY,
    config_key VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT,
    description VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 初始化系统配置
INSERT INTO system_configs (config_key, config_value, description) VALUES
('mqtt_broker_url', 'tcp://localhost:1883', 'MQTT Broker地址'),
('mqtt_ws_url', 'ws://localhost:8083/mqtt', 'MQTT WebSocket地址'),
('token_expire_hours', '168', 'Token过期时间(小时)'),
('verify_code_expire_minutes', '5', '验证码过期时间(分钟)'),
('data_retention_days', '365', '数据保留天数'),
('max_devices_per_user', '100', '每用户最大设备数'),
('max_stations_per_user', '20', '每用户最大电站数')
ON CONFLICT (config_key) DO NOTHING;

-- ============================================
-- 10. 视图
-- ============================================

-- [已废弃] v_station_realtime - 引用了已删除的 device_realtime_data 表
-- [已废弃] v_user_devices - 引用了已删除的 device_shares 表

-- ============================================
-- 11. 函数
-- ============================================

-- 更新时间戳函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为需要的表创建触发器（使用 DROP IF EXISTS 保证幂等，可安全重复执行）
DO $$ BEGIN
    DROP TRIGGER IF EXISTS update_users_updated_at ON users;
    CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
END $$;
DO $$ BEGIN
    DROP TRIGGER IF EXISTS update_stations_updated_at ON stations;
    CREATE TRIGGER update_stations_updated_at BEFORE UPDATE ON stations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
END $$;
DO $$ BEGIN
    DROP TRIGGER IF EXISTS update_devices_updated_at ON devices;
    CREATE TRIGGER update_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
END $$;
DO $$ BEGIN
    DROP TRIGGER IF EXISTS update_system_configs_updated_at ON system_configs;
    CREATE TRIGGER update_system_configs_updated_at BEFORE UPDATE ON system_configs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
END $$;

-- ============================================
-- 12. 清理过期数据函数
-- ============================================

CREATE OR REPLACE FUNCTION clean_expired_data()
RETURNS void AS $$
BEGIN
    -- 清理过期验证码
    DELETE FROM verification_codes WHERE expires_at < NOW();
    
    -- 注意：分钟级/小时级数据已由 TimescaleDB 自动管理
    -- user_sessions 已删除（改用 JWT）
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 时序遥测数据表（替代旧 device_realtime_data）
-- ============================================

-- 设备遥测数据表（时序超表，支持万级设备）
CREATE TABLE IF NOT EXISTS device_telemetry (
    id          BIGSERIAL,
    device_sn   VARCHAR(50) NOT NULL,
    model_code  VARCHAR(50),           -- 关联设备型号
    topic       VARCHAR(200),           -- 来源 Topic
    data        JSONB NOT NULL,         -- 原始 JSON 数据（完整保留）
    -- 常用索引字段（从 JSON 中提取，用于快速查询/排序）
    total_active_power DECIMAL(12,2) DEFAULT 0,
    daily_energy       DECIMAL(14,4) DEFAULT 0,
    work_state         VARCHAR(50),
    fault_code         VARCHAR(50),
    internal_temperature DECIMAL(6,1) DEFAULT 0,
    grid_frequency       NUMERIC(6,2),
    battery_soc          NUMERIC(4,1),
    battery_power        NUMERIC(10,2),
    pv_power             NUMERIC(10,2),
    time               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time ON device_telemetry(device_sn, time DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_model ON device_telemetry(model_code);
CREATE INDEX IF NOT EXISTS idx_telemetry_time ON device_telemetry(time DESC);

-- 最新数据视图（替代旧的实时表单行查询）
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
    dt.grid_frequency,
    dt.battery_soc,
    dt.battery_power,
    dt.pv_power,
    dt.time as data_time,
    dt.created_at as updated_at
FROM device_telemetry dt
ORDER BY dt.device_sn, dt.time DESC;

-- ============================================
-- 设备型号注册表
-- ============================================

CREATE TABLE IF NOT EXISTS device_models (
    id              SERIAL PRIMARY KEY,
    model_code      VARCHAR(50) NOT NULL UNIQUE,
    model_name      VARCHAR(100) NOT NULL,     -- 显示名称如 "5000TL 逆变器"
    manufacturer    VARCHAR(50),                -- 制造商
    category        VARCHAR(20) NOT NULL DEFAULT 'inverter',  -- inverter/battery/meter/hybrid
    rated_power_kw  DECIMAL(8,2) DEFAULT 0,    -- 额定功率 kW
    data_fields     JSONB NOT NULL DEFAULT '{}',  -- 该型号的标准字段定义
    field_mapping   JSONB NOT NULL DEFAULT '{}',  -- MQTT字段→标准字段映射
    mqtt_topics     JSONB NOT NULL DEFAULT '[]',  -- 该型号订阅的 Topic 列表
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE device_models IS '设备型号注册表 - 新型号只需在此配置，无需改代码';
COMMENT ON COLUMN device_models.data_fields IS 'JSON格式: {"total_active_power":{"type":"float","unit":"W","label":"总有功功率"}}';
COMMENT ON COLUMN device_models.field_mapping IS 'JSON格式: {"data/status":{"work_state":"work_state_1","temp":"internal_temperature"}}';

-- ============================================
-- 设备型号字段表（模块化字段定义）
-- ============================================

CREATE TABLE IF NOT EXISTS device_model_field (
    id          BIGSERIAL PRIMARY KEY,
    model_id    INT NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
    field_key   VARCHAR(64) NOT NULL,
    field_name  VARCHAR(128) NOT NULL,
    field_type  VARCHAR(32) NOT NULL,
    unit        VARCHAR(32),
    sort        INT NOT NULL DEFAULT 0,
    is_show     BOOLEAN NOT NULL DEFAULT true,
    is_control  BOOLEAN NOT NULL DEFAULT false,
    parse_rule  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model_id, field_key)
);

CREATE INDEX IF NOT EXISTS idx_model_field_model ON device_model_field(model_id);

CREATE TABLE IF NOT EXISTS device_model_protocol (
    id            BIGSERIAL PRIMARY KEY,
    model_id      INT NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
    topic_pattern VARCHAR(200) NOT NULL,
    parse_type    VARCHAR(32) NOT NULL DEFAULT 'json',
    parse_config  JSONB,
    is_active     BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model_id, topic_pattern)
);

CREATE INDEX IF NOT EXISTS idx_model_protocol_model ON device_model_protocol(model_id);

-- 预置一些常见型号
INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, data_fields, field_mapping, mqtt_topics) VALUES
('INV-5000-TL', 'INVT 5000TL 逆变器', 'INVT', 'inverter', 5.0,
 '{"serial_number":{"type":"string","label":"序列号"},"total_active_power":{"type":"float","unit":"W","label":"总有功功率"},"work_state_1":{"type":"string","label":"工作状态"},"work_state_1_code":{"type":"int","label":"状态码"},"internal_temperature":{"type":"float","unit":"℃","label":"内部温度"},"bus_voltage":{"type":"float","unit":"V","label":"母线电压"},"efficiency":{"type":"float","unit":"%","label":"转换效率"},"fault_code":{"type":"int","label":"故障码"},"daily_power_yields":{"type":"float","unit":"kWh","label":"日发电量"},"total_power_yields":{"type":"float","unit":"kWh","label":"总发电量"},"grid_frequency":{"type":"float","unit":"Hz","label":"电网频率"},"power_factor":{"type":"float","label":"功率因数"},"nominal_active_power":{"type":"float","unit":"W","label":"额定功率"},"output_type":{"type":"int","label":"输出类型"}}'::jsonb,
 '{"data/status":{"work_state":"work_state_1","temp":"internal_temperature","bus_voltage":"bus_voltage","efficiency":"efficiency","fault_code":"fault_code"},"data/ac":{"active_power":"total_active_power","frequency":"grid_frequency","pf":"power_factor"},"data/energy":{"daily":"daily_power_yields","total":"total_power_yields"}}'::jsonb,
 '["cs_inv/+/data/status", "cs_inv/+/data/ac", "cs_inv/+/data/energy"]'::jsonb)
ON CONFLICT (model_code) DO NOTHING;

-- ============================================
-- 设备告警、命令日志、日统计表
-- ============================================

CREATE TABLE IF NOT EXISTS device_alarms (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    event_type VARCHAR(50),
    source VARCHAR(50),
    fault_code INTEGER,
    fault_desc TEXT,
    alarm_code INTEGER,
    trigger_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_alarms_sn ON device_alarms(device_sn);
CREATE INDEX IF NOT EXISTS idx_device_alarms_created ON device_alarms(created_at DESC);

CREATE TABLE IF NOT EXISTS device_cmd_logs (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    cmd VARCHAR(50) NOT NULL,
    result VARCHAR(20),
    message TEXT,
    sent_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn ON device_cmd_logs(device_sn);

CREATE TABLE IF NOT EXISTS device_day_data (
    device_sn VARCHAR(50) NOT NULL,
    data_date DATE NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (device_sn, data_date)
);

CREATE INDEX IF NOT EXISTS idx_device_day_data_date ON device_day_data(data_date);

CREATE TABLE IF NOT EXISTS station_day_data (
    station_id BIGINT NOT NULL,
    data_date DATE NOT NULL,
    energy_produce DECIMAL(12,4) DEFAULT 0,
    income DECIMAL(12,4) DEFAULT 0,
    device_count INTEGER DEFAULT 0,
    online_count INTEGER DEFAULT 0,
    fault_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (station_id, data_date)
);

CREATE INDEX IF NOT EXISTS idx_station_day_data_date ON station_day_data(data_date);
