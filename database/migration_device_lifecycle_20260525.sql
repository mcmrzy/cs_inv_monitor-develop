CREATE TABLE IF NOT EXISTS device_unbind_requests (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    requested_by BIGINT NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    reviewed_by BIGINT,
    review_comment TEXT,
    reviewed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS device_lifecycle (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    description TEXT,
    triggered_by BIGINT,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_lifecycle_sn ON device_lifecycle(device_sn);
CREATE INDEX idx_lifecycle_type ON device_lifecycle(event_type);
CREATE INDEX idx_unbind_requests_sn ON device_unbind_requests(device_sn);
CREATE INDEX idx_unbind_requests_status ON device_unbind_requests(status);
