-- Add the measured V3 field catalog to previously registered Modbus models
-- whose field configuration is empty. Preserve every existing configuration.
WITH fields(field_key, group_code, sort_order) AS (VALUES
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
)
INSERT INTO device_model_fields (
    model_id, field_key, display_name_key, group_code, display_unit, decimal_places, sort_order
)
SELECT m.id, f.field_key, 'fields.' || f.field_key, f.group_code, c.base_unit,
       CASE WHEN c.field_type IN ('integer', 'bitmask') OR c.base_unit = 'W' THEN 0 ELSE 1 END,
       f.sort_order
FROM device_models m CROSS JOIN fields f
JOIN telemetry_field_catalog c ON c.field_key = f.field_key
WHERE m.model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
  AND m.is_active AND m.lifecycle_status != 'retired'
  AND NOT EXISTS (SELECT 1 FROM device_model_fields existing WHERE existing.model_id = m.id)
ON CONFLICT (model_id, field_key) DO NOTHING;
