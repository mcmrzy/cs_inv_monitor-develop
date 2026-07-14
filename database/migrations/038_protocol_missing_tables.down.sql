-- =====================================================
-- Migration 038 (DOWN): Drop 5 protocol-mandated tables
-- =====================================================
-- Drops tables in reverse creation order.
-- Hypertable compression/retention policies are removed
-- before dropping the tables to avoid leftover jobs.
-- =====================================================

-- 5. device_three_phase_3min (hypertable) — remove policies then drop
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
          AND hypertable_name = 'device_three_phase_3min'
    ) THEN
        PERFORM remove_compression_policy('device_three_phase_3min', if_exists => TRUE);
    END IF;

    IF EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
          AND hypertable_name = 'device_three_phase_3min'
    ) THEN
        PERFORM remove_retention_policy('device_three_phase_3min', if_exists => TRUE);
    END IF;
END $$;

DROP TABLE IF EXISTS device_three_phase_3min;

-- 4. device_parallel_events
DROP TABLE IF EXISTS device_parallel_events;

-- 3. device_parallel_state
DROP TABLE IF EXISTS device_parallel_state;

-- 2. device_alarm_snapshots
DROP TABLE IF EXISTS device_alarm_snapshots;

-- 1. device_alarm_events (hypertable) — remove policies then drop
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
          AND hypertable_name = 'device_alarm_events'
    ) THEN
        PERFORM remove_compression_policy('device_alarm_events', if_exists => TRUE);
    END IF;

    IF EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
          AND hypertable_name = 'device_alarm_events'
    ) THEN
        PERFORM remove_retention_policy('device_alarm_events', if_exists => TRUE);
    END IF;
END $$;

DROP TABLE IF EXISTS device_alarm_events;
