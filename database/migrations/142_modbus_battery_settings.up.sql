-- Reuse the existing control keys while keeping the L10 schema and behavior.
WITH models AS (
    SELECT id, model_code FROM device_models
    WHERE model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
      AND is_active AND lifecycle_status != 'retired'
), soc(command_code, lower_limit, upper_limit) AS (
    VALUES ('set_soc_cutoff', 5, 50), ('set_soc_back_utl', 10, 90), ('set_soc_back_bat', 10, 100)
), soc_options AS (
    SELECT s.command_code,
           jsonb_build_object('args', jsonb_build_array(jsonb_build_object(
               'key', 'value', 'type', 'integer', 'min', 0, 'max', s.upper_limit,
               'unit', '%', 'enum', '[0]'::jsonb || jsonb_agg(v ORDER BY v)))) AS parameters,
           jsonb_build_object('config_enum', '{"0":"off"}'::jsonb ||
               jsonb_object_agg(v::text, v::text || '%'), 'config_validation', '{}'::jsonb) AS ui
    FROM soc s CROSS JOIN LATERAL generate_series(s.lower_limit, s.upper_limit) AS n(v)
    GROUP BY s.command_code, s.upper_limit
), eq_time_options AS (
    SELECT jsonb_agg(v ORDER BY v) AS values,
           jsonb_object_agg(v::text, v::text || ' min') AS labels
    FROM generate_series(60, 900, 60) AS n(v)
), equalization(command_code, argument, labels) AS (
    SELECT n.command_code, jsonb_build_object(
               'key', 'value', 'type', 'integer', 'min', 60, 'max', 900,
               'unit', 'min', 'enum', t.values), t.labels
    FROM eq_time_options t CROSS JOIN (VALUES ('set_equalize_time'), ('set_equalize_timeout')) AS n(command_code)
    UNION ALL VALUES
        ('set_equalize_enable', '{"key":"value","type":"boolean"}'::jsonb, NULL::jsonb),
        ('set_equalize_voltage', '{"key":"value","type":"number","min":24,"max":30,"unit":"V"}', NULL),
        ('set_equalize_interval', '{"key":"value","type":"integer","min":1,"max":90,"unit":"day"}', NULL)
), grants AS (
    SELECT m.id, s.command_code, s.parameters, s.ui
    FROM models m CROSS JOIN soc_options s
    UNION ALL
    SELECT m.id, e.command_code, jsonb_build_object('args', jsonb_build_array(e.argument)),
           jsonb_strip_nulls(jsonb_build_object('config_enum', e.labels,
               'config_visibility', '{"param":"set_battery_type","in":[1,2]}'::jsonb))
    FROM models m CROSS JOIN equalization e
    WHERE m.model_code = '3KU'
)
INSERT INTO device_model_commands (
    model_id, command_code, display_name_key, parameter_schema, timeout_seconds, risk_level,
    requires_online, config_domain, operation_kind, permission_code, confirmation_mode, min_firmware, ui_schema
)
SELECT id, command_code, 'commands.' || command_code, parameters, 30, 2,
       TRUE, 'hybrid', 'write', 'devices:control', 'modal', '0.4.53-modbus-full', ui
FROM grants
ON CONFLICT (model_id, command_code) DO NOTHING;

-- Resolve display and ingestion options from the same grants.
CREATE OR REPLACE VIEW device_model_config_options AS
SELECT model_id, command_code AS param_key,
       ui_schema->'config_enum' AS enum_map,
       (parameter_schema->'args'->0->>'min')::numeric AS min,
       (parameter_schema->'args'->0->>'max')::numeric AS max,
       ui_schema->'config_visibility' AS visibility,
       ui_schema->'config_validation' AS validation
FROM device_model_commands
WHERE jsonb_typeof(ui_schema->'config_enum') = 'object'
   OR ui_schema ? 'config_visibility'
   OR ui_schema ? 'config_validation';
