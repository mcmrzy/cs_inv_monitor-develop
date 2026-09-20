ALTER TABLE device_model_commands
    ALTER COLUMN permission_code SET DEFAULT 'device:control';

UPDATE device_model_commands
SET permission_code = 'device:control', updated_at = NOW()
WHERE permission_code = 'devices:control';
