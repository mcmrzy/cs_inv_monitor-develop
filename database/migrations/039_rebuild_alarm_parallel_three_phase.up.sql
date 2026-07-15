-- 039: Rebuild the protocol tables introduced by migration 038.
--
-- The five 038 tables are intentionally disposable in this migration. Core
-- business tables (users/devices/stations/model registry/OTA/work orders and
-- telemetry) are never truncated or dropped.

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Keep the existing alarms data and add the compatibility columns used by
--    the current API write path. alarm_level/fault_message remain canonical.
-- ---------------------------------------------------------------------------

ALTER TABLE alarms
    ADD COLUMN IF NOT EXISTS type VARCHAR(32),
    ADD COLUMN IF NOT EXISTS level SMALLINT,
    ADD COLUMN IF NOT EXISTS message TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE alarms
SET type = COALESCE(type, 'device_fault'),
    level = COALESCE(level, alarm_level),
    message = COALESCE(message, fault_message),
    updated_at = COALESCE(updated_at, created_at, NOW())
WHERE type IS NULL OR level IS NULL OR message IS NULL OR updated_at IS NULL;

ALTER TABLE alarms
    ALTER COLUMN type SET DEFAULT 'device_fault',
    ALTER COLUMN type SET NOT NULL,
    ALTER COLUMN level SET NOT NULL,
    ALTER COLUMN message SET NOT NULL,
    ALTER COLUMN updated_at SET DEFAULT NOW(),
    ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM alarms WHERE status NOT IN (0, 1, 2)) THEN
        RAISE EXCEPTION 'alarms contains status outside the handling-state enum 0/1/2';
    END IF;
    IF EXISTS (SELECT 1 FROM alarms WHERE event_state NOT IN ('active', 'recovered')) THEN
        RAISE EXCEPTION 'alarms contains an invalid lifecycle event_state';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION normalize_alarms_compat_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status NOT IN (0, 1, 2) THEN
        RAISE EXCEPTION 'alarms.status must be 0 (unhandled), 1 (handled), or 2 (ignored)'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.event_state NOT IN ('active', 'recovered') THEN
        RAISE EXCEPTION 'alarms.event_state must be active or recovered'
            USING ERRCODE = '23514';
    END IF;
    NEW.alarm_level := COALESCE(NEW.alarm_level, NEW.level);
    NEW.level := NEW.alarm_level;
    NEW.fault_message := COALESCE(NULLIF(NEW.fault_message, ''), NEW.message, '');
    NEW.message := NEW.fault_message;
    NEW.type := COALESCE(NULLIF(NEW.type, ''), 'device_fault');
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_alarms_compat_columns ON alarms;
CREATE TRIGGER trg_alarms_compat_columns
BEFORE INSERT OR UPDATE ON alarms
FOR EACH ROW EXECUTE FUNCTION normalize_alarms_compat_columns();

-- Migration 036 preserved alarms_old, whose indexes retained the public
-- idx_alarms_* names. Preserve those backup indexes under explicit *_old_*
-- names before restoring the canonical names to the live hypertable.
DO $$
DECLARE
    item RECORD;
    owner_table TEXT;
BEGIN
    FOR item IN
        SELECT * FROM (VALUES
            ('idx_alarms_device',   'idx_alarms_old_device'),
            ('idx_alarms_station',  'idx_alarms_old_station'),
            ('idx_alarms_user',     'idx_alarms_old_user'),
            ('idx_alarms_status',   'idx_alarms_old_status'),
            ('idx_alarms_time',     'idx_alarms_old_time'),
            ('idx_alarms_device_time', 'idx_alarms_old_device_time'),
            ('idx_alarms_pending',  'idx_alarms_old_pending'),
            ('idx_alarms_v1_active','idx_alarms_old_v1_active')
        ) AS names(current_name, backup_name)
    LOOP
        SELECT tbl.relname INTO owner_table
        FROM pg_class idx
        JOIN pg_index pi ON pi.indexrelid = idx.oid
        JOIN pg_class tbl ON tbl.oid = pi.indrelid
        JOIN pg_namespace ns ON ns.oid = idx.relnamespace
        WHERE ns.nspname = 'public' AND idx.relname = item.current_name;

        IF owner_table = 'alarms_old' THEN
            IF to_regclass('public.' || item.backup_name) IS NOT NULL THEN
                RAISE EXCEPTION 'cannot preserve index %: target % already exists', item.current_name, item.backup_name;
            END IF;
            EXECUTE format('ALTER INDEX public.%I RENAME TO %I', item.current_name, item.backup_name);
        END IF;
        owner_table := NULL;
    END LOOP;
END $$;

CREATE INDEX IF NOT EXISTS idx_alarms_device ON alarms(device_sn);
CREATE INDEX IF NOT EXISTS idx_alarms_station ON alarms(station_id);
CREATE INDEX IF NOT EXISTS idx_alarms_user ON alarms(user_id);
CREATE INDEX IF NOT EXISTS idx_alarms_status ON alarms(status);
CREATE INDEX IF NOT EXISTS idx_alarms_time ON alarms(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_alarms_v1_active
    ON alarms(device_sn, alarm_source, fault_code)
    WHERE event_state = 'active';

-- ---------------------------------------------------------------------------
-- 2. Drop only the five disposable 038 tables, then recreate one contract.
--    Dropping a Timescale hypertable also removes its background policies.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS device_alarm_snapshots CASCADE;
DROP TABLE IF EXISTS device_parallel_events CASCADE;
DROP TABLE IF EXISTS device_parallel_state CASCADE;
DROP TABLE IF EXISTS device_alarm_events CASCADE;
DROP TABLE IF EXISTS device_three_phase_3min CASCADE;

-- ---------------------------------------------------------------------------
-- 3. Alarm event log: ordinary PostgreSQL table. The compatibility trigger
--    derives the canonical event_time/t/raw/hash fields for legacy writers.
-- ---------------------------------------------------------------------------

CREATE TABLE device_alarm_events (
    id            BIGSERIAL PRIMARY KEY,
    device_sn     VARCHAR(50) NOT NULL,
    station_id    BIGINT,
    source        SMALLINT NOT NULL CHECK (source BETWEEN 0 AND 3),
    code          VARCHAR(64) NOT NULL CHECK (code <> ''),
    level         SMALLINT NOT NULL CHECK (level BETWEEN 0 AND 3),
    state         VARCHAR(16) NOT NULL CHECK (state IN ('active', 'recovered')),
    topic         VARCHAR(64) NOT NULL DEFAULT 'alarm' CHECK (topic = 'alarm'),
    event_time    TIMESTAMPTZ NOT NULL,
    t             BIGINT NOT NULL,
    active_at     TIMESTAMPTZ,
    recovered_at  TIMESTAMPTZ,
    raw_data      JSONB,
    raw_envelope  JSONB NOT NULL DEFAULT '{}'::jsonb
                  CHECK (jsonb_typeof(raw_envelope) = 'object'),
    data_hash     VARCHAR(64) NOT NULL
                  CHECK (data_hash ~ '^[0-9a-f]{64}$'),
    received_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_device_alarm_events_lifecycle
        UNIQUE (device_sn, source, code, state, event_time)
);

CREATE INDEX idx_alarm_events_device_time
    ON device_alarm_events(device_sn, event_time DESC);
CREATE INDEX idx_alarm_events_active
    ON device_alarm_events(device_sn, source, code, event_time DESC)
    WHERE state = 'active';
CREATE INDEX idx_alarm_events_station_time
    ON device_alarm_events(station_id, event_time DESC)
    WHERE station_id IS NOT NULL;

CREATE OR REPLACE FUNCTION normalize_device_alarm_event()
RETURNS TRIGGER AS $$
BEGIN
    NEW.created_at := COALESCE(NEW.created_at, NOW());
    NEW.received_at := COALESCE(NEW.received_at, NOW());
    NEW.event_time := COALESCE(NEW.event_time, NEW.active_at, NEW.recovered_at, NEW.created_at);
    NEW.t := COALESCE(NEW.t, EXTRACT(EPOCH FROM NEW.event_time)::BIGINT);
    NEW.topic := COALESCE(NULLIF(NEW.topic, ''), 'alarm');

    IF NEW.raw_envelope IS NULL OR NEW.raw_envelope = '{}'::jsonb THEN
        NEW.raw_envelope := COALESCE(NEW.raw_data, '{}'::jsonb);
    END IF;
    NEW.raw_data := COALESCE(NEW.raw_data, NEW.raw_envelope);
    NEW.data_hash := COALESCE(
        NULLIF(NEW.data_hash, ''),
        encode(digest(convert_to(NEW.raw_envelope::text, 'UTF8'), 'sha256'), 'hex')
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalize_device_alarm_event
BEFORE INSERT OR UPDATE ON device_alarm_events
FOR EACH ROW EXECUTE FUNCTION normalize_device_alarm_event();

-- Alarm snapshots can now reference a stable, globally unique event id.
CREATE TABLE device_alarm_snapshots (
    id                   BIGSERIAL PRIMARY KEY,
    device_sn            VARCHAR(50) NOT NULL,
    alarm_event_id       BIGINT NOT NULL
                         REFERENCES device_alarm_events(id) ON DELETE CASCADE,
    snapshot_type        VARCHAR(16) NOT NULL
                         CHECK (snapshot_type IN ('before', 'after')),
    ac_voltage           DOUBLE PRECISION,
    ac_current           DOUBLE PRECISION,
    ac_active_power      DOUBLE PRECISION,
    ac_frequency         DOUBLE PRECISION,
    battery_soc          DOUBLE PRECISION,
    battery_voltage      DOUBLE PRECISION,
    battery_current      DOUBLE PRECISION,
    battery_temperature  DOUBLE PRECISION,
    internal_temperature DOUBLE PRECISION,
    dc_bus_voltage       DOUBLE PRECISION,
    work_state           SMALLINT,
    fault_code           BIGINT,
    raw_snapshot         JSONB NOT NULL DEFAULT '{}'::jsonb,
    captured_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_alarm_snapshot_event_type
        UNIQUE (alarm_event_id, snapshot_type)
);

CREATE INDEX idx_alarm_snapshots_device_time
    ON device_alarm_snapshots(device_sn, captured_at DESC);

-- ---------------------------------------------------------------------------
-- 4. Parallel current state and immutable topology events.
-- ---------------------------------------------------------------------------

CREATE TABLE device_parallel_state (
    station_id          BIGINT PRIMARY KEY REFERENCES stations(id) ON DELETE CASCADE,
    master_sn           VARCHAR(50) NOT NULL,
    enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    mode                VARCHAR(20) NOT NULL DEFAULT 'standalone'
                        CHECK (mode IN ('standalone', 'single_phase', 'three_phase')),
    count               SMALLINT NOT NULL DEFAULT 0 CHECK (count BETWEEN 0 AND 8),
    total_rated_power   BIGINT NOT NULL DEFAULT 0 CHECK (total_rated_power >= 0),
    total_active_power  DOUBLE PRECISION NOT NULL DEFAULT 0
                        CHECK (total_active_power BETWEEN 0 AND 1000000000),
    sync_state          VARCHAR(20) NOT NULL DEFAULT 'idle'
                        CHECK (sync_state IN ('idle', 'synced', 'syncing', 'fault')),
    machines            JSONB NOT NULL DEFAULT '[]'::jsonb
                        CHECK (jsonb_typeof(machines) = 'array'),
    topic               VARCHAR(64) NOT NULL DEFAULT 'parallel' CHECK (topic = 'parallel'),
    event_time          TIMESTAMPTZ NOT NULL,
    t                   BIGINT NOT NULL,
    raw_envelope        JSONB NOT NULL DEFAULT '{}'::jsonb
                        CHECK (jsonb_typeof(raw_envelope) = 'object'),
    data_hash           VARCHAR(64) NOT NULL
                        CHECK (data_hash ~ '^[0-9a-f]{64}$'),
    reported_at         TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_parallel_state_master ON device_parallel_state(master_sn);
CREATE INDEX idx_parallel_state_updated ON device_parallel_state(updated_at DESC);

CREATE OR REPLACE FUNCTION normalize_device_parallel_state()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.reported_at IS NULL OR NEW.reported_at < TIMESTAMPTZ '2000-01-01 00:00:00+00' THEN
        NEW.reported_at := COALESCE(NEW.event_time, NOW());
    END IF;
    NEW.event_time := COALESCE(NEW.event_time, NEW.reported_at);
    NEW.t := COALESCE(NEW.t, EXTRACT(EPOCH FROM NEW.event_time)::BIGINT);
    NEW.topic := COALESCE(NULLIF(NEW.topic, ''), 'parallel');
    NEW.created_at := COALESCE(NEW.created_at, NOW());
    NEW.updated_at := NOW();

    IF NEW.raw_envelope IS NULL OR NEW.raw_envelope = '{}'::jsonb THEN
        NEW.raw_envelope := jsonb_build_object(
            'v', 1,
            't', NEW.t,
            'data', jsonb_build_object(
                'enabled', NEW.enabled,
                'mode', NEW.mode,
                'count', NEW.count,
                'total_rated_power', NEW.total_rated_power,
                'total_active_power', NEW.total_active_power,
                'sync_state', NEW.sync_state,
                'machines', NEW.machines
            )
        );
    END IF;
    NEW.data_hash := COALESCE(
        NULLIF(NEW.data_hash, ''),
        encode(digest(convert_to(NEW.raw_envelope::text, 'UTF8'), 'sha256'), 'hex')
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalize_device_parallel_state
BEFORE INSERT OR UPDATE ON device_parallel_state
FOR EACH ROW EXECUTE FUNCTION normalize_device_parallel_state();

CREATE TABLE device_parallel_events (
    id            BIGSERIAL PRIMARY KEY,
    station_id    BIGINT NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    master_sn     VARCHAR(50) NOT NULL,
    event_type    VARCHAR(32) NOT NULL CHECK (event_type IN (
                      'parallel_created', 'topology_changed', 'master_switched',
                      'member_added', 'member_removed', 'sync_state_changed', 'disabled',
                      'out_of_order'
                  )),
    old_state     JSONB,
    new_state     JSONB,
    topic         VARCHAR(64) NOT NULL DEFAULT 'parallel' CHECK (topic = 'parallel'),
    event_time    TIMESTAMPTZ NOT NULL,
    t             BIGINT NOT NULL,
    raw_envelope  JSONB NOT NULL DEFAULT '{}'::jsonb
                  CHECK (jsonb_typeof(raw_envelope) = 'object'),
    data_hash     VARCHAR(64) NOT NULL
                  CHECK (data_hash ~ '^[0-9a-f]{64}$'),
    occurred_at   TIMESTAMPTZ NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_device_parallel_events_message
        UNIQUE (master_sn, event_time, data_hash)
);

CREATE INDEX idx_parallel_events_station_time
    ON device_parallel_events(station_id, event_time DESC);
CREATE INDEX idx_parallel_events_master_time
    ON device_parallel_events(master_sn, event_time DESC);

CREATE OR REPLACE FUNCTION normalize_device_parallel_event()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.occurred_at IS NULL OR NEW.occurred_at < TIMESTAMPTZ '2000-01-01 00:00:00+00' THEN
        NEW.occurred_at := COALESCE(NEW.event_time, NOW());
    END IF;
    NEW.event_time := COALESCE(NEW.event_time, NEW.occurred_at);
    NEW.t := COALESCE(NEW.t, EXTRACT(EPOCH FROM NEW.event_time)::BIGINT);
    NEW.topic := COALESCE(NULLIF(NEW.topic, ''), 'parallel');
    NEW.created_at := COALESCE(NEW.created_at, NOW());

    IF NEW.raw_envelope IS NULL OR NEW.raw_envelope = '{}'::jsonb THEN
        NEW.raw_envelope := jsonb_build_object(
            'v', 1,
            't', NEW.t,
            'data', jsonb_build_object(
                'event_type', NEW.event_type,
                'old_state', NEW.old_state,
                'new_state', NEW.new_state
            )
        );
    END IF;
    NEW.data_hash := COALESCE(
        NULLIF(NEW.data_hash, ''),
        encode(digest(convert_to(NEW.raw_envelope::text, 'UTF8'), 'sha256'), 'hex')
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalize_device_parallel_event
BEFORE INSERT OR UPDATE ON device_parallel_events
FOR EACH ROW EXECUTE FUNCTION normalize_device_parallel_event();

-- ---------------------------------------------------------------------------
-- 5. Three-phase 3-minute fact hypertable.
-- ---------------------------------------------------------------------------

CREATE TABLE device_three_phase_3min (
    device_sn           VARCHAR(50) NOT NULL,
    topic               VARCHAR(64) NOT NULL DEFAULT 'three_phase' CHECK (topic = 'three_phase'),
    event_time          TIMESTAMPTZ NOT NULL,
    t                   BIGINT NOT NULL,
    received_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_hash           VARCHAR(64) NOT NULL
                        CHECK (data_hash ~ '^[0-9a-f]{64}$'),
    raw_envelope        JSONB NOT NULL DEFAULT '{}'::jsonb
                        CHECK (jsonb_typeof(raw_envelope) = 'object'),
    voltage_l1          DOUBLE PRECISION NOT NULL CHECK (voltage_l1 BETWEEN 0 AND 100000),
    voltage_l2          DOUBLE PRECISION NOT NULL CHECK (voltage_l2 BETWEEN 0 AND 100000),
    voltage_l3          DOUBLE PRECISION NOT NULL CHECK (voltage_l3 BETWEEN 0 AND 100000),
    current_l1          DOUBLE PRECISION NOT NULL CHECK (current_l1 BETWEEN 0 AND 100000),
    current_l2          DOUBLE PRECISION NOT NULL CHECK (current_l2 BETWEEN 0 AND 100000),
    current_l3          DOUBLE PRECISION NOT NULL CHECK (current_l3 BETWEEN 0 AND 100000),
    active_power_l1     DOUBLE PRECISION NOT NULL CHECK (active_power_l1 BETWEEN 0 AND 1000000000),
    active_power_l2     DOUBLE PRECISION NOT NULL CHECK (active_power_l2 BETWEEN 0 AND 1000000000),
    active_power_l3     DOUBLE PRECISION NOT NULL CHECK (active_power_l3 BETWEEN 0 AND 1000000000),
    total_active_power  DOUBLE PRECISION NOT NULL CHECK (total_active_power BETWEEN 0 AND 1000000000),
    line_voltage_l1l2   DOUBLE PRECISION NOT NULL CHECK (line_voltage_l1l2 BETWEEN 0 AND 100000),
    line_voltage_l2l3   DOUBLE PRECISION NOT NULL CHECK (line_voltage_l2l3 BETWEEN 0 AND 100000),
    line_voltage_l3l1   DOUBLE PRECISION NOT NULL CHECK (line_voltage_l3l1 BETWEEN 0 AND 100000),
    frequency           DOUBLE PRECISION NOT NULL CHECK (frequency BETWEEN 0 AND 1000),
    voltage_unbalance   DOUBLE PRECISION NOT NULL CHECK (voltage_unbalance BETWEEN 0 AND 100),
    current_unbalance   DOUBLE PRECISION NOT NULL CHECK (current_unbalance BETWEEN 0 AND 100),
    quality_flags       INTEGER NOT NULL DEFAULT 0 CHECK (quality_flags >= 0)
);

CREATE UNIQUE INDEX uq_three_phase_message
    ON device_three_phase_3min(device_sn, event_time, data_hash);
CREATE INDEX idx_three_phase_device_time
    ON device_three_phase_3min(device_sn, event_time DESC);

CREATE OR REPLACE FUNCTION normalize_device_three_phase_sample()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.event_time IS NULL OR NEW.event_time < TIMESTAMPTZ '2000-01-01 00:00:00+00' THEN
        NEW.event_time := NOW();
        NEW.quality_flags := NEW.quality_flags | 4;
    END IF;
    NEW.t := COALESCE(NEW.t, EXTRACT(EPOCH FROM NEW.event_time)::BIGINT);
    NEW.topic := COALESCE(NULLIF(NEW.topic, ''), 'three_phase');
    NEW.received_at := COALESCE(NEW.received_at, NOW());

    IF NEW.raw_envelope IS NULL OR NEW.raw_envelope = '{}'::jsonb THEN
        NEW.raw_envelope := jsonb_build_object(
            'v', 1,
            't', NEW.t,
            'data', jsonb_build_object(
                'voltage', jsonb_build_array(NEW.voltage_l1, NEW.voltage_l2, NEW.voltage_l3),
                'current', jsonb_build_array(NEW.current_l1, NEW.current_l2, NEW.current_l3),
                'active_power', jsonb_build_array(NEW.active_power_l1, NEW.active_power_l2, NEW.active_power_l3),
                'total_active_power', NEW.total_active_power,
                'line_voltage', jsonb_build_array(NEW.line_voltage_l1l2, NEW.line_voltage_l2l3, NEW.line_voltage_l3l1),
                'frequency', NEW.frequency,
                'voltage_unbalance', NEW.voltage_unbalance,
                'current_unbalance', NEW.current_unbalance
            )
        );
    END IF;
    NEW.data_hash := COALESCE(
        NULLIF(NEW.data_hash, ''),
        encode(digest(convert_to(NEW.raw_envelope::text, 'UTF8'), 'sha256'), 'hex')
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalize_device_three_phase_sample
BEFORE INSERT OR UPDATE ON device_three_phase_3min
FOR EACH ROW EXECUTE FUNCTION normalize_device_three_phase_sample();

SELECT create_hypertable(
    'device_three_phase_3min',
    'event_time',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE
);

ALTER TABLE device_three_phase_3min SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_sn',
    timescaledb.compress_orderby = 'event_time DESC'
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
          AND hypertable_schema = 'public'
          AND hypertable_name = 'device_three_phase_3min'
    ) THEN
        PERFORM add_compression_policy('device_three_phase_3min', INTERVAL '3 days');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
          AND hypertable_schema = 'public'
          AND hypertable_name = 'device_three_phase_3min'
    ) THEN
        PERFORM add_retention_policy('device_three_phase_3min', INTERVAL '90 days');
    END IF;
END $$;

COMMENT ON TABLE device_alarm_events IS 'Alarm active/recovered events; ordinary PostgreSQL table rebuilt by migration 039';
COMMENT ON TABLE device_alarm_snapshots IS 'Before/after telemetry snapshots with FK to device_alarm_events';
COMMENT ON TABLE device_parallel_state IS 'Current station-level parallel topology';
COMMENT ON TABLE device_parallel_events IS 'Immutable parallel topology changes';
COMMENT ON TABLE device_three_phase_3min IS 'Three-phase 3-minute TimescaleDB facts';
