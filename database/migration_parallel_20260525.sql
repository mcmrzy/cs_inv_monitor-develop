CREATE TABLE IF NOT EXISTS parallel_configs (
    id BIGSERIAL PRIMARY KEY,
    group_name VARCHAR(100) NOT NULL,
    phase_config VARCHAR(10) DEFAULT 'single',
    master_sn VARCHAR(50) NOT NULL,
    slave_sns TEXT,
    circulating_current_threshold DECIMAL(10,2),
    load_balance_deviation DECIMAL(5,1),
    status SMALLINT DEFAULT 1,
    created_by BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS parallel_status (
    id BIGSERIAL PRIMARY KEY,
    parallel_id BIGINT NOT NULL,
    device_sn VARCHAR(50) NOT NULL,
    output_power DECIMAL(10,2) DEFAULT 0,
    load_percent DECIMAL(5,1) DEFAULT 0,
    phase_angle_offset DECIMAL(10,4) DEFAULT 0,
    circulating_current DECIMAL(8,3) DEFAULT 0,
    sync_status VARCHAR(20) DEFAULT 'synced',
    role VARCHAR(20) NOT NULL,
    data_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_parallel_status_pid ON parallel_status(parallel_id);
CREATE INDEX IF NOT EXISTS idx_parallel_status_sn ON parallel_status(device_sn);
