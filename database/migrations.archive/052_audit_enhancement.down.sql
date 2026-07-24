-- 052_audit_enhancement: 回滚审计日志字段扩展
ALTER TABLE device_control_events
    DROP COLUMN IF EXISTS firmware_version,
    DROP COLUMN IF EXISTS model_id,
    DROP COLUMN IF EXISTS reject_reason,
    DROP COLUMN IF EXISTS confirmation_mode,
    DROP COLUMN IF EXISTS ip_address,
    DROP COLUMN IF EXISTS source,
    DROP COLUMN IF EXISTS operator_role;
