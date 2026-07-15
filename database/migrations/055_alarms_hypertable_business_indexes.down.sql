-- 055 DOWN: Remove the hypertable-optimized alarms indexes.
-- The created_at-based indexes from migrations 039/044 remain in place.

DROP INDEX IF EXISTS idx_alarms_station_occurred;
DROP INDEX IF EXISTS idx_alarms_pending_occurred;
DROP INDEX IF EXISTS idx_alarms_device_occurred;
