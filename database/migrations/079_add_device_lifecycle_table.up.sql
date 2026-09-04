-- 079: Add device_lifecycle table for device lifecycle events
-- This table stores device lifecycle events (e.g., device creation, firmware updates, etc.)

CREATE TABLE IF NOT EXISTS device_lifecycle (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(50) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    description TEXT,
    triggered_by BIGINT,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_lifecycle_sn ON device_lifecycle(device_sn);
CREATE INDEX IF NOT EXISTS idx_device_lifecycle_type ON device_lifecycle(event_type);
CREATE INDEX IF NOT EXISTS idx_device_lifecycle_sn_time ON device_lifecycle(device_sn, created_at DESC);

COMMENT ON TABLE device_lifecycle IS '设备生命周期事件表';
COMMENT ON COLUMN device_lifecycle.device_sn IS '设备序列号';
COMMENT ON COLUMN device_lifecycle.event_type IS '事件类型（如：created, firmware_update, status_change等）';
COMMENT ON COLUMN device_lifecycle.description IS '事件描述';
COMMENT ON COLUMN device_lifecycle.triggered_by IS '触发者用户ID';
COMMENT ON COLUMN device_lifecycle.metadata IS '事件元数据（JSON格式）';
COMMENT ON COLUMN device_lifecycle.created_at IS '事件发生时间';
