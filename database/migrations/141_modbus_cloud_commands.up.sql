-- 138–140 were allocated in the production release. Keep this seed additive.
WITH models AS (
    SELECT id, model_code FROM device_models
    WHERE model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
      AND is_active AND lifecycle_status != 'retired'
), scalar(command_code, domain, options, unit) AS (VALUES
    ('set_output_voltage', 'application', '{"208":"208 V","220":"220 V","230":"230 V","240":"240 V"}'::jsonb, 'V'),
    ('set_output_frequency', 'application', '{"50":"50 Hz","60":"60 Hz"}', 'Hz'),
    ('set_output_priority', 'general', '{"2":"utility_first","3":"solar_battery_utility","4":"solar_utility_battery"}', ''),
    ('set_ac_volt_range', 'application', '{"1":"appliance","2":"ups","3":"generator"}', ''),
    ('set_charge_priority', 'hybrid', '{"1":"solar_first","2":"solar_utility","3":"solar_only"}', ''),
    ('set_max_charge_current', 'hybrid', '{"2":"2 A","10":"10 A","20":"20 A","30":"30 A","40":"40 A","50":"50 A","60":"60 A","70":"70 A","80":"80 A","90":"90 A","100":"100 A"}', 'A')
), per_model AS (
    SELECT m.id, s.command_code, s.domain, s.unit,
           CASE
               WHEN m.model_code = '12KU' AND s.command_code = 'set_output_voltage' THEN s.options - '208'
               WHEN m.model_code = '3KU' AND s.command_code = 'set_output_priority'
                   THEN s.options || '{"4":"solar_first"}'::jsonb
               WHEN m.model_code = '3KU' AND s.command_code = 'set_ac_volt_range' THEN s.options - '3'
               ELSE s.options
           END AS options
    FROM models m CROSS JOIN scalar s
    WHERE s.command_code != 'set_max_charge_current' OR m.model_code = '3KU'
), scalar_specs AS (
    SELECT m.id, m.command_code, m.domain,
           jsonb_build_object('args', jsonb_build_array(jsonb_build_object(
               'key', 'value', 'type', 'integer', 'unit', m.unit,
               'min', min(k.value::int), 'max', max(k.value::int),
               'enum', jsonb_agg(k.value::int ORDER BY k.value::int)))) AS parameters,
           jsonb_build_object('config_enum', m.options) AS ui_schema
    FROM per_model m CROSS JOIN LATERAL jsonb_object_keys(m.options) AS k(value)
    GROUP BY m.id, m.command_code, m.domain, m.unit, m.options
), other(command_code, operation_kind, domain, parameters, risk, confirmation, minimum_firmware) AS (VALUES
    ('ac_on', 'write', 'output', '{"args":[]}'::jsonb, 2, 'modal', '0.4.47-modbus-full'),
    ('ac_off', 'write', 'output', '{"args":[]}', 2, 'modal', '0.4.47-modbus-full'),
    ('set_modbus_input_change_alarm', 'write', 'general', '{"args":[{"key":"value","type":"boolean"}]}', 2, NULL, NULL),
    ('set_overload_restart', 'write', 'general', '{"args":[{"key":"value","type":"boolean"}]}', 2, NULL, NULL),
    ('set_high_temp_restart', 'write', 'general', '{"args":[{"key":"value","type":"boolean"}]}', 2, NULL, NULL),
    ('set_overload_use_city_power', 'write', 'application', '{"args":[{"key":"value","type":"boolean"}]}', 2, NULL, NULL),
    ('query_info', 'query', NULL, '{"args":[]}', 1, NULL, NULL),
    ('query_config', 'query', NULL, '{"args":[]}', 1, NULL, NULL),
    ('query_telemetry', 'query', NULL, '{"args":[]}', 1, NULL, NULL)
), grants AS (
    SELECT id, command_code, 'write' AS operation_kind, domain, parameters, 2 AS risk,
           'modal' AS confirmation, NULL::text AS minimum_firmware, ui_schema
    FROM scalar_specs
    UNION ALL
    SELECT m.id, o.command_code, o.operation_kind, o.domain, o.parameters, o.risk,
           o.confirmation, o.minimum_firmware, '{}'::jsonb
    FROM models m CROSS JOIN other o
)
INSERT INTO device_model_commands (
    model_id, command_code, display_name_key, parameter_schema, timeout_seconds, risk_level,
    requires_online, config_domain, operation_kind, permission_code, confirmation_mode, min_firmware, ui_schema
)
SELECT id, command_code, 'commands.' || command_code, parameters,
       CASE WHEN operation_kind = 'query' THEN 10 ELSE 30 END,
       risk, TRUE, domain, operation_kind, 'devices:control', confirmation, minimum_firmware, ui_schema
FROM grants
ON CONFLICT (model_id, command_code) DO NOTHING;

-- Both config ingestion and the settings screens use these model-specific enums.
-- Keep the global schema so existing controllers keep their current ranges.
CREATE VIEW device_model_config_options AS
SELECT model_id, command_code AS param_key,
       ui_schema->'config_enum' AS enum_map,
       (parameter_schema->'args'->0->>'min')::numeric AS min,
       (parameter_schema->'args'->0->>'max')::numeric AS max
FROM device_model_commands
WHERE jsonb_typeof(ui_schema->'config_enum') = 'object';

INSERT INTO device_config_schema (
    param_key, group_code, control_type, scale, min, max, display_name_key, sort_order, permission_code
) VALUES (
    'set_modbus_input_change_alarm', 'general', 'boolean', 1, 0, 1,
    'config.set_modbus_input_change_alarm', 16, 'devices:control'
)
ON CONFLICT (param_key) DO NOTHING;
