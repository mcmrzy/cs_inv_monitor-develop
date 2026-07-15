-- 055: Add hypertable-optimized business indexes to the alarms table.
--
-- Renumbered from 048 because 048_p0_prerequisites is the canonical migration
-- 048 and migration versions are the primary key in schema_migrations.

CREATE INDEX IF NOT EXISTS idx_alarms_device_occurred
    ON alarms(device_sn, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_alarms_pending_occurred
    ON alarms(status, occurred_at DESC)
    WHERE status = 0;

CREATE INDEX IF NOT EXISTS idx_alarms_station_occurred
    ON alarms(station_id, occurred_at DESC)
    WHERE station_id IS NOT NULL;
