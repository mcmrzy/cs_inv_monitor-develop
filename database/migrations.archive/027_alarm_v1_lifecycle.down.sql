DROP INDEX IF EXISTS idx_alarms_v1_active;
ALTER TABLE alarms
    DROP COLUMN IF EXISTS event_state,
    DROP COLUMN IF EXISTS alarm_source;
