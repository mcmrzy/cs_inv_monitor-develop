-- 026_p0_prerequisites DOWN: Remove system commands and devices:control permission added by the UP migration.

-- Remove devices:control permission
DELETE FROM role_permissions
WHERE resource = 'devices' AND action = 'control';

-- Remove the six system commands registered for CS-I10-6k2
DELETE FROM device_model_commands
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-I10-6k2')
  AND command_code IN ('get_params', 'set_params', 'set_control', 'set_alarm', 'batch_config', 'reset');
