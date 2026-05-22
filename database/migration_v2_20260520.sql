ALTER TABLE devices ADD COLUMN IF NOT EXISTS manufacturer VARCHAR(32) DEFAULT '辰烁科技';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_arm VARCHAR(32);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_esp VARCHAR(32);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_type VARCHAR(20);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS phase VARCHAR(20);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_voltage INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_freq INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_voltage INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_types JSONB;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS mppt_count INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS pv_max_voltage INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS pv_max_power INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS bms_count INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS cell_count INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS ip_address VARCHAR(16);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS city VARCHAR(64);

CREATE TABLE IF NOT EXISTS device_alarms (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    event_type VARCHAR(20),
    source VARCHAR(20),
    fault_code INT,
    fault_desc VARCHAR(128),
    alarm_code INT,
    trigger_info JSONB,
    is_resolved SMALLINT DEFAULT 0,
    resolved_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_alarms_device_time ON device_alarms(device_sn, created_at);

CREATE TABLE IF NOT EXISTS command_logs (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    cmd VARCHAR(100) NOT NULL,
    result VARCHAR(50),
    message TEXT,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_device_time ON command_logs(device_sn, sent_at);
