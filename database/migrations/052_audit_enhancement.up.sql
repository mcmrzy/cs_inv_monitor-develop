-- 052_audit_enhancement: 审计日志字段扩展
ALTER TABLE device_control_events
    ADD COLUMN IF NOT EXISTS operator_role SMALLINT,
    ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'web',
    ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45),
    ADD COLUMN IF NOT EXISTS confirmation_mode VARCHAR(20) DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS reject_reason TEXT,
    ADD COLUMN IF NOT EXISTS model_id BIGINT,
    ADD COLUMN IF NOT EXISTS firmware_version VARCHAR(32);
