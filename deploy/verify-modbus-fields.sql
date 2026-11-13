-- Use migration 139's 27 required keys. Extra model fields are allowed.
DO $$
DECLARE
    missing text;
BEGIN
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
    ), target(model_code) AS (VALUES ('PWR2KH12H1'), ('3KU'), ('6KU'), ('12KU'))
    SELECT string_agg(t.model_code || ':' || e.field_key, ', ' ORDER BY t.model_code, e.field_key)
    INTO missing
    FROM target t CROSS JOIN expected e
    LEFT JOIN device_models m ON m.model_code = t.model_code
      AND m.is_active AND m.lifecycle_status != 'retired'
    LEFT JOIN telemetry_field_catalog c ON c.field_key = e.field_key
    LEFT JOIN device_model_fields f ON f.model_id = m.id AND f.field_key = e.field_key
    WHERE c.field_key IS NULL OR f.field_key IS NULL;

    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'Missing required Modbus model fields: %', missing;
    END IF;
END $$;

SELECT m.model_code, count(f.field_key) AS total_fields
FROM device_models m LEFT JOIN device_model_fields f ON f.model_id = m.id
WHERE m.model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
GROUP BY m.model_code ORDER BY m.model_code;
