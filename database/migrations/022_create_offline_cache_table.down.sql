-- 022 down: remove the cached telemetry columns added by the up migration.
-- Safe to run after 046-down recreates the legacy device_telemetry table.
ALTER TABLE device_telemetry DROP COLUMN IF EXISTS grid_frequency;
ALTER TABLE device_telemetry DROP COLUMN IF EXISTS battery_soc;
ALTER TABLE device_telemetry DROP COLUMN IF EXISTS battery_power;
ALTER TABLE device_telemetry DROP COLUMN IF EXISTS pv_power;
