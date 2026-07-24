-- 026_p0_prerequisites: Register legacy system commands and add devices:control permission.
-- The systemCommands whitelist in services.go (get_params, set_params, set_control,
-- set_alarm, batch_config, reset) bypassed model-capability validation.  Before we can
-- remove that whitelist we must persist these commands into device_model_commands so the
-- standard validation path recognises them.
-- Note: restart, query_config and query_telemetry were already registered in migration 023.
-- Note: ota is handled by a dedicated OTA service path and is intentionally not registered here.

-- =============================================================
-- 1. Register missing system commands for CS-I10-6k2
-- =============================================================
WITH commands(command_code, display_name_key, parameter_schema, timeout_seconds, risk_level) AS (VALUES
    ('get_params',   'commands.get_params',   '{"args":[]}'::jsonb, 30, 1),
    ('set_params',   'commands.set_params',   '{"args":[]}'::jsonb, 30, 2),
    ('set_control',  'commands.set_control',  '{"args":[]}'::jsonb, 30, 2),
    ('set_alarm',    'commands.set_alarm',    '{"args":[]}'::jsonb, 30, 2),
    ('batch_config', 'commands.batch_config', '{"args":[]}'::jsonb, 60, 2),
    ('reset',        'commands.reset',        '{"args":[]}'::jsonb, 30, 2)
)
INSERT INTO device_model_commands (model_id, command_code, display_name_key, parameter_schema, timeout_seconds, risk_level)
SELECT dm.id, c.command_code, c.display_name_key, c.parameter_schema, c.timeout_seconds, c.risk_level
FROM device_models dm
CROSS JOIN commands c
WHERE dm.model_code = 'CS-I10-6k2'
ON CONFLICT (model_id, command_code) DO NOTHING;

-- =============================================================
-- 2. Grant devices:control permission to roles 1-4, deny for role 5
-- =============================================================
INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'devices', 'control', true),
    (2, 'devices', 'control', true),
    (3, 'devices', 'control', true),
    (4, 'devices', 'control', true),
    (5, 'devices', 'control', false)
ON CONFLICT (role, resource, action) DO NOTHING;
