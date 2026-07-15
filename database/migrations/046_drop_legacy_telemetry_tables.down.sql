-- 046 down: restore only the legacy table shapes for emergency application
-- rollback. Dropped telemetry is not recoverable by this migration.

CREATE TABLE IF NOT EXISTS device_telemetry (
    id BIGSERIAL,
    device_sn VARCHAR(50) NOT NULL,
    model_code VARCHAR(50),
    topic VARCHAR(200),
    data JSONB NOT NULL,
    total_active_power DECIMAL(12,2) DEFAULT 0,
    daily_energy DECIMAL(14,4) DEFAULT 0,
    work_state VARCHAR(50),
    fault_code VARCHAR(50),
    internal_temperature DECIMAL(6,1) DEFAULT 0,
    grid_frequency NUMERIC(6,2),
    battery_soc NUMERIC(4,1),
    battery_power NUMERIC(10,2),
    pv_power NUMERIC(10,2),
    time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time ON device_telemetry(device_sn, time DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_model ON device_telemetry(model_code);
CREATE INDEX IF NOT EXISTS idx_telemetry_time ON device_telemetry(time DESC);

CREATE TABLE IF NOT EXISTS device_day_data (
    device_sn VARCHAR(50) NOT NULL,
    data_date DATE NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
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
