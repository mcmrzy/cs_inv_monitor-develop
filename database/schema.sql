-- 辰烁科技光伏逆变器APP数据库设计
-- 数据库: PostgreSQL 15+
-- 字符集: UTF-8
-- 说明: 本文件为数据库基准 schema，包含所有表定义。
--       触发器函数、连续聚合物化视图及种子数据请参照 database/migrations/ 中的迁移文件。

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

-- [已废弃] user_sessions — 改用 JWT，表已移除

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

-- 用户-设备关联表 (migration 031)
-- 记录用户与设备的绑定关系，支持多用户共享同一设备
CREATE TABLE IF NOT EXISTS user_device_rel (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_sn VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_sn)
);
CREATE INDEX IF NOT EXISTS idx_user_device_rel_user ON user_device_rel(user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_rel_sn ON user_device_rel(device_sn);

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
    timezone VARCHAR(50) NOT NULL DEFAULT 'Asia/Shanghai', -- 电站所在时区
    status SMALLINT NOT NULL DEFAULT 1, -- 1:正常 0:禁用
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_stations_user ON stations(user_id);
CREATE INDEX idx_stations_location ON stations(province, city, district);
CREATE INDEX idx_stations_timezone ON stations(timezone);

-- ============================================
-- 3. 设备型号注册表与协议定义
-- ============================================

-- 设备型号注册表
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

-- 预置型号
INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, data_fields, field_mapping, mqtt_topics) VALUES
('INV-5000-TL', 'INVT 5000TL 逆变器', 'INVT', 'inverter', 5.0,
 '{"serial_number":{"type":"string","label":"序列号"},"total_active_power":{"type":"float","unit":"W","label":"总有功功率"},"work_state_1":{"type":"string","label":"工作状态"},"work_state_1_code":{"type":"int","label":"状态码"},"internal_temperature":{"type":"float","unit":"℃","label":"内部温度"},"bus_voltage":{"type":"float","unit":"V","label":"母线电压"},"efficiency":{"type":"float","unit":"%","label":"转换效率"},"fault_code":{"type":"int","label":"故障码"},"daily_power_yields":{"type":"float","unit":"kWh","label":"日发电量"},"total_power_yields":{"type":"float","unit":"kWh","label":"总发电量"},"grid_frequency":{"type":"float","unit":"Hz","label":"电网频率"},"power_factor":{"type":"float","label":"功率因数"},"nominal_active_power":{"type":"float","unit":"W","label":"额定功率"},"output_type":{"type":"int","label":"输出类型"}}'::jsonb,
 '{"data/status":{"work_state":"work_state_1","temp":"internal_temperature","bus_voltage":"bus_voltage","efficiency":"efficiency","fault_code":"fault_code"},"data/ac":{"active_power":"total_active_power","frequency":"grid_frequency","pf":"power_factor"},"data/energy":{"daily":"daily_power_yields","total":"total_power_yields"}}'::jsonb,
 '["cs_inv/+/data/status", "cs_inv/+/data/ac", "cs_inv/+/data/energy"]'::jsonb)
ON CONFLICT (model_code) DO NOTHING;

-- 遥测字段目录 (migration 023)
-- 全局字段字典，所有型号共享同一套字段定义
CREATE TABLE IF NOT EXISTS telemetry_field_catalog (
    field_key          VARCHAR(64) PRIMARY KEY,
    field_type         VARCHAR(20) NOT NULL CHECK (field_type IN ('float', 'integer', 'boolean', 'string', 'bitmask')),
    base_unit          VARCHAR(20),
    category           VARCHAR(32) NOT NULL,
    description        TEXT,
    is_timeseries      BOOLEAN NOT NULL DEFAULT TRUE,
    is_aggregatable    BOOLEAN NOT NULL DEFAULT TRUE,
    allowed_aggregates JSONB NOT NULL DEFAULT '[]'::jsonb,
    status             VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deprecated')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 设备协议版本表 (migration 023)
-- 替代已废弃的 device_model_protocol 表
CREATE TABLE IF NOT EXISTS device_protocol_versions (
    id            BIGSERIAL PRIMARY KEY,
    protocol_code VARCHAR(64) NOT NULL,
    version       SMALLINT NOT NULL CHECK (version > 0),
    schema_hash   VARCHAR(64) NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'released', 'retired')),
    released_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (protocol_code, version)
);

-- 设备协议字段表 (migration 023)
-- 定义每个协议版本包含的字段及其线缆编码
CREATE TABLE IF NOT EXISTS device_protocol_fields (
    id                  BIGSERIAL PRIMARY KEY,
    protocol_version_id BIGINT NOT NULL REFERENCES device_protocol_versions(id) ON DELETE RESTRICT,
    group_code          VARCHAR(16) NOT NULL,
    field_index         SMALLINT NOT NULL CHECK (field_index >= 0),
    field_key           VARCHAR(64) NOT NULL REFERENCES telemetry_field_catalog(field_key) ON DELETE RESTRICT,
    wire_type           VARCHAR(20) NOT NULL,
    scale               NUMERIC NOT NULL DEFAULT 1,
    minimum             NUMERIC,
    maximum             NUMERIC,
    nullable            BOOLEAN NOT NULL DEFAULT TRUE,
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deprecated')),
    UNIQUE (protocol_version_id, group_code, field_index),
    UNIQUE (protocol_version_id, group_code, field_key)
);

-- 设备型号字段表（复数，模块化字段定义）(migration 023)
-- 替代已废弃的 device_model_field（单数）表
CREATE TABLE IF NOT EXISTS device_model_fields (
    id               BIGSERIAL PRIMARY KEY,
    model_id         BIGINT NOT NULL REFERENCES device_models(id) ON DELETE RESTRICT,
    field_key        VARCHAR(64) NOT NULL REFERENCES telemetry_field_catalog(field_key) ON DELETE RESTRICT,
    display_name_key VARCHAR(128),
    group_code       VARCHAR(32) NOT NULL,
    display_unit     VARCHAR(20),
    decimal_places   SMALLINT NOT NULL DEFAULT 1 CHECK (decimal_places BETWEEN 0 AND 6),
    sort_order       INTEGER NOT NULL DEFAULT 0,
    is_supported     BOOLEAN NOT NULL DEFAULT TRUE,
    is_visible       BOOLEAN NOT NULL DEFAULT TRUE,
    show_realtime    BOOLEAN NOT NULL DEFAULT TRUE,
    show_history     BOOLEAN NOT NULL DEFAULT TRUE,
    allow_compare    BOOLEAN NOT NULL DEFAULT FALSE,
    allow_alarm_rule BOOLEAN NOT NULL DEFAULT FALSE,
    default_chart    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (model_id, field_key)
);
CREATE INDEX IF NOT EXISTS idx_device_model_fields_model_sort ON device_model_fields(model_id, group_code, sort_order);

-- 设备型号命令定义表 (migration 023)
CREATE TABLE IF NOT EXISTS device_model_commands (
    id               BIGSERIAL PRIMARY KEY,
    model_id         BIGINT NOT NULL REFERENCES device_models(id) ON DELETE RESTRICT,
    command_code     VARCHAR(64) NOT NULL,
    display_name_key VARCHAR(128) NOT NULL,
    parameter_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
    response_schema  JSONB NOT NULL DEFAULT '{}'::jsonb,
    timeout_seconds  INTEGER NOT NULL DEFAULT 30 CHECK (timeout_seconds BETWEEN 1 AND 3600),
    risk_level       SMALLINT NOT NULL DEFAULT 1 CHECK (risk_level BETWEEN 1 AND 3),
    requires_online  BOOLEAN NOT NULL DEFAULT TRUE,
    is_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (model_id, command_code)
);

-- 型号注册迁移报告表 (migration 024)
-- 记录从旧 device_model_field 迁移到 device_model_fields 的状态
CREATE TABLE IF NOT EXISTS model_registry_migration_report (
    model_id BIGINT PRIMARY KEY REFERENCES device_models(id) ON DELETE CASCADE,
    legacy_field_count INTEGER NOT NULL DEFAULT 0,
    legacy_json_field_count INTEGER NOT NULL DEFAULT 0,
    migrated_field_count INTEGER NOT NULL DEFAULT 0,
    legacy_mapping_count INTEGER NOT NULL DEFAULT 0,
    migration_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    migrated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 4. 设备相关表
-- ============================================

-- 设备表
CREATE TABLE devices (
    id BIGSERIAL PRIMARY KEY,
    sn VARCHAR(50) NOT NULL UNIQUE,
    model VARCHAR(100),
    model_id BIGINT REFERENCES device_models(id),       -- 关联设备型号注册表 (migration 031)
    manufacturer VARCHAR(100) DEFAULT '',               -- 制造商
    firmware_arm VARCHAR(50) DEFAULT '',                -- ARM固件版本
    firmware_esp VARCHAR(50) DEFAULT '',                -- ESP固件版本
    firmware_dsp VARCHAR(50) DEFAULT '',                -- DSP固件版本
    firmware_bms VARCHAR(50) DEFAULT '',                -- BMS固件版本
    main_version VARCHAR(50) DEFAULT '',                -- 主版本号
    device_type VARCHAR(50) DEFAULT '',                 -- 设备类型
    rated_power DECIMAL(10,2),                          -- 额定功率(kW)
    rated_voltage DECIMAL(10,2) DEFAULT 0,              -- 额定电压(V)
    rated_freq DECIMAL(5,2) DEFAULT 0,                  -- 额定频率(Hz)
    battery_voltage DECIMAL(10,2) DEFAULT 0,            -- 电池电压(V)
    battery_type VARCHAR(50) DEFAULT '',                -- 电池类型
    cell_count INTEGER DEFAULT 0,                       -- 电池节数
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
CREATE INDEX IF NOT EXISTS idx_devices_model_id ON devices(model_id) WHERE model_id IS NOT NULL;

-- [已废弃] device_realtime_data / device_minute_data / device_hour_data / device_params
--   已由 device_telemetry_3min 超表 + TimescaleDB 连续聚合替代

-- ============================================
-- 5. 时序遥测数据表
-- ============================================

-- 设备遥测数据表（旧版 JSONB 超表，过渡期保留可读）
CREATE TABLE IF NOT EXISTS device_telemetry (
    id          BIGSERIAL,
    device_sn   VARCHAR(50) NOT NULL,
    model_code  VARCHAR(50),           -- 关联设备型号
    topic       VARCHAR(200),           -- 来源 Topic
    data        JSONB NOT NULL,         -- 原始 JSON 数据（完整保留）
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

-- 设备遥测数据表 V2（三分钟采样，HTML V1 规范）(migration 023 + 026)
-- 替代旧版 device_telemetry JSONB 超表
CREATE TABLE IF NOT EXISTS device_telemetry_3min (
    device_sn VARCHAR(50) NOT NULL,
    protocol_version SMALLINT NOT NULL,
    sequence_no BIGINT NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    quality_flags INTEGER NOT NULL DEFAULT 0,
    topic VARCHAR(64) NOT NULL DEFAULT 'heartbeat',
    data_hash VARCHAR(64) NOT NULL,
    raw_envelope JSONB NOT NULL DEFAULT '{}'::jsonb,
    ac_voltage REAL, ac_current REAL, ac_active_power REAL, ac_apparent_power REAL,
    ac_frequency REAL, ac_power_factor REAL, load_percent REAL, ac_voltage_thd REAL,
    battery_soc REAL, battery_soh REAL, battery_voltage REAL, battery_current REAL, battery_power REAL,
    battery_capacity_remain REAL, battery_capacity_total REAL, battery_cycle_count INTEGER,
    battery_temp_max REAL, battery_temp_min REAL, cell_voltage_max REAL, cell_voltage_min REAL,
    cell_voltage_diff REAL, battery_state SMALLINT, battery_protect_status BIGINT, bms_fault_code BIGINT,
    max_charge_current REAL, max_discharge_current REAL, charge_voltage_ref REAL,
    discharge_cutoff_voltage REAL, battery_temperature REAL,
    pv1_voltage REAL, pv1_current REAL, pv1_power REAL, pv1_voltage_max REAL, pv1_power_max REAL,
    pv2_voltage REAL, pv2_current REAL, pv2_power REAL, pv2_voltage_max REAL, pv2_power_max REAL,
    pv_total_power REAL, mppt_state SMALLINT,
    work_state SMALLINT, fault_code BIGINT, alarm_code BIGINT, inverter_temperature REAL,
    mos_temperature REAL, ambient_temperature REAL, dc_bus_voltage REAL, runtime_hours BIGINT,
    fan_speed_percent SMALLINT, efficiency REAL,
    daily_pv_energy DOUBLE PRECISION, total_pv_energy DOUBLE PRECISION,
    daily_charge_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    daily_discharge_energy DOUBLE PRECISION, total_discharge_energy DOUBLE PRECISION,
    daily_load_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    charge_request_current_x10 BIGINT, charge_request_voltage_x10 BIGINT, system_mode BIGINT,
    total_charge_capacity DOUBLE PRECISION, total_discharge_capacity DOUBLE PRECISION,
    total_charge_time BIGINT, total_discharge_time BIGINT
);
CREATE INDEX IF NOT EXISTS idx_device_telemetry_3min_sn_time ON device_telemetry_3min(device_sn, event_time DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_telemetry_3min_message
    ON device_telemetry_3min(device_sn, event_time, data_hash);

-- 设备最新状态表（每设备一行，由触发器维护）(migration 023 + 026)
CREATE TABLE IF NOT EXISTS device_latest_state (
    device_sn VARCHAR(50) PRIMARY KEY,
    protocol_version SMALLINT NOT NULL,
    sequence_no BIGINT NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    topic VARCHAR(64) NOT NULL DEFAULT 'heartbeat',
    data_hash VARCHAR(64) NOT NULL DEFAULT '',
    raw_envelope JSONB NOT NULL DEFAULT '{}'::jsonb,
    ac_voltage REAL, ac_current REAL, ac_active_power REAL, ac_apparent_power REAL,
    ac_frequency REAL, ac_power_factor REAL, load_percent REAL, ac_voltage_thd REAL,
    battery_soc REAL, battery_soh REAL, battery_voltage REAL, battery_current REAL, battery_power REAL,
    battery_capacity_remain REAL, battery_capacity_total REAL, battery_cycle_count INTEGER,
    battery_temp_max REAL, battery_temp_min REAL, cell_voltage_max REAL, cell_voltage_min REAL,
    cell_voltage_diff REAL, battery_state SMALLINT, battery_protect_status BIGINT, bms_fault_code BIGINT,
    max_charge_current REAL, max_discharge_current REAL, charge_voltage_ref REAL,
    discharge_cutoff_voltage REAL, battery_temperature REAL,
    pv1_voltage REAL, pv1_current REAL, pv1_power REAL, pv1_voltage_max REAL, pv1_power_max REAL,
    pv2_voltage REAL, pv2_current REAL, pv2_power REAL, pv2_voltage_max REAL, pv2_power_max REAL,
    pv_total_power REAL, mppt_state SMALLINT,
    work_state SMALLINT, fault_code BIGINT, alarm_code BIGINT, inverter_temperature REAL,
    mos_temperature REAL, ambient_temperature REAL, dc_bus_voltage REAL, runtime_hours BIGINT,
    fan_speed_percent SMALLINT, efficiency REAL,
    daily_pv_energy DOUBLE PRECISION, total_pv_energy DOUBLE PRECISION,
    daily_charge_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    daily_discharge_energy DOUBLE PRECISION, total_discharge_energy DOUBLE PRECISION,
    daily_load_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    charge_request_current_x10 BIGINT, charge_request_voltage_x10 BIGINT, system_mode BIGINT,
    total_charge_capacity DOUBLE PRECISION, total_discharge_capacity DOUBLE PRECISION,
    total_charge_time BIGINT, total_discharge_time BIGINT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_latest_state_event_time ON device_latest_state(event_time DESC);

-- 设备电芯采样表 (migration 023 + 026)
CREATE TABLE IF NOT EXISTS device_cell_samples (
    device_sn VARCHAR(50) NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    sequence_no BIGINT NOT NULL,
    data_hash VARCHAR(64) NOT NULL,
    voltages JSONB NOT NULL,
    temperatures JSONB NOT NULL,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    is_abnormal BOOLEAN NOT NULL DEFAULT FALSE,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_cell_samples_message
    ON device_cell_samples(device_sn, event_time, data_hash);

-- 设备最新电芯数据表（每设备一行，由触发器维护）(migration 023)
CREATE TABLE IF NOT EXISTS device_latest_cells (
    device_sn VARCHAR(50) PRIMARY KEY,
    event_time TIMESTAMPTZ NOT NULL,
    sequence_no BIGINT NOT NULL,
    voltages JSONB NOT NULL,
    temperatures JSONB NOT NULL,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 设备日能量统计表 (migration 023)
CREATE TABLE IF NOT EXISTS device_energy_day (
    device_sn VARCHAR(50) NOT NULL,
    stat_date DATE NOT NULL,
    timezone VARCHAR(64) NOT NULL,
    pv_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    charge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    discharge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    load_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_pv_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    total_discharge_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    max_pv_power REAL, max_ac_power REAL, max_charge_power REAL, max_discharge_power REAL,
    avg_battery_soc REAL, min_battery_soc REAL, max_battery_soc REAL,
    max_inverter_temperature REAL, max_mos_temperature REAL, max_battery_temperature REAL,
    sample_count INTEGER NOT NULL DEFAULT 0,
    online_minutes SMALLINT NOT NULL DEFAULT 0, run_minutes SMALLINT NOT NULL DEFAULT 0,
    alarm_count INTEGER NOT NULL DEFAULT 0, fault_count INTEGER NOT NULL DEFAULT 0,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_sn, stat_date)
);

-- 设备月能量统计表 (migration 023)
CREATE TABLE IF NOT EXISTS device_energy_month (
    device_sn VARCHAR(50) NOT NULL,
    stat_month DATE NOT NULL,
    timezone VARCHAR(64) NOT NULL,
    pv_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    charge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    discharge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    load_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_pv_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    total_discharge_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    online_minutes INTEGER NOT NULL DEFAULT 0, run_minutes INTEGER NOT NULL DEFAULT 0,
    alarm_count INTEGER NOT NULL DEFAULT 0, fault_count INTEGER NOT NULL DEFAULT 0,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_sn, stat_month)
);

-- 设备控制状态表（desired/reported 影子模型）(migration 023)
CREATE TABLE IF NOT EXISTS device_control_state (
    device_sn         VARCHAR(50) PRIMARY KEY,
    protocol_version  SMALLINT NOT NULL DEFAULT 1,
    desired           JSONB NOT NULL DEFAULT '{}'::jsonb,
    reported          JSONB NOT NULL DEFAULT '{}'::jsonb,
    desired_version   BIGINT NOT NULL DEFAULT 0,
    reported_revision BIGINT NOT NULL DEFAULT 0,
    sync_status       VARCHAR(20) NOT NULL DEFAULT 'unknown',
    desired_at        TIMESTAMPTZ,
    reported_at       TIMESTAMPTZ,
    last_task_id      UUID,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 设备控制事件日志表 (migration 023)
CREATE TABLE IF NOT EXISTS device_control_events (
    id          BIGSERIAL PRIMARY KEY,
    device_sn   VARCHAR(50) NOT NULL,
    task_id     UUID,
    event_type  VARCHAR(32) NOT NULL,
    old_value   JSONB NOT NULL DEFAULT '{}'::jsonb,
    new_value   JSONB NOT NULL DEFAULT '{}'::jsonb,
    operator_id BIGINT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_control_events_sn_created ON device_control_events(device_sn, created_at DESC);

-- 设备命令表 (migration 023)
CREATE TABLE IF NOT EXISTS device_commands (
    id              BIGSERIAL PRIMARY KEY,
    task_id         UUID NOT NULL UNIQUE,
    device_sn       VARCHAR(50) NOT NULL,
    command_code    VARCHAR(64) NOT NULL,
    requested_args  JSONB NOT NULL DEFAULT '[]'::jsonb,
    response_data   JSONB NOT NULL DEFAULT '[]'::jsonb,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    result_code     VARCHAR(64),
    result_message  TEXT,
    requested_by    BIGINT,
    source          VARCHAR(20) NOT NULL DEFAULT 'web',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    queued_at       TIMESTAMPTZ,
    sent_at         TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    timeout_at      TIMESTAMPTZ NOT NULL,
    retry_count     SMALLINT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_device_commands_sn_created ON device_commands(device_sn, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_commands_pending ON device_commands(status, timeout_at)
    WHERE status IN ('pending', 'queued', 'sent', 'acknowledged', 'executing');

-- 设备数据摄入错误表 (migration 026)
-- 结构无效的 MQTT 载荷被排除在正常遥测之外，存于此表用于排查
CREATE TABLE IF NOT EXISTS device_ingest_errors (
    id           BIGSERIAL PRIMARY KEY,
    device_sn    VARCHAR(50),
    topic        VARCHAR(128) NOT NULL,
    raw_payload  BYTEA NOT NULL,
    error_code   VARCHAR(64) NOT NULL,
    error_detail TEXT,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_ingest_errors_sn_received ON device_ingest_errors(device_sn, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_ingest_errors_received ON device_ingest_errors(received_at DESC);

-- 三相数据超表（每3分钟采样）(migration 038)
-- 存储并机三相模式下各相电压、电流、功率及不平衡度
CREATE TABLE IF NOT EXISTS device_three_phase_3min (
    device_sn           VARCHAR(50) NOT NULL,
    event_time          TIMESTAMPTZ NOT NULL,
    received_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_hash           VARCHAR(64) NOT NULL DEFAULT '',
    raw_envelope        JSONB NOT NULL DEFAULT '{}'::jsonb,
    voltage_l1          DOUBLE PRECISION,
    voltage_l2          DOUBLE PRECISION,
    voltage_l3          DOUBLE PRECISION,
    current_l1          DOUBLE PRECISION,
    current_l2          DOUBLE PRECISION,
    current_l3          DOUBLE PRECISION,
    active_power_l1     DOUBLE PRECISION,
    active_power_l2     DOUBLE PRECISION,
    active_power_l3     DOUBLE PRECISION,
    total_active_power  DOUBLE PRECISION,
    line_voltage_l1l2   DOUBLE PRECISION,
    line_voltage_l2l3   DOUBLE PRECISION,
    line_voltage_l3l1   DOUBLE PRECISION,
    frequency           DOUBLE PRECISION,
    voltage_unbalance   DOUBLE PRECISION,
    current_unbalance   DOUBLE PRECISION,
    quality_flags       INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_three_phase_unique
    ON device_three_phase_3min(device_sn, event_time, data_hash);
CREATE INDEX IF NOT EXISTS idx_three_phase_device_time
    ON device_three_phase_3min(device_sn, event_time DESC);

-- TimescaleDB 超表配置 (migration 023)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable('device_telemetry_3min', 'event_time', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);
        PERFORM create_hypertable('device_cell_samples', 'event_time', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);

        ALTER TABLE device_telemetry_3min SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'event_time DESC'
        );
        ALTER TABLE device_cell_samples SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'event_time DESC'
        );

        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_compression' AND hypertable_name = 'device_telemetry_3min') THEN
            PERFORM add_compression_policy('device_telemetry_3min', INTERVAL '3 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' AND hypertable_name = 'device_telemetry_3min') THEN
            PERFORM add_retention_policy('device_telemetry_3min', INTERVAL '90 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_compression' AND hypertable_name = 'device_cell_samples') THEN
            PERFORM add_compression_policy('device_cell_samples', INTERVAL '7 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' AND hypertable_name = 'device_cell_samples') THEN
            PERFORM add_retention_policy('device_cell_samples', INTERVAL '90 days');
        END IF;

        -- device_three_phase_3min: 7-day chunks, compress 3d, retain 90d (migration 038)
        PERFORM create_hypertable('device_three_phase_3min', 'event_time',
            chunk_time_interval => INTERVAL '7 days', if_not_exists => TRUE);
        ALTER TABLE device_three_phase_3min SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'event_time DESC'
        );
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_compression' AND hypertable_name = 'device_three_phase_3min') THEN
            PERFORM add_compression_policy('device_three_phase_3min', INTERVAL '3 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' AND hypertable_name = 'device_three_phase_3min') THEN
            PERFORM add_retention_policy('device_three_phase_3min', INTERVAL '90 days');
        END IF;
    END IF;
END $$;

-- ============================================
-- 5.1 并机拓扑表 (migration 038)
-- ============================================

-- 并机拓扑当前状态表（每电站一行）
CREATE TABLE IF NOT EXISTS device_parallel_state (
    station_id          BIGINT PRIMARY KEY,
    master_sn           VARCHAR(50) NOT NULL,
    mode                VARCHAR(20) NOT NULL,      -- standalone/single_phase/three_phase
    count               SMALLINT NOT NULL DEFAULT 0,
    total_rated_power   INTEGER NOT NULL DEFAULT 0,
    total_active_power  DOUBLE PRECISION NOT NULL DEFAULT 0,
    sync_state          VARCHAR(20) NOT NULL DEFAULT 'idle',
    machines            JSONB NOT NULL DEFAULT '[]'::jsonb,
    reported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 并机拓扑变更历史表
CREATE TABLE IF NOT EXISTS device_parallel_events (
    id              BIGSERIAL PRIMARY KEY,
    station_id      BIGINT NOT NULL,
    master_sn       VARCHAR(50) NOT NULL,
    event_type      VARCHAR(32) NOT NULL,          -- topology_changed/master_switched/member_added/member_removed/sync_state_changed/disabled
    mode            VARCHAR(20),
    count           SMALLINT,
    sync_state      VARCHAR(20),
    machines_before JSONB,
    machines_after  JSONB,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_parallel_events_station_time
    ON device_parallel_events(station_id, occurred_at DESC);

-- ============================================
-- 6. 告警相关表
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

-- 告警规则表 (migration 028)
CREATE TABLE IF NOT EXISTS alert_rules (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    type VARCHAR(40) NOT NULL DEFAULT 'telemetry',
    station_id BIGINT,
    device_sn VARCHAR(64),
    conditions JSONB NOT NULL DEFAULT '[]'::jsonb,
    severity VARCHAR(16) NOT NULL DEFAULT 'warning',
    notification_channels JSONB NOT NULL DEFAULT '["app"]'::jsonb,
    cooldown_minutes INTEGER NOT NULL DEFAULT 5 CHECK (cooldown_minutes BETWEEN 1 AND 1440),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alert_rules_owner ON alert_rules(created_by, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_alert_rules_target ON alert_rules(device_sn, station_id) WHERE enabled;

-- 告警事件日志表 (migration 038)
-- TimescaleDB hypertable，按 active_at 分区，7天chunk，30天后压缩，保留1年
-- 复合主键 (id, active_at) 满足超表对分区列的唯一约束要求
CREATE TABLE IF NOT EXISTS device_alarm_events (
    id            BIGSERIAL,
    device_sn     VARCHAR(50) NOT NULL,
    station_id    BIGINT,
    source        SMALLINT NOT NULL,        -- 0 PCS, 1 BMS, 2 MPPT, 3 COMM
    code          INTEGER NOT NULL,         -- 告警码
    level         SMALLINT NOT NULL,       -- 1 warning, 2 fault
    state         SMALLINT NOT NULL,       -- 1 active, 0 recovered
    active_at     TIMESTAMPTZ NOT NULL,    -- 告警发生时间
    recovered_at  TIMESTAMPTZ,             -- 恢复时间
    raw_data      JSONB,                   -- 原始告警信封
    received_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, active_at)
);
CREATE INDEX IF NOT EXISTS idx_alarm_events_device_time
    ON device_alarm_events(device_sn, active_at DESC);
CREATE INDEX IF NOT EXISTS idx_alarm_events_active
    ON device_alarm_events(device_sn, source, code) WHERE state = 1;

-- device_alarm_events 超表配置: 7天chunk, 30天后压缩, 保留1年 (migration 038)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable('device_alarm_events', 'active_at',
            chunk_time_interval => INTERVAL '7 days', if_not_exists => TRUE);
        ALTER TABLE device_alarm_events SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'active_at DESC'
        );
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_compression' AND hypertable_name = 'device_alarm_events') THEN
            PERFORM add_compression_policy('device_alarm_events', INTERVAL '30 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' AND hypertable_name = 'device_alarm_events') THEN
            PERFORM add_retention_policy('device_alarm_events', INTERVAL '1 year');
        END IF;
    END IF;
END $$;

-- 告警快照表 (migration 038)
-- 记录告警发生前后的设备状态快照，用于故障诊断
CREATE TABLE IF NOT EXISTS device_alarm_snapshots (
    id                   BIGSERIAL PRIMARY KEY,
    device_sn            VARCHAR(50) NOT NULL,
    alarm_event_id       BIGINT,                  -- 关联 device_alarm_events.id
    snapshot_type        VARCHAR(16) NOT NULL,    -- 'before' 或 'after'
    ac_voltage           DOUBLE PRECISION,
    ac_current           DOUBLE PRECISION,
    ac_active_power      DOUBLE PRECISION,
    ac_frequency         DOUBLE PRECISION,
    battery_soc          DOUBLE PRECISION,
    battery_voltage      DOUBLE PRECISION,
    battery_current      DOUBLE PRECISION,
    battery_temperature  DOUBLE PRECISION,
    internal_temperature DOUBLE PRECISION,
    dc_bus_voltage       DOUBLE PRECISION,
    work_state           SMALLINT,
    fault_code           INTEGER,
    raw_snapshot         JSONB NOT NULL,          -- 完整heartbeat快照
    captured_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_alarm_snapshots_event
    ON device_alarm_snapshots(alarm_event_id);
CREATE INDEX IF NOT EXISTS idx_alarm_snapshots_device_time
    ON device_alarm_snapshots(device_sn, captured_at DESC);

-- ============================================
-- 7. OTA升级相关表
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

-- [已废弃] ota_records — 已被 device_upgrades 替代，Go 代码不再引用

-- 设备升级记录表 (migration 006 + 008 + 009 + 013 + 032)
-- 替代已废弃的 ota_records 表
CREATE TABLE IF NOT EXISTS device_upgrades (
    id                  BIGSERIAL PRIMARY KEY,
    device_sn           VARCHAR(50) NOT NULL,
    firmware_id         BIGINT NOT NULL REFERENCES firmware_versions(id),
    firmware_version    VARCHAR(50) NOT NULL,
    target_chip         VARCHAR(50) NOT NULL DEFAULT '',
    old_version         VARCHAR(50) NOT NULL DEFAULT '',
    status              VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending/downloading/upgrading/success/failed/cancelled
    progress            INTEGER NOT NULL DEFAULT 0,
    error_message       TEXT NOT NULL DEFAULT '',
    retry_count         INTEGER NOT NULL DEFAULT 0,
    pushed_by           BIGINT,
    upgrade_package_id  BIGINT,                             -- (migration 008)
    task_id             BIGINT,                             -- (migration 009)
    source              VARCHAR(20) NOT NULL DEFAULT 'admin', -- (migration 013)
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_du_device_sn ON device_upgrades(device_sn);
CREATE INDEX IF NOT EXISTS idx_du_firmware_id ON device_upgrades(firmware_id);
CREATE INDEX IF NOT EXISTS idx_du_status ON device_upgrades(status);
CREATE INDEX IF NOT EXISTS idx_du_created_at ON device_upgrades(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_du_device_status ON device_upgrades(device_sn, status);
CREATE INDEX IF NOT EXISTS idx_du_package_id ON device_upgrades(upgrade_package_id);
CREATE INDEX IF NOT EXISTS idx_du_task_id ON device_upgrades(task_id);
CREATE INDEX IF NOT EXISTS idx_du_source ON device_upgrades(source);
CREATE UNIQUE INDEX IF NOT EXISTS uq_du_device_firmware_package
    ON device_upgrades (device_sn, firmware_id, COALESCE(upgrade_package_id, 0));

-- 升级包表 (migration 008 + 013 + 032)
CREATE TABLE IF NOT EXISTS upgrade_packages (
    id              BIGSERIAL PRIMARY KEY,
    model           VARCHAR(100) NOT NULL,
    main_version    VARCHAR(50) NOT NULL,
    changelog       TEXT NOT NULL DEFAULT '',
    is_force        BOOLEAN NOT NULL DEFAULT FALSE,
    status          SMALLINT NOT NULL DEFAULT 1,
    created_by      BIGINT,
    user_version    VARCHAR(50) NOT NULL DEFAULT '',           -- (migration 013)
    user_changelog  TEXT NOT NULL DEFAULT '',                  -- (migration 013)
    rollout_type    VARCHAR(20) NOT NULL DEFAULT 'all',        -- (migration 013) all/model/user/device
    rollout_targets TEXT NOT NULL DEFAULT '',                  -- (migration 013) 逗号分隔的 model/user_id/sn
    is_published    BOOLEAN NOT NULL DEFAULT FALSE,            -- (migration 013)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_package_model_version UNIQUE (model, main_version)
);

CREATE INDEX IF NOT EXISTS idx_pkg_model ON upgrade_packages(model);
CREATE INDEX IF NOT EXISTS idx_pkg_status ON upgrade_packages(status);
CREATE INDEX IF NOT EXISTS idx_pkg_created ON upgrade_packages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pkg_published ON upgrade_packages(is_published);
CREATE INDEX IF NOT EXISTS idx_pkg_rollout_type ON upgrade_packages(rollout_type);

-- 升级包明细表（关联芯片固件）(migration 008)
CREATE TABLE IF NOT EXISTS upgrade_package_items (
    id               BIGSERIAL PRIMARY KEY,
    package_id       BIGINT NOT NULL REFERENCES upgrade_packages(id) ON DELETE CASCADE,
    firmware_id      BIGINT NOT NULL REFERENCES firmware_versions(id),
    target_chip      VARCHAR(50) NOT NULL,
    firmware_version VARCHAR(50) NOT NULL,
    CONSTRAINT uq_pkg_firmware UNIQUE (package_id, firmware_id),
    CONSTRAINT uq_pkg_chip UNIQUE (package_id, target_chip)
);

CREATE INDEX IF NOT EXISTS idx_pkg_item_package ON upgrade_package_items(package_id);
CREATE INDEX IF NOT EXISTS idx_pkg_item_firmware ON upgrade_package_items(firmware_id);

-- 升级任务表 (migration 009 + 013 + 032)
CREATE TABLE IF NOT EXISTS upgrade_tasks (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(200) NOT NULL DEFAULT '',
    task_type       VARCHAR(20) NOT NULL,               -- 'single' | 'package'
    firmware_id     BIGINT,                              -- 单芯片模式关联 firmware_versions
    package_id      BIGINT,                              -- 升级包模式关联 upgrade_packages
    model           VARCHAR(100) NOT NULL,
    target_version  VARCHAR(50) NOT NULL DEFAULT '',
    status          VARCHAR(20) NOT NULL DEFAULT 'draft', -- draft/pending/scheduled/running/completed/partial_success/failed/cancelled
    execute_mode    VARCHAR(20) NOT NULL DEFAULT 'manual', -- 'immediate' | 'scheduled' | 'manual'
    scheduled_at    TIMESTAMPTZ,
    rollout_percent INTEGER NOT NULL DEFAULT 100,
    total_devices   INTEGER NOT NULL DEFAULT 0,
    success_count   INTEGER NOT NULL DEFAULT 0,
    failed_count    INTEGER NOT NULL DEFAULT 0,
    source          VARCHAR(20) NOT NULL DEFAULT 'admin', -- (migration 013)
    triggered_by    BIGINT,                               -- (migration 013)
    notes           TEXT NOT NULL DEFAULT '',             -- (migration 013)
    created_by      BIGINT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    executed_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ut_status ON upgrade_tasks(status);
CREATE INDEX IF NOT EXISTS idx_ut_model ON upgrade_tasks(model);
CREATE INDEX IF NOT EXISTS idx_ut_created ON upgrade_tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ut_type ON upgrade_tasks(task_type);
CREATE INDEX IF NOT EXISTS idx_ut_source ON upgrade_tasks(source);
CREATE INDEX IF NOT EXISTS idx_ut_triggered_by ON upgrade_tasks(triggered_by);

-- ============================================
-- 8. 工单相关表 (migration 029)
-- ============================================

CREATE TABLE IF NOT EXISTS work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','closed')),
    priority VARCHAR(16) NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
    device_sn VARCHAR(64),
    creator_id BIGINT NOT NULL,
    assigned_to BIGINT,
    template_type VARCHAR(40),
    resolution TEXT,
    sla_deadline TIMESTAMPTZ,
    sla_overdue_count INTEGER NOT NULL DEFAULT 0,
    escalated_count INTEGER NOT NULL DEFAULT 0,
    resolved_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_orders_status ON work_orders(status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_work_orders_people ON work_orders(creator_id, assigned_to);
CREATE INDEX IF NOT EXISTS idx_work_orders_device ON work_orders(device_sn) WHERE device_sn IS NOT NULL;

CREATE TABLE IF NOT EXISTS work_order_events (
    id BIGSERIAL PRIMARY KEY,
    work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    status VARCHAR(24) NOT NULL,
    operator_id BIGINT NOT NULL,
    remark TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS work_order_attachments (
    id BIGSERIAL PRIMARY KEY,
    work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,
    uploaded_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- 9. RBAC 权限表 (migration 012)
-- ============================================

-- 角色权限映射表，用于API网关RBAC中间件的权限校验
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

-- ============================================
-- 10. 审计日志表 (migration 017)
-- ============================================

-- 记录用户操作审计，用于安全审计和操作追溯
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    operator_id BIGINT,                    -- 操作者用户ID
    operator_name VARCHAR(100) DEFAULT '', -- 操作者用户名/昵称
    action VARCHAR(50) NOT NULL,           -- login/logout/create/update/delete/import/export/bind/unbind/command/approve/reject
    resource_type VARCHAR(50) DEFAULT '',  -- auth/device/station/alarm/firmware/user/config/system
    resource_id BIGINT,                    -- 资源ID（可为空）
    detail JSONB DEFAULT '{}',             -- 操作详情（JSON格式，可包含变更前后值）
    ip VARCHAR(45) DEFAULT '',             -- 操作者IP地址
    user_agent TEXT DEFAULT '',            -- 用户代理（可选）
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_operator ON audit_logs(operator_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON audit_logs(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_ip ON audit_logs(ip);

-- ============================================
-- 11. 系统配置表
-- ============================================

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
-- 12. 设备统计表
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

-- 设备日数据表（JSONB 格式，Go 代码 internal_handler.go 仍引用）
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

-- ============================================
-- 13. 视图
-- ============================================

-- 最新数据视图（查询 device_latest_state，由 device_telemetry_3min 触发器维护）
-- 列名保持与旧视图兼容（Go 代码引用 total_active_power / daily_energy）
CREATE OR REPLACE VIEW v_device_latest AS
SELECT
    device_sn,
    ac_active_power  AS total_active_power,
    daily_pv_energy  AS daily_energy,
    work_state,
    fault_code,
    inverter_temperature AS internal_temperature,
    ac_frequency     AS grid_frequency,
    battery_soc,
    battery_power,
    pv_total_power   AS pv_power,
    event_time       AS data_time,
    updated_at
FROM device_latest_state;

-- ============================================
-- 14. 函数与触发器
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

-- 设备时区同步函数 (migration 031)
-- 设备 station_id 变更时自动从电站同步时区
CREATE OR REPLACE FUNCTION sync_device_timezone()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.station_id IS NOT NULL AND (OLD.station_id IS NULL OR OLD.station_id != NEW.station_id) THEN
        SELECT COALESCE(s.timezone, 'Asia/Shanghai')
        INTO NEW.timezone
        FROM stations s
        WHERE s.id = NEW.station_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_device_timezone ON devices;
CREATE TRIGGER trg_sync_device_timezone
    BEFORE INSERT OR UPDATE OF station_id ON devices
    FOR EACH ROW EXECUTE FUNCTION sync_device_timezone();

-- 清理过期数据函数
CREATE OR REPLACE FUNCTION clean_expired_data()
RETURNS void AS $$
BEGIN
    -- 清理过期验证码
    DELETE FROM verification_codes WHERE expires_at < NOW();
    -- 注意：时序数据由 TimescaleDB 自动管理
    -- user_sessions 已删除（改用 JWT）
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 附注：以下对象定义在迁移文件中，请另行执行
--   - maintain_telemetry_v2_derived() 触发器函数 (migration 025) — 维护 device_latest_state 和 device_energy_day
--   - maintain_latest_cells() 触发器函数 (migration 025) — 维护 device_latest_cells
--   - refresh_device_energy_month() 存储过程 (migration 025) — 刷新 device_energy_month
--   - device_telemetry_hour 连续聚合物化视图 (migration 023) — 小时级聚合
--   - telemetry_field_catalog / device_protocol_versions / device_protocol_fields 等种子数据 (migration 023/026)
--   - role_permissions 种子数据 (migration 012/024)
-- ============================================
