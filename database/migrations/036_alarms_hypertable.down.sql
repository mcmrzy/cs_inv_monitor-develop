-- =====================================================
-- Migration 036 (DOWN): Revert alarms hypertable to regular table
-- =====================================================
-- Reverses the hypertable conversion by:
--   1. Removing TimescaleDB compression and retention policies
--   2. Renaming the hypertable (alarms) to alarms_hypertable_bak
--   3. Restoring the original pre-migration table from alarms_old
--   4. If alarms_old is unavailable, recreate the original structure
-- =====================================================

-- Step 1: Remove compression and retention policies from current alarms table
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
          AND hypertable_name = 'alarms'
    ) THEN
        PERFORM remove_compression_policy('alarms', if_exists => TRUE);
        RAISE NOTICE 'Removed compression policy from alarms';
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
          AND hypertable_name = 'alarms'
    ) THEN
        PERFORM remove_retention_policy('alarms', if_exists => TRUE);
        RAISE NOTICE 'Removed retention policy from alarms';
    END IF;
END $$;

-- Step 2: Rename current alarms (hypertable) to alarms_hypertable_bak
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'alarms') THEN
        ALTER TABLE alarms RENAME TO alarms_hypertable_bak;
        RAISE NOTICE 'Renamed alarms (hypertable) -> alarms_hypertable_bak';
    END IF;
END $$;

-- Step 3: Restore original table from alarms_old backup
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'alarms_old') THEN
        ALTER TABLE alarms_old RENAME TO alarms;
        -- Fix sequence ownership back to alarms.id
        IF EXISTS (SELECT 1 FROM pg_sequences WHERE sequencename = 'alarms_id_seq') THEN
            ALTER SEQUENCE alarms_id_seq OWNED BY alarms.id;
        END IF;
        RAISE NOTICE 'Restored alarms from alarms_old backup';
    ELSE
        RAISE NOTICE 'alarms_old not found — recreating original table structure';
    END IF;
END $$;

-- Step 4: If alarms table does not exist (no backup was available),
--         recreate the original structure with original indexes
CREATE TABLE IF NOT EXISTS alarms (
    id              BIGSERIAL PRIMARY KEY,
    device_sn       VARCHAR(50) NOT NULL,
    station_id      BIGINT,
    user_id         BIGINT NOT NULL,
    alarm_level     SMALLINT NOT NULL,
    fault_code      VARCHAR(20) NOT NULL,
    fault_message   VARCHAR(200) NOT NULL,
    fault_detail    TEXT,
    status          SMALLINT NOT NULL DEFAULT 0,
    occurred_at     TIMESTAMPTZ NOT NULL,
    recovered_at    TIMESTAMPTZ,
    handled_at      TIMESTAMPTZ,
    handled_by      BIGINT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    alarm_source    SMALLINT NOT NULL DEFAULT 0,
    event_state     VARCHAR(16) NOT NULL DEFAULT 'active'
);

CREATE INDEX IF NOT EXISTS idx_alarms_device ON alarms(device_sn);
CREATE INDEX IF NOT EXISTS idx_alarms_station ON alarms(station_id);
CREATE INDEX IF NOT EXISTS idx_alarms_user ON alarms(user_id);
CREATE INDEX IF NOT EXISTS idx_alarms_status ON alarms(status);
CREATE INDEX IF NOT EXISTS idx_alarms_time ON alarms(occurred_at);
CREATE INDEX IF NOT EXISTS idx_alarms_v1_active
    ON alarms(device_sn, alarm_source, fault_code)
    WHERE status = 0;

RAISE NOTICE 'Migration 036 down complete: alarms restored as regular table';
