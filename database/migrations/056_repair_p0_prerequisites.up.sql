-- 056: Repair databases that encountered the historical duplicate 048.
--
-- The old migration set contained both 048_alarms_hypertable_business_indexes
-- and 048_p0_prerequisites. The migrator tracks only the numeric version, so a
-- database that applied the alarms file first skipped the P0 prerequisites.
-- Repeating the prerequisite inserts here is safe and makes both histories
-- converge on the same state.

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

INSERT INTO role_permissions (role, resource, action, is_allowed) VALUES
    (1, 'devices', 'control', true),
    (2, 'devices', 'control', true),
    (3, 'devices', 'control', true),
    (4, 'devices', 'control', true),
    (5, 'devices', 'control', false)
ON CONFLICT (role, resource, action) DO UPDATE
SET is_allowed = EXCLUDED.is_allowed;
