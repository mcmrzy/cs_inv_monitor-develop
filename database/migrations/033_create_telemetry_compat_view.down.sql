-- 033 down: revert to legacy v_device_latest on device_telemetry
-- and drop the compatibility view.

DROP VIEW IF EXISTS v_device_latest;
DROP VIEW IF EXISTS v_device_telemetry_compat;

-- Restore the original v_device_latest backed by device_telemetry
CREATE OR REPLACE VIEW v_device_latest AS
SELECT DISTINCT ON (dt.device_sn)
    dt.device_sn,
    dt.model_code,
    dt.topic,
    dt.data,
    dt.total_active_power,
    dt.daily_energy,
    dt.work_state,
    dt.fault_code,
    dt.internal_temperature,
    dt.grid_frequency,
    dt.battery_soc,
    dt.battery_power,
    dt.pv_power,
    dt.time    AS data_time,
    dt.created_at AS updated_at
FROM device_telemetry dt
ORDER BY dt.device_sn, dt.time DESC;
