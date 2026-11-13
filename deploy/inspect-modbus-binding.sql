BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '15s';
SET LOCAL TIME ZONE 'UTC';

SELECT json_build_object(
    'device_id', d.id,
    'sn_suffix', CASE WHEN length(d.sn) > 6 THEN right(d.sn, 6) ELSE '[masked]' END,
    'reported_model', d.reported_model,
    'model', d.model,
    'registered_model', m.model_code,
    'firmware_esp', d.firmware_esp,
    'info_reported_at', d.info_reported_at,
    'last_online_at', d.last_online_at,
    'status', d.status,
    'manufacturer', d.manufacturer,
    'device_type', d.device_type,
    'rated_power_kw', d.rated_power,
    'rated_power_w', d.rated_power_w,
    'rated_voltage_v', d.rated_voltage,
    'rated_frequency_hz', d.rated_freq,
    'battery_voltage_v', d.battery_voltage,
    'battery_type', d.battery_type,
    'cell_count', d.cell_count,
    'temp_sensor_count', d.temp_sensor_count,
    'last_user_update_audit_at', (
        SELECT max(a.created_at)
        FROM audit_logs a
        WHERE a.action = 'update' AND a.resource_type = 'device'
          AND a.operator_id > 0 AND a.detail->>'sn' = d.sn
    ),
    'active_ota', EXISTS (
        SELECT 1 FROM device_upgrades u
        WHERE u.device_sn = d.sn AND u.status IN ('pending', 'downloading', 'upgrading')
    ),
    'active_ota_task', EXISTS (
        SELECT 1 FROM device_upgrades u JOIN upgrade_tasks t ON t.id = u.task_id
        WHERE u.device_sn = d.sn AND t.status IN ('pending', 'scheduled', 'running')
    )
)
FROM devices d LEFT JOIN device_models m ON m.id = d.model_id
WHERE d.deleted_at IS NULL AND d.firmware_esp LIKE '%-modbus-full%'
ORDER BY d.id;

WITH expected(command_code) AS (VALUES
    ('query_info'), ('query_telemetry'), ('query_config'),
    ('set_overload_restart'), ('set_high_temp_restart'), ('set_overload_use_city_power')
)
SELECT json_build_object(
    'target_model', 'PWR2KH12H1',
    'model_id', m.id,
    'is_active', m.is_active,
    'lifecycle_status', m.lifecycle_status,
    'manufacturer', m.manufacturer,
    'category', m.category,
    'rated_power_kw', m.rated_power_kw,
    'rated_power_w', m.rated_power_w,
    'rated_voltage_v', m.rated_voltage_v,
    'rated_frequency_hz', m.rated_frequency_hz,
    'battery_voltage_v', m.battery_voltage_v,
    'battery_type', m.battery_type,
    'cell_count', m.cell_count,
    'temp_sensor_count', m.temp_sensor_count,
    'field_count', (SELECT count(*) FROM device_model_fields f WHERE f.model_id = m.id),
    'capabilities', (
        SELECT json_object_agg(e.command_code, c.is_enabled ORDER BY e.command_code)
        FROM expected e LEFT JOIN device_model_commands c
          ON c.model_id = m.id AND c.command_code = e.command_code
    )
)
FROM (VALUES ('PWR2KH12H1')) AS target(model_code)
LEFT JOIN device_models m ON m.model_code = target.model_code;

-- Compare the exact migration 139 fields with the global catalog and each model.
WITH expected(field_key) AS (VALUES
    ('pv_total_power'), ('pv1_voltage'), ('pv1_current'),
    ('pv1_power'), ('pv2_voltage'), ('pv2_current'),
    ('pv2_power'), ('battery_soc'), ('battery_voltage'),
    ('battery_current'), ('battery_charge_power'), ('battery_discharge_power'),
    ('grid_voltage'), ('grid_frequency'), ('ac_input_power'),
    ('ac_output_voltage'), ('ac_output_frequency'), ('output_current'),
    ('output_power'), ('load_percent'), ('inverter_temperature'),
    ('boost_temperature'), ('dc_bus_voltage'), ('sys_status'),
    ('fault_code'), ('daily_pv_energy'), ('total_pv_energy')
), target(model_code) AS (VALUES ('PWR2KH12H1'), ('3KU'), ('6KU'), ('12KU')),
gaps AS (
    SELECT 'telemetry_field_catalog' AS scope, NULL::text AS model_code,
           e.field_key, c.field_key IS NULL AS missing
    FROM expected e LEFT JOIN telemetry_field_catalog c ON c.field_key = e.field_key
    UNION ALL
    SELECT 'device_model_fields', t.model_code,
           e.field_key, f.field_key IS NULL
    FROM target t CROSS JOIN expected e
    LEFT JOIN device_models m ON m.model_code = t.model_code
    LEFT JOIN device_model_fields f ON f.model_id = m.id AND f.field_key = e.field_key
)
SELECT json_build_object(
    'scope', scope,
    'model_code', model_code,
    'expected_count', count(*),
    'missing_count', count(*) FILTER (WHERE missing),
    'missing_keys', COALESCE(json_agg(field_key ORDER BY field_key) FILTER (WHERE missing), '[]'::json)
)
FROM gaps GROUP BY scope, model_code
ORDER BY scope DESC, model_code;

COMMIT;
