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
CREATE INDEX IF NOT EXISTS idx_cmd_logs_time ON command_logs(created_at);
