-- Rollback migration 027: remove capability columns, restore risk_level
-- constraint (1..3), delete fine-grained permission rows, drop partial index.

-- 1. Drop partial index
DROP INDEX IF EXISTS idx_dmc_model_domain;

-- 2. Delete fine-grained permission codes from role_permissions
DELETE FROM role_permissions
WHERE (resource, action) IN (
    ('device_control', 'basic'),
    ('device_control', 'disruptive'),
    ('device_configure', 'battery'),
    ('device_configure', 'ac_input'),
    ('device_configure', 'parallel'),
    ('device_service', 'diagnostics'),
    ('device_service', 'factory'),
    ('ota', 'control')
);

-- 3. Restore original risk_level CHECK constraint (1..3)
ALTER TABLE device_model_commands DROP CONSTRAINT IF EXISTS device_model_commands_risk_level_check;
ALTER TABLE device_model_commands ADD CONSTRAINT device_model_commands_risk_level_check
    CHECK (risk_level BETWEEN 1 AND 3);

-- 4. Drop capability columns added by migration 027
ALTER TABLE device_model_commands
    DROP COLUMN IF EXISTS config_domain,
    DROP COLUMN IF EXISTS permission_code,
    DROP COLUMN IF EXISTS operation_kind,
    DROP COLUMN IF EXISTS requires_stopped,
    DROP COLUMN IF EXISTS requires_bms_online,
    DROP COLUMN IF EXISTS requires_group_master,
    DROP COLUMN IF EXISTS confirmation_mode,
    DROP COLUMN IF EXISTS ttl_seconds,
    DROP COLUMN IF EXISTS cooldown_seconds,
    DROP COLUMN IF EXISTS precondition_schema,
    DROP COLUMN IF EXISTS ui_schema,
    DROP COLUMN IF EXISTS min_firmware;

DELETE FROM schema_migrations WHERE version=27;
