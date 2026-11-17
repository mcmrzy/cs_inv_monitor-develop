-- The four options have independent readback bits in Modbus register 0x0351.
WITH settings(command_code, config_group, sort_order) AS (VALUES
    ('set_modbus_power_saving', 'general', 60),
    ('set_modbus_auto_frequency', 'application', 61),
    ('set_modbus_battery_open_alarm', 'general', 62),
    ('set_modbus_inverter_mute', 'general', 63)
), registered_schema AS (
    INSERT INTO device_config_schema (
        param_key, group_code, control_type, scale, min, max,
        display_name_key, sort_order, permission_code, confirmation_mode
    )
    SELECT command_code, config_group, 'boolean', 1, 0, 1,
           'config.' || command_code, sort_order, 'devices:control', 'modal'
    FROM settings
    ON CONFLICT (param_key) DO NOTHING
)
INSERT INTO device_model_commands (
    model_id, command_code, display_name_key, parameter_schema, timeout_seconds,
    risk_level, requires_online, config_domain, operation_kind, permission_code,
    confirmation_mode, min_firmware
)
SELECT m.id, s.command_code, 'config.' || s.command_code,
       '{"args":[{"key":"value","type":"boolean"}]}'::jsonb, 30,
       2, true, s.config_group, 'write', 'devices:control', 'modal', '0.4.54-modbus-full'
FROM device_models m CROSS JOIN settings s
WHERE m.model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
  AND m.is_active AND m.lifecycle_status != 'retired'
ON CONFLICT (model_id, command_code) DO NOTHING;
