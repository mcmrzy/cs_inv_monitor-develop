DROP INDEX IF EXISTS idx_telemetry_bms_summary_sn_time;
ALTER TABLE device_telemetry_3min DROP COLUMN IF EXISTS bms_summary;
