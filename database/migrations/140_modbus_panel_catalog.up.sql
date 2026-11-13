-- Restore the six measured fields missing from the production catalog.
-- Their definitions match migration 091 and the model layout matches migration 139.
INSERT INTO telemetry_field_catalog (field_key, field_type, base_unit, category, description, allowed_aggregates)
VALUES
    ('ac_input_power','float','W','ac','AC 输入有功功率','["avg","min","max","last"]'),
    ('battery_charge_power','float','W','battery','电池充电功率','["avg","min","max","last"]'),
    ('battery_discharge_power','float','W','battery','电池放电功率','["avg","min","max","last"]'),
    ('boost_temperature','float','C','system','Boost 温度','["avg","min","max","last"]'),
    ('grid_voltage','float','V','ac','电网电压','["avg","min","max","last"]'),
    ('sys_status','bitmask',NULL,'system','系统状态位（12 位：StandBy/Fault/Charge/Discharging/PVCharging/ACCharging/GenCharging/ACBypass/ToLoad/Pvinput/AcInput/GeInput）','["last"]')
ON CONFLICT (field_key) DO NOTHING;

WITH fields(field_key, group_code, sort_order) AS (VALUES
    ('ac_input_power', 'ac', 3),
    ('battery_charge_power', 'bat', 4),
    ('battery_discharge_power', 'bat', 5),
    ('boost_temperature', 'sys', 3),
    ('grid_voltage', 'ac', 1),
    ('sys_status', 'sys', 5)
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
ON CONFLICT (model_id, field_key) DO NOTHING;
