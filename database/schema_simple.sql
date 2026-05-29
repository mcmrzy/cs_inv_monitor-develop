-- 简化版 Schema（已清理，2026-05-28）
-- 完整架构请参考 schema.sql + migration_timescaledb.sql + 各 migration 文件

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nickname VARCHAR(50),
    avatar VARCHAR(500),
    role SMALLINT NOT NULL DEFAULT 5,
    status SMALLINT NOT NULL DEFAULT 1,
    last_login_at TIMESTAMP,
    last_login_ip VARCHAR(45),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

CREATE TABLE IF NOT EXISTS verification_codes (
    id BIGSERIAL PRIMARY KEY,
    target VARCHAR(100) NOT NULL,
    code VARCHAR(10) NOT NULL,
    type VARCHAR(20) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    used BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_verify_code_target_type ON verification_codes(target, type);

CREATE TABLE IF NOT EXISTS stations (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    name VARCHAR(100) NOT NULL,
    station_type VARCHAR(20) NOT NULL DEFAULT 'grid-tied',
    province VARCHAR(50),
    city VARCHAR(50),
    district VARCHAR(50),
    address VARCHAR(200),
    longitude DECIMAL(10,6),
    latitude DECIMAL(10,6),
    capacity DECIMAL(10,2),
    panel_count INTEGER,
    panel_power DECIMAL(10,2),
    battery_capacity DECIMAL(10,2),
    battery_count INTEGER DEFAULT 0,
    installation_date DATE,
    contact_name VARCHAR(50),
    contact_phone VARCHAR(20),
    description TEXT,
    status SMALLINT NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_stations_user ON stations(user_id);

CREATE TABLE IF NOT EXISTS devices (
    id BIGSERIAL PRIMARY KEY,
    sn VARCHAR(50) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    station_id BIGINT,
    model VARCHAR(50) NOT NULL,
    model_code VARCHAR(50),
    name VARCHAR(100),
    status SMALLINT NOT NULL DEFAULT 1,
    firmware_version VARCHAR(50),
    last_heartbeat TIMESTAMP,
    network_type VARCHAR(20) DEFAULT 'wifi',
    signal_strength INTEGER,
    activation_date DATE,
    warranty_date DATE,
    last_data_time TIMESTAMP,
    remark TEXT,
    is_old BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_devices_station ON devices(station_id);
CREATE INDEX IF NOT EXISTS idx_devices_model ON devices(model);

CREATE TABLE IF NOT EXISTS alarms (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    type VARCHAR(50) NOT NULL,
    level SMALLINT NOT NULL,
    message VARCHAR(500),
    value DECIMAL(10,2),
    threshold DECIMAL(10,2),
    status SMALLINT NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    acknowledged_at TIMESTAMP,
    acknowledged_by BIGINT,
    resolved_at TIMESTAMP,
    resolved_by BIGINT,
    solution TEXT,
    remark TEXT
);

CREATE INDEX IF NOT EXISTS idx_alarms_device ON alarms(device_sn);
CREATE INDEX IF NOT EXISTS idx_alarms_status ON alarms(status);
CREATE INDEX IF NOT EXISTS idx_alarms_level ON alarms(level);
CREATE INDEX IF NOT EXISTS idx_alarms_time ON alarms(created_at);

CREATE TABLE IF NOT EXISTS system_configs (
    id BIGSERIAL PRIMARY KEY,
    config_key VARCHAR(50) NOT NULL UNIQUE,
    config_value TEXT,
    description VARCHAR(200),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admin_users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(50),
    role_id BIGINT,
    status SMALLINT NOT NULL DEFAULT 1,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admin_roles (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description VARCHAR(200),
    is_system BOOLEAN DEFAULT FALSE,
    status SMALLINT NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admin_permissions (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(100) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL,
    resource VARCHAR(100) NOT NULL,
    description VARCHAR(200),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS command_logs (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    command_name VARCHAR(50) NOT NULL,
    command_label VARCHAR(100) NOT NULL,
    params JSONB,
    req_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    result_message TEXT,
    executed_by BIGINT NOT NULL,
    ip_address VARCHAR(45),
    retry_count INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn ON command_logs(device_sn);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_user ON command_logs(executed_by);

CREATE TABLE IF NOT EXISTS firmware_versions (
    id BIGSERIAL PRIMARY KEY,
    model VARCHAR(100) NOT NULL,
    version VARCHAR(50) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size BIGINT,
    file_md5 VARCHAR(32),
    changelog TEXT,
    is_force BOOLEAN DEFAULT FALSE,
    status SMALLINT DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(model, version)
);

CREATE TABLE IF NOT EXISTS ota_tasks (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    firmware_id BIGINT NOT NULL,
    firmware_version VARCHAR(50) NOT NULL,
    model VARCHAR(100) NOT NULL,
    target_type VARCHAR(20) NOT NULL,
    target_value VARCHAR(100),
    total_count INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    fail_count INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending',
    description TEXT,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ota_task_devices (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT NOT NULL,
    device_sn VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    progress INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    UNIQUE(task_id, device_sn)
);

CREATE TABLE IF NOT EXISTS alert_rules (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL,
    station_id BIGINT,
    device_sn VARCHAR(50),
    conditions JSONB NOT NULL,
    severity VARCHAR(20) NOT NULL,
    notification_channels JSONB,
    cooldown_minutes INTEGER DEFAULT 60,
    enabled BOOLEAN DEFAULT TRUE,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alert_notifications (
    id BIGSERIAL PRIMARY KEY,
    rule_id BIGINT NOT NULL,
    alarm_id BIGINT,
    channel VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    operator_id BIGINT NOT NULL,
    operator_name VARCHAR(100),
    action VARCHAR(50) NOT NULL,
    resource_type VARCHAR(50),
    resource_id BIGINT,
    resource_name VARCHAR(200),
    detail TEXT,
    ip VARCHAR(45),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
