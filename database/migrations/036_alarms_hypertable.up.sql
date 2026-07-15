-- =====================================================
-- Migration 036: Convert alarms table to TimescaleDB hypertable
-- =====================================================
-- Converts the alarms table from a regular PostgreSQL table to a
-- TimescaleDB hypertable partitioned on occurred_at.
--
-- Prerequisites:
--   - TimescaleDB extension must be installed (CREATE EXTENSION IF NOT EXISTS timescaledb)
--   - Migration 027 (alarm_v1_lifecycle) must have been applied
--
-- Current alarms table structure (schema.sql + migration 027):
--   id           BIGSERIAL PRIMARY KEY
--   device_sn    VARCHAR(50) NOT NULL
--   station_id   BIGINT
--   user_id      BIGINT NOT NULL
--   alarm_level  SMALLINT NOT NULL
--   fault_code   VARCHAR(20) NOT NULL
--   fault_message VARCHAR(200) NOT NULL
--   fault_detail TEXT
--   status       SMALLINT NOT NULL DEFAULT 0
--   occurred_at  TIMESTAMPTZ NOT NULL        (already TIMESTAMPTZ — no type change needed)
--   recovered_at TIMESTAMPTZ
--   handled_at   TIMESTAMPTZ
--   handled_by   BIGINT
--   created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
--   alarm_source SMALLINT NOT NULL DEFAULT 0       (migration 027)
--   event_state  VARCHAR(16) NOT NULL DEFAULT 'active'  (migration 027)
--
-- Time columns are already TIMESTAMPTZ — no TIMESTAMP -> TIMESTAMPTZ
-- conversion is needed.
--
-- No foreign keys reference the alarms table (verified via grep).
--
-- Hypertable configuration:
--   - Partitioning column: occurred_at
--   - Chunk time interval: 7 days
--   - Compression: enabled after 30 days, segmentby device_sn
--   - Retention: retain 1 year of data
-- =====================================================

-- Ensure TimescaleDB extension is available
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- =====================================================
-- Step 1: Create new table with same structure (LIKE INCLUDING ALL)
-- =====================================================
-- Use a transaction-safe approach: create alarms_new, migrate data,
-- then swap table names.

CREATE TABLE IF NOT EXISTS alarms_new (LIKE alarms INCLUDING ALL);

-- =====================================================
-- Step 2: Fix unique constraints for hypertable compatibility
-- =====================================================
-- TimescaleDB requires the partitioning column (occurred_at) to be
-- included in all unique indexes and primary keys. The original
-- primary key on (id) alone is incompatible.
-- LIKE ... INCLUDING INDEXES copies the PK as a unique index — we
-- must drop it and create a composite PK.

DO $$
DECLARE
    r RECORD;
BEGIN
    -- First drop any unique constraints on alarms_new that do NOT include occurred_at
    FOR r IN
        SELECT conname
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        WHERE cl.relname = 'alarms_new'
          AND c.contype IN ('u', 'p')
          AND NOT EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.conrelid
                AND a.attnum = ANY(c.conkey)
                AND a.attname = 'occurred_at'
          )
    LOOP
        EXECUTE format('ALTER TABLE alarms_new DROP CONSTRAINT IF EXISTS %I', r.conname);
        RAISE NOTICE 'Dropped constraint % for hypertable compatibility', r.conname;
    END LOOP;

    -- Then drop any remaining unique index on alarms_new that does NOT include occurred_at
    FOR r IN
        SELECT i.indexname
        FROM pg_indexes i
        WHERE i.tablename = 'alarms_new'
          AND i.indexdef ILIKE '%UNIQUE%'
          AND i.indexdef NOT ILIKE '%occurred_at%'
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.indexname);
        RAISE NOTICE 'Dropped unique index % for hypertable compatibility', r.indexname;
    END LOOP;
END $$;

-- Add composite primary key including occurred_at
ALTER TABLE alarms_new DROP CONSTRAINT IF EXISTS alarms_new_pkey;
ALTER TABLE alarms_new ADD PRIMARY KEY (id, occurred_at);

-- =====================================================
-- Step 3: Convert to hypertable (chunk_time_interval = 7 days)
-- =====================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.hypertables
        WHERE hypertable_name = 'alarms_new'
    ) THEN
        PERFORM create_hypertable(
            'alarms_new',
            'occurred_at',
            chunk_time_interval => INTERVAL '7 days',
            if_not_exists => TRUE
        );
        RAISE NOTICE 'Created hypertable alarms_new on occurred_at (7-day chunks)';
    ELSE
        RAISE NOTICE 'Hypertable alarms_new already exists';
    END IF;
END $$;

-- =====================================================
-- Step 4: Migrate data from alarms to alarms_new
-- =====================================================
INSERT INTO alarms_new
SELECT * FROM alarms
ON CONFLICT (id, occurred_at) DO NOTHING;

-- =====================================================
-- Step 5: Configure compression strategy
-- =====================================================
-- Compress chunks older than 30 days, segmented by device_sn
ALTER TABLE alarms_new SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_sn',
    timescaledb.compress_orderby = 'occurred_at DESC'
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
          AND hypertable_name = 'alarms_new'
    ) THEN
        PERFORM add_compression_policy('alarms_new', INTERVAL '30 days');
        RAISE NOTICE 'Added compression policy: compress after 30 days';
    ELSE
        RAISE NOTICE 'Compression policy already exists for alarms_new';
    END IF;
END $$;

-- =====================================================
-- Step 6: Configure retention policy (retain 1 year)
-- =====================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
          AND hypertable_name = 'alarms_new'
    ) THEN
        PERFORM add_retention_policy('alarms_new', INTERVAL '1 year');
        RAISE NOTICE 'Added retention policy: retain 1 year';
    ELSE
        RAISE NOTICE 'Retention policy already exists for alarms_new';
    END IF;
END $$;

-- =====================================================
-- Step 7: Rename old table and swap
-- =====================================================
-- Preserve the original table as alarms_old for rollback safety.
-- The original sequence (alarms_id_seq) remains owned by alarms_old;
-- we reassign ownership to the new alarms table.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'alarms' AND table_type = 'BASE TABLE') THEN
        ALTER TABLE alarms RENAME TO alarms_old;
        RAISE NOTICE 'Renamed alarms -> alarms_old (backup preserved)';
    END IF;
END $$;

ALTER TABLE alarms_new RENAME TO alarms;

-- Recreate indexes with standard names on the renamed table
-- (indexes copied by INCLUDING ALL had alarms_new_ prefixed names)
CREATE INDEX IF NOT EXISTS idx_alarms_device ON alarms(device_sn);
CREATE INDEX IF NOT EXISTS idx_alarms_station ON alarms(station_id);
CREATE INDEX IF NOT EXISTS idx_alarms_user ON alarms(user_id);
CREATE INDEX IF NOT EXISTS idx_alarms_status ON alarms(status);
CREATE INDEX IF NOT EXISTS idx_alarms_time ON alarms(occurred_at);
CREATE INDEX IF NOT EXISTS idx_alarms_v1_active
    ON alarms(device_sn, alarm_source, fault_code)
    WHERE status = 0;

-- Drop duplicate indexes that were copied with alarms_new_ prefix
DROP INDEX IF EXISTS alarms_new_device_sn_idx;
DROP INDEX IF EXISTS alarms_new_station_id_idx;
DROP INDEX IF EXISTS alarms_new_user_id_idx;
DROP INDEX IF EXISTS alarms_new_status_idx;
DROP INDEX IF EXISTS alarms_new_occurred_at_idx;
DROP INDEX IF EXISTS alarms_new_device_sn_alarm_source_fault_code_idx;
-- Baseline schema may already contain migration-002's composite indexes.
-- LIKE INCLUDING ALL copies them under alarms_new_* names; remove those
-- copies so migration 039/044 can restore the canonical names without
-- retaining semantically duplicate indexes.
DROP INDEX IF EXISTS alarms_new_device_sn_created_at_idx;
DROP INDEX IF EXISTS alarms_new_status_created_at_idx;

-- Fix sequence ownership: alarms_id_seq was owned by alarms_old.id
-- Reassign to alarms.id so the new table controls the sequence
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_sequences WHERE sequencename = 'alarms_id_seq') THEN
        ALTER SEQUENCE alarms_id_seq OWNED BY alarms.id;
        RAISE NOTICE 'Reassigned alarms_id_seq ownership to alarms.id';
    END IF;
END $$;

-- Update applied_at marker
DO $$ BEGIN
    RAISE NOTICE 'Migration 036 complete: alarms is now a TimescaleDB hypertable';
END $$;
