-- 046: retire the pre-V1 JSONB telemetry and station rollup stores.
--
-- No data is copied intentionally: the product decision permits discarding
-- legacy telemetry. All current reads are backed by device_telemetry_3min,
-- device_telemetry_hour, device_energy_day, or v_device_telemetry_compat.
-- DROP without CASCADE is deliberate: an unexpected dependency must stop the
-- migration instead of silently deleting a live view or function.

DROP TABLE IF EXISTS station_day_data;
DROP TABLE IF EXISTS device_day_data;
DROP TABLE IF EXISTS device_telemetry;
