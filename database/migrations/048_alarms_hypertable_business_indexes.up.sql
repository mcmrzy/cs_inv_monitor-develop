-- 048: Add hypertable-optimized business indexes to the alarms table.
--
-- Migration 036 converted alarms to a TimescaleDB hypertable partitioned on
-- occurred_at.  The composite indexes restored by migrations 039 and 044 use
-- created_at, which is NOT the partitioning column.  Without a composite index
-- that includes occurred_at, queries that filter by device_sn + time range or
-- status + time range cannot prune chunks efficiently: TimescaleDB performs
-- chunk exclusion on the WHERE clause, but within each chunk the planner falls
-- back to a bitmap scan on the single-column index followed by a filter,
-- effectively degrading to a cross-chunk sequential scan for wide time ranges.
--
-- These indexes complement (do not replace) the existing created_at-based
-- indexes.  They use occurred_at — the hypertable partitioning column — so the
-- planner can combine chunk exclusion with an ordered index scan, eliminating
-- the cross-chunk scan penalty for the three most common alarm query patterns:
--
--   1. Device alarm history:  WHERE device_sn = ? AND occurred_at BETWEEN ? AND ?
--   2. Pending alarm dashboard: WHERE status = 0 AND occurred_at > ?
--   3. Station alarm overview: WHERE station_id = ? AND occurred_at BETWEEN ? AND ?

CREATE INDEX IF NOT EXISTS idx_alarms_device_occurred
    ON alarms(device_sn, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_alarms_pending_occurred
    ON alarms(status, occurred_at DESC)
    WHERE status = 0;

CREATE INDEX IF NOT EXISTS idx_alarms_station_occurred
    ON alarms(station_id, occurred_at DESC)
    WHERE station_id IS NOT NULL;
