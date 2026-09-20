-- 123: Align model command permissions with role_permission_grants.
-- Migration 096 defaulted to the singular device:control; actual RBAC grants
-- use devices:control. Migration 110 corrected only device_config_schema.
ALTER TABLE device_model_commands
    ALTER COLUMN permission_code SET DEFAULT 'devices:control';

UPDATE device_model_commands
SET permission_code = 'devices:control', updated_at = NOW()
WHERE permission_code = 'device:control';
