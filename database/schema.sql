-- 光伏逆变器APP数据库设计
-- 数据库: PostgreSQL 15+
-- 字符集: UTF-8

-- ============================================
-- 1. 用户相关表
-- ============================================

-- 用户表
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nickname VARCHAR(50),
    avatar VARCHAR(500),
    role SMALLINT NOT NULL DEFAULT 5, -- 1:原厂 2:总代理 3:经销商 4:安装商 5:用户
    region_id BIGINT, -- 所属区域(代理商/经销商)
    status SMALLINT NOT NULL DEFAULT 1, -- 1:正常 0:禁用
    last_login_at TIMESTAMP,
    last_login_ip VARCHAR(45),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_region ON users(region_id);

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
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(token_hash);

-- 验证码表
CREATE TABLE verification_codes (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    code VARCHAR(6) NOT NULL,
    type VARCHAR(20) NOT NULL, -- register/reset_password/login
    expires_at TIMESTAMP NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    status SMALLINT NOT NULL DEFAULT 1, -- 1:正常 0:禁用
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX idx_stations_user ON stations(user_id);
CREATE INDEX idx_stations_location ON stations(province, city, district);

-- ============================================
-- 3. 设备相关表
-- ============================================

-- 设备表
CREATE TABLE devices (
    id BIGSERIAL PRIMARY KEY,
    sn VARCHAR(50) NOT NULL UNIQUE,
    model VARCHAR(100),
    rated_power DECIMAL(10,2), -- 额定功率(kW)
    firmware_version VARCHAR(50),
    hardware_version VARCHAR(50),
    mac_address VARCHAR(17),
    station_id BIGINT,
    user_id BIGINT NOT NULL,
    status SMALLINT NOT NULL DEFAULT 0, -- 0:离线 1:在线 2:故障
    last_online_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX idx_devices_sn ON devices(sn);
CREATE INDEX idx_devices_station ON devices(station_id);
CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_status ON devices(status);

-- 设备实时数据表
CREATE TABLE device_realtime_data (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL UNIQUE,
    -- 光伏参数
    pv1_voltage DECIMAL(10,2),
    pv1_current DECIMAL(10,2),
    pv1_power DECIMAL(10,2),
    pv1_temp DECIMAL(10,2),
    pv2_voltage DECIMAL(10,2),
    pv2_current DECIMAL(10,2),
    pv2_power DECIMAL(10,2),
    pv2_temp DECIMAL(10,2),
    -- 电池参数
    battery_voltage DECIMAL(10,2),
    battery_current DECIMAL(10,2),
    battery_soc INTEGER,
    battery_temp DECIMAL(10,2),
    battery_status VARCHAR(50),
    -- 电网参数
    grid_voltage DECIMAL(10,2),
    grid_frequency DECIMAL(10,2),
    grid_power DECIMAL(10,2),
    grid_power_direction VARCHAR(20), -- buy/sell
    -- 输出参数
    output_voltage DECIMAL(10,2),
    output_current DECIMAL(10,2),
    output_frequency DECIMAL(10,2),
    output_power DECIMAL(10,2),
    power_factor DECIMAL(5,3),
    -- 温度故障
    board_temp DECIMAL(10,2),
    tube_temp DECIMAL(10,2),
    fault_code VARCHAR(20),
    fault_message VARCHAR(200),
    -- 运行状态
    run_mode VARCHAR(20), -- grid_tied/off_grid/standby/fault
    total_power DECIMAL(10,2), -- 当前总功率
    wifi_signal INTEGER,
    -- 时间戳
    data_time TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_realtime_data_sn ON device_realtime_data(device_sn);

-- 设备历史数据表(分钟级)
CREATE TABLE device_minute_data (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    data_time TIMESTAMP NOT NULL,
    -- 汇总数据
    avg_power DECIMAL(10,2),
    max_power DECIMAL(10,2),
    min_power DECIMAL(10,2),
    energy_produce DECIMAL(10,4), -- 发电量(kWh)
    energy_consume DECIMAL(10,4), -- 用电量(kWh)
    energy_sell DECIMAL(10,4), -- 上网电量(kWh)
    energy_buy DECIMAL(10,4), -- 购电量(kWh)
    avg_soc INTEGER,
    run_minutes INTEGER, -- 运行分钟数
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_minute_data_sn_time ON device_minute_data(device_sn, data_time);

-- 设备历史数据表(小时级)
CREATE TABLE device_hour_data (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    data_time TIMESTAMP NOT NULL,
    energy_produce DECIMAL(10,4),
    energy_consume DECIMAL(10,4),
    energy_sell DECIMAL(10,4),
    energy_buy DECIMAL(10,4),
    avg_power DECIMAL(10,2),
    max_power DECIMAL(10,2),
    avg_soc INTEGER,
    run_minutes INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_hour_data_sn_time ON device_hour_data(device_sn, data_time);

-- 设备历史数据表(日级)
CREATE TABLE device_day_data (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    data_date DATE NOT NULL,
    energy_produce DECIMAL(10,4),
    energy_consume DECIMAL(10,4),
    energy_sell DECIMAL(10,4),
    energy_buy DECIMAL(10,4),
    max_power DECIMAL(10,2),
    avg_soc INTEGER,
    run_minutes INTEGER,
    income DECIMAL(10,2), -- 收益(元)
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(device_sn, data_date)
);

CREATE INDEX idx_day_data_sn_date ON device_day_data(device_sn, data_date);

-- 设备参数设置表
CREATE TABLE device_params (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL UNIQUE,
    -- 基础运行设置
    power_switch BOOLEAN DEFAULT TRUE,
    run_mode VARCHAR(20) DEFAULT 'grid_tied', -- grid_tied/off_grid
    power_strategy VARCHAR(20) DEFAULT 'self_use', -- self_use/sell_first
    output_power_limit DECIMAL(10,2),
    device_time TIMESTAMP,
    -- 电池充放电设置
    charge_voltage_limit DECIMAL(10,2),
    discharge_voltage_limit DECIMAL(10,2),
    max_charge_current DECIMAL(10,2),
    max_discharge_current DECIMAL(10,2),
    peak_valley_schedule JSONB,
    -- 电网保护设置
    over_voltage_threshold DECIMAL(10,2),
    under_voltage_threshold DECIMAL(10,2),
    over_freq_threshold DECIMAL(10,2),
    under_freq_threshold DECIMAL(10,2),
    island_protection BOOLEAN DEFAULT TRUE,
    grid_delay INTEGER DEFAULT 60,
    -- 硬件保护设置
    over_current_threshold DECIMAL(10,2),
    over_temp_threshold DECIMAL(10,2),
    dc_threshold DECIMAL(10,2),
    -- 工厂高级参数
    voltage_calibration DECIMAL(10,4),
    current_calibration DECIMAL(10,4),
    power_calibration DECIMAL(10,4),
    inner_loop_params JSONB,
    -- 时间戳
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_params_sn ON device_params(device_sn);

-- ============================================
-- 4. 告警相关表
-- ============================================

-- 告警表
CREATE TABLE alarms (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    station_id BIGINT,
    user_id BIGINT NOT NULL,
    alarm_level SMALLINT NOT NULL, -- 1:提示 2:警告 3:严重
    fault_code VARCHAR(20) NOT NULL,
    fault_message VARCHAR(200) NOT NULL,
    fault_detail TEXT,
    status SMALLINT NOT NULL DEFAULT 0, -- 0:未处理 1:已处理 2:已忽略
    occurred_at TIMESTAMP NOT NULL,
    recovered_at TIMESTAMP,
    handled_at TIMESTAMP,
    handled_by BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    sent_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_alarm_notify_alarm ON alarm_notifications(alarm_id);
CREATE INDEX idx_alarm_notify_user ON alarm_notifications(user_id);

-- ============================================
-- 5. 设备分享相关表
-- ============================================

-- 设备分享表
CREATE TABLE device_shares (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    owner_id BIGINT NOT NULL,
    share_to_user_id BIGINT NOT NULL,
    permission VARCHAR(20) NOT NULL DEFAULT 'view', -- view/control
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(device_sn, share_to_user_id)
);

CREATE INDEX idx_shares_device ON device_shares(device_sn);
CREATE INDEX idx_shares_owner ON device_shares(owner_id);
CREATE INDEX idx_shares_to_user ON device_shares(share_to_user_id);

-- ============================================
-- 6. 电站汇总数据表
-- ============================================

-- 电站日汇总表
CREATE TABLE station_day_data (
    id BIGSERIAL PRIMARY KEY,
    station_id BIGINT NOT NULL,
    data_date DATE NOT NULL,
    energy_produce DECIMAL(10,4),
    energy_consume DECIMAL(10,4),
    energy_sell DECIMAL(10,4),
    energy_buy DECIMAL(10,4),
    max_power DECIMAL(10,2),
    device_count INTEGER,
    online_count INTEGER,
    fault_count INTEGER,
    income DECIMAL(10,2),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(station_id, data_date)
);

CREATE INDEX idx_station_day_station_date ON station_day_data(station_id, data_date);

-- ============================================
-- 7. 消息推送相关表
-- ============================================

-- 用户消息设置表
CREATE TABLE user_notify_settings (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE,
    push_enabled BOOLEAN DEFAULT TRUE,
    alarm_push BOOLEAN DEFAULT TRUE,
    offline_push BOOLEAN DEFAULT TRUE,
    system_push BOOLEAN DEFAULT TRUE,
    quiet_hours_start TIME, -- 免打扰开始时间
    quiet_hours_end TIME, -- 免打扰结束时间
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 消息表
CREATE TABLE messages (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    type VARCHAR(20) NOT NULL, -- alarm/system/promotion
    is_read BOOLEAN DEFAULT FALSE,
    extra_data JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_messages_user ON messages(user_id);
CREATE INDEX idx_messages_read ON messages(user_id, is_read);

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
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
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
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
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
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 初始化系统配置
INSERT INTO system_configs (config_key, config_value, description) VALUES
('mqtt_broker_url', 'tcp://localhost:1883', 'MQTT Broker地址'),
('mqtt_ws_url', 'ws://localhost:8083/mqtt', 'MQTT WebSocket地址'),
('token_expire_hours', '168', 'Token过期时间(小时)'),
('verify_code_expire_minutes', '5', '验证码过期时间(分钟)'),
('data_retention_days', '365', '数据保留天数'),
('max_devices_per_user', '100', '每用户最大设备数'),
('max_stations_per_user', '20', '每用户最大电站数');

-- ============================================
-- 10. 视图
-- ============================================

-- 电站实时数据视图
CREATE VIEW v_station_realtime AS
SELECT 
    s.id AS station_id,
    s.user_id,
    s.name AS station_name,
    s.capacity,
    COUNT(d.id) AS device_count,
    SUM(CASE WHEN d.status = 1 THEN 1 ELSE 0 END) AS online_count,
    SUM(CASE WHEN d.status = 2 THEN 1 ELSE 0 END) AS fault_count,
    COALESCE(SUM(r.total_power), 0) AS total_power,
    COALESCE(AVG(r.battery_soc), 0) AS avg_soc
FROM stations s
LEFT JOIN devices d ON d.station_id = s.id AND d.deleted_at IS NULL
LEFT JOIN device_realtime_data r ON r.device_sn = d.sn
WHERE s.deleted_at IS NULL
GROUP BY s.id, s.user_id, s.name, s.capacity;

-- 用户设备权限视图
CREATE VIEW v_user_devices AS
SELECT 
    u.id AS user_id,
    d.sn AS device_sn,
    d.station_id,
    CASE 
        WHEN d.user_id = u.id THEN 'owner'
        WHEN ds.permission IS NOT NULL THEN ds.permission
        ELSE NULL
    END AS permission
FROM users u
LEFT JOIN devices d ON d.user_id = u.id AND d.deleted_at IS NULL
LEFT JOIN device_shares ds ON ds.device_sn = d.sn AND ds.share_to_user_id = u.id;

-- ============================================
-- 11. 函数
-- ============================================

-- 更新时间戳函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为需要的表创建触发器
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_stations_updated_at BEFORE UPDATE ON stations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_device_params_updated_at BEFORE UPDATE ON device_params FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_notify_settings_updated_at BEFORE UPDATE ON user_notify_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_system_configs_updated_at BEFORE UPDATE ON system_configs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 12. 清理过期数据函数
-- ============================================

CREATE OR REPLACE FUNCTION clean_expired_data()
RETURNS void AS $$
BEGIN
    -- 清理过期验证码
    DELETE FROM verification_codes WHERE expires_at < CURRENT_TIMESTAMP;
    
    -- 清理过期会话
    DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;
    
    -- 清理30天前的分钟级数据
    DELETE FROM device_minute_data WHERE data_time < CURRENT_TIMESTAMP - INTERVAL '30 days';
    
    -- 清理1年前的小时级数据
    DELETE FROM device_hour_data WHERE data_time < CURRENT_TIMESTAMP - INTERVAL '1 year';
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 阶段2: 时序遥测数据表（替代旧 device_realtime_data）
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
    time               TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMP NOT NULL DEFAULT NOW()
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
    dt.time as data_time,
    dt.created_at as updated_at
FROM device_telemetry dt
ORDER BY dt.device_sn, dt.time DESC;

-- ============================================
-- 阶段3: 设备型号注册表
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
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE device_models IS '设备型号注册表 - 新型号只需在此配置，无需改代码';
COMMENT ON COLUMN device_models.data_fields IS 'JSON格式: {"total_active_power":{"type":"float","unit":"W","label":"总有功功率"}}';
COMMENT ON COLUMN device_models.field_mapping IS 'JSON格式: {"data/status":{"work_state":"work_state_1","temp":"internal_temperature"}}';

-- 预置一些常见型号
INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, data_fields, field_mapping, mqtt_topics) VALUES
('INV-5000-TL', 'INVT 5000TL 逆变器', 'INVT', 'inverter', 5.0,
 '{"serial_number":{"type":"string","label":"序列号"},"total_active_power":{"type":"float","unit":"W","label":"总有功功率"},"work_state_1":{"type":"string","label":"工作状态"},"work_state_1_code":{"type":"int","label":"状态码"},"internal_temperature":{"type":"float","unit":"℃","label":"内部温度"},"bus_voltage":{"type":"float","unit":"V","label":"母线电压"},"efficiency":{"type":"float","unit":"%","label":"转换效率"},"fault_code":{"type":"int","label":"故障码"},"daily_power_yields":{"type":"float","unit":"kWh","label":"日发电量"},"total_power_yields":{"type":"float","unit":"kWh","label":"总发电量"},"grid_frequency":{"type":"float","unit":"Hz","label":"电网频率"},"power_factor":{"type":"float","label":"功率因数"},"nominal_active_power":{"type":"float","unit":"W","label":"额定功率"},"output_type":{"type":"int","label":"输出类型"}}'::jsonb,
 '{"data/status":{"work_state":"work_state_1","temp":"internal_temperature","bus_voltage":"bus_voltage","efficiency":"efficiency","fault_code":"fault_code"},"data/ac":{"active_power":"total_active_power","frequency":"grid_frequency","pf":"power_factor"},"data/energy":{"daily":"daily_power_yields","total":"total_power_yields"}}'::jsonb,
 '["cs_inv/+/data/status", "cs_inv/+/data/ac", "cs_inv/+/data/energy"]'::jsonb)
ON CONFLICT (model_code) DO NOTHING;
