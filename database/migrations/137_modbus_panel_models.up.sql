-- The panel reports the detected inverter, using PWR2KH12H1 for 2KU.
-- This additive seed leaves existing catalog definitions and their grants intact.
-- Keep registered models and their operational device bindings across app rollbacks.
WITH new_models AS (
    INSERT INTO device_models (
        model_code, model_name, manufacturer, category, description, battery_voltage_v, specifications, lifecycle_status
    ) VALUES
        ('PWR2KH12H1', '2KU', '', 'inverter', 'CS-MB-PANEL · CVTE Modbus RTU', NULL, '{"uart_protocol":"modbus_rtu_v1.27"}', 'active'),
        ('3KU', '3KU', '', 'inverter', 'CS-MB-PANEL · CVTE Modbus RTU', 24, '{"uart_protocol":"modbus_rtu_v1.27"}', 'active'),
        ('6KU', '6KU', '', 'inverter', 'CS-MB-PANEL · CVTE Modbus RTU', NULL, '{"uart_protocol":"modbus_rtu_v1.27"}', 'active'),
        ('12KU', '12KU', '', 'inverter', 'CS-MB-PANEL · CVTE Modbus RTU', NULL, '{"uart_protocol":"modbus_rtu_v1.27"}', 'active')
    ON CONFLICT (model_code) DO NOTHING
    RETURNING id
), fields(field_key, group_code, sort_order) AS (VALUES
    ('pv_total_power', 'pv', 1),
    ('pv1_voltage', 'pv', 2),
    ('pv1_current', 'pv', 3),
    ('pv1_power', 'pv', 4),
    ('pv2_voltage', 'pv', 5),
    ('pv2_current', 'pv', 6),
    ('pv2_power', 'pv', 7),
    ('battery_soc', 'bat', 1),
    ('battery_voltage', 'bat', 2),
    ('battery_current', 'bat', 3),
    ('battery_charge_power', 'bat', 4),
    ('battery_discharge_power', 'bat', 5),
    ('grid_voltage', 'ac', 1),
    ('grid_frequency', 'ac', 2),
    ('ac_input_power', 'ac', 3),
    ('ac_output_voltage', 'ac', 4),
    ('ac_output_frequency', 'ac', 5),
    ('output_current', 'ac', 6),
    ('output_power', 'ac', 7),
    ('load_percent', 'sys', 1),
    ('inverter_temperature', 'sys', 2),
    ('boost_temperature', 'sys', 3),
    ('dc_bus_voltage', 'sys', 4),
    ('sys_status', 'sys', 5),
    ('fault_code', 'sys', 6),
    ('daily_pv_energy', 'eng', 1),
    ('total_pv_energy', 'eng', 2)
), seeded_fields AS (
    -- Expose measured V3 fields only. Unmapped legacy words may contain zero.
    INSERT INTO device_model_fields (
        model_id, field_key, display_name_key, group_code, display_unit, decimal_places, sort_order
    )
    SELECT m.id, f.field_key, 'fields.' || f.field_key, f.group_code, c.base_unit,
           CASE WHEN c.field_type IN ('integer', 'bitmask') OR c.base_unit = 'W' THEN 0 ELSE 1 END,
           f.sort_order
    FROM new_models m CROSS JOIN fields f
    JOIN telemetry_field_catalog c ON c.field_key = f.field_key
), capabilities(command_code, operation_kind, config_domain) AS (VALUES
    ('query_info', 'query', NULL),
    ('query_telemetry', 'query', NULL),
    ('query_config', 'query', NULL),
    -- These three settings have independent readback bits in register 0x0351.
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
FROM new_models m CROSS JOIN capabilities c;

-- A fresh INFO report may already have recorded the model before registration.
-- Prefer reported identity over stale display text, and preserve existing IDs.
UPDATE devices d
SET model_id = m.id, model = m.model_code, updated_at = NOW()
FROM device_models m
WHERE m.model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
  AND m.is_active AND m.lifecycle_status != 'retired'
  AND m.model_code = COALESCE(NULLIF(d.reported_model, ''), d.model)
  AND d.model_id IS NULL AND d.deleted_at IS NULL;
