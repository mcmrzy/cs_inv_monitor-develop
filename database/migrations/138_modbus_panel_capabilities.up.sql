-- Models registered before migration 137 also need the independently readable
-- Modbus settings. Preserve every existing command, including disabled grants.
WITH capabilities(command_code, operation_kind, config_domain) AS (VALUES
    ('query_info', 'query', NULL),
    ('query_telemetry', 'query', NULL),
    ('query_config', 'query', NULL),
    ('set_overload_restart', 'write', 'general'),
    ('set_high_temp_restart', 'write', 'general'),
    ('set_overload_use_city_power', 'write', 'application')
)
INSERT INTO device_model_commands (
    model_id, command_code, display_name_key, parameter_schema, timeout_seconds, risk_level,
    requires_online, config_domain, operation_kind, permission_code
)
SELECT m.id, c.command_code, 'commands.' || c.command_code,
       CASE WHEN c.operation_kind = 'query' THEN '{"args":[]}'::jsonb
            ELSE '{"args":[{"key":"value","type":"boolean"}]}'::jsonb END,
       CASE WHEN c.operation_kind = 'query' THEN 10 ELSE 30 END,
       CASE WHEN c.operation_kind = 'query' THEN 1 ELSE 2 END,
       TRUE, c.config_domain, c.operation_kind, 'devices:control'
FROM device_models m CROSS JOIN capabilities c
WHERE m.model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
  AND m.is_active AND m.lifecycle_status != 'retired'
ON CONFLICT (model_id, command_code) DO NOTHING;
