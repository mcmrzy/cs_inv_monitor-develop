DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version=137) THEN
    RAISE EXCEPTION 'Modbus model migration 137 is missing';
  END IF;
  IF (SELECT count(*) FROM device_models WHERE model_code IN ('PWR2KH12H1','3KU','6KU','12KU')
      AND is_active AND lifecycle_status!='retired') <> 4 THEN
    RAISE EXCEPTION 'Modbus model registry is incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM device_models m WHERE m.model_code IN ('PWR2KH12H1','3KU','6KU','12KU')
      AND (SELECT count(*) FROM device_model_commands c WHERE c.model_id=m.id AND c.command_code IN
      ('query_info','query_telemetry','query_config','set_overload_restart','set_high_temp_restart','set_overload_use_city_power')) <> 6) THEN
    RAISE EXCEPTION 'Modbus command capabilities are incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM devices d JOIN device_models m
      ON m.model_code=COALESCE(NULLIF(d.reported_model,''),d.model)
      WHERE m.model_code IN ('PWR2KH12H1','3KU','6KU','12KU') AND m.is_active
      AND m.lifecycle_status!='retired' AND d.model_id IS NULL AND d.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Reported Modbus identity remains unbound';
  END IF;
END $$;
SELECT json_build_object('migration',137,'models',count(*),'modbus_registry_ready',true)
FROM device_models WHERE model_code IN ('PWR2KH12H1','3KU','6KU','12KU');
SELECT m.model_code,m.model_name,count(d.id) AS bound_devices
FROM device_models m LEFT JOIN devices d ON d.model_id=m.id AND d.deleted_at IS NULL
WHERE m.model_code IN ('PWR2KH12H1','3KU','6KU','12KU')
GROUP BY m.model_code,m.model_name ORDER BY m.model_code;
