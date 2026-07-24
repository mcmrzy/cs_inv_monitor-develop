-- =====================================================
-- Migration 038: Create 5 protocol-mandated missing tables
-- =====================================================
-- Creates:
--   1. device_alarm_events      — alarm event log (hypertable, 7-day chunks)
--   2. device_alarm_snapshots   — before/after alarm snapshots
--   3. device_parallel_state    — parallel topology current state
--   4. device_parallel_events   — parallel topology change history
--   5. device_three_phase_3min  — three-phase telemetry (hypertable, 7-day chunks)
--
-- Hypertable policies:
--   device_alarm_events:     compress 30d, retain 1 year
--   device_three_phase_3min: compress 3d,  retain 90 days
-- =====================================================

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- =====================================================
-- 1. device_alarm_events — alarm event log (hypertable)
-- =====================================================
-- Composite PK (id, active_at) required for TimescaleDB hypertable
-- compatibility: the partitioning column must be part of all unique
-- constraints.

CREATE TABLE IF NOT EXISTS device_alarm_events (
    id            BIGSERIAL,
    device_sn     VARCHAR(50) NOT NULL,
    station_id    BIGINT,
    source        SMALLINT NOT NULL,        -- 0 PCS, 1 BMS, 2 MPPT, 3 COMM
    code          INTEGER NOT NULL,         -- alarm code
    level         SMALLINT NOT NULL,        -- 1 warning, 2 fault
    state         SMALLINT NOT NULL,        -- 1 active, 0 recovered
    active_at     TIMESTAMPTZ NOT NULL,     -- alarm occurrence time
    recovered_at  TIMESTAMPTZ,              -- recovery time
    raw_data      JSONB,                    -- original alarm envelope
    received_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, active_at)
);

CREATE INDEX IF NOT EXISTS idx_alarm_events_device_time
    ON device_alarm_events(device_sn, active_at DESC);
CREATE INDEX IF NOT EXISTS idx_alarm_events_active
    ON device_alarm_events(device_sn, source, code) WHERE state = 1;

-- Convert to hypertable: 7-day chunks, compress after 30 days, retain 1 year
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable(
            'device_alarm_events',
            'active_at',
            chunk_time_interval => INTERVAL '7 days',
            if_not_exists => TRUE
        );

        ALTER TABLE device_alarm_events SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'active_at DESC'
        );

        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs
            WHERE proc_name = 'policy_compression'
              AND hypertable_name = 'device_alarm_events'
        ) THEN
            PERFORM add_compression_policy('device_alarm_events', INTERVAL '30 days');
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs
            WHERE proc_name = 'policy_retention'
              AND hypertable_name = 'device_alarm_events'
        ) THEN
            PERFORM add_retention_policy('device_alarm_events', INTERVAL '1 year');
        END IF;
    END IF;
END $$;

-- =====================================================
-- 2. device_alarm_snapshots — before/after alarm snapshots
-- =====================================================

CREATE TABLE IF NOT EXISTS device_alarm_snapshots (
    id                   BIGSERIAL PRIMARY KEY,
    device_sn            VARCHAR(50) NOT NULL,
    alarm_event_id       BIGINT,                  -- references device_alarm_events.id
    snapshot_type        VARCHAR(16) NOT NULL,    -- 'before' or 'after'
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
    fault_code           INTEGER,
    raw_snapshot         JSONB NOT NULL,          -- complete heartbeat snapshot
    captured_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alarm_snapshots_event
    ON device_alarm_snapshots(alarm_event_id);
CREATE INDEX IF NOT EXISTS idx_alarm_snapshots_device_time
    ON device_alarm_snapshots(device_sn, captured_at DESC);

-- =====================================================
-- 3. device_parallel_state — parallel topology current state
-- =====================================================

CREATE TABLE IF NOT EXISTS device_parallel_state (
    station_id          BIGINT PRIMARY KEY,
    master_sn           VARCHAR(50) NOT NULL,
    mode                VARCHAR(20) NOT NULL,      -- standalone/single_phase/three_phase
    count               SMALLINT NOT NULL DEFAULT 0,
    total_rated_power   INTEGER NOT NULL DEFAULT 0,
    total_active_power  DOUBLE PRECISION NOT NULL DEFAULT 0,
    sync_state          VARCHAR(20) NOT NULL DEFAULT 'idle',
    machines            JSONB NOT NULL DEFAULT '[]'::jsonb,
    reported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================
-- 4. device_parallel_events — parallel topology change history
-- =====================================================

CREATE TABLE IF NOT EXISTS device_parallel_events (
    id              BIGSERIAL PRIMARY KEY,
    station_id      BIGINT NOT NULL,
    master_sn       VARCHAR(50) NOT NULL,
    event_type      VARCHAR(32) NOT NULL,          -- topology_changed/master_switched/member_added/member_removed/sync_state_changed/disabled
    mode            VARCHAR(20),
    count           SMALLINT,
    sync_state      VARCHAR(20),
    machines_before JSONB,
    machines_after  JSONB,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_parallel_events_station_time
    ON device_parallel_events(station_id, occurred_at DESC);

-- =====================================================
-- 5. device_three_phase_3min — three-phase telemetry (hypertable)
-- =====================================================
-- Unique index (device_sn, event_time, data_hash) includes the partitioning
-- column event_time, satisfying TimescaleDB hypertable requirements.

CREATE TABLE IF NOT EXISTS device_three_phase_3min (
    device_sn           VARCHAR(50) NOT NULL,
    event_time          TIMESTAMPTZ NOT NULL,
    received_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_hash           VARCHAR(64) NOT NULL DEFAULT '',
    raw_envelope        JSONB NOT NULL DEFAULT '{}'::jsonb,
    voltage_l1          DOUBLE PRECISION,
    voltage_l2          DOUBLE PRECISION,
    voltage_l3          DOUBLE PRECISION,
    current_l1          DOUBLE PRECISION,
    current_l2          DOUBLE PRECISION,
    current_l3          DOUBLE PRECISION,
    active_power_l1     DOUBLE PRECISION,
    active_power_l2     DOUBLE PRECISION,
    active_power_l3     DOUBLE PRECISION,
    total_active_power  DOUBLE PRECISION,
    line_voltage_l1l2   DOUBLE PRECISION,
    line_voltage_l2l3   DOUBLE PRECISION,
    line_voltage_l3l1   DOUBLE PRECISION,
    frequency           DOUBLE PRECISION,
    voltage_unbalance   DOUBLE PRECISION,
    current_unbalance   DOUBLE PRECISION,
    quality_flags       INTEGER NOT NULL DEFAULT 0
);

-- Unique constraint for deduplication (includes partitioning column)
CREATE UNIQUE INDEX IF NOT EXISTS idx_three_phase_unique
    ON device_three_phase_3min(device_sn, event_time, data_hash);

CREATE INDEX IF NOT EXISTS idx_three_phase_device_time
    ON device_three_phase_3min(device_sn, event_time DESC);

-- Convert to hypertable: 7-day chunks, compress after 3 days, retain 90 days
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable(
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

        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs
            WHERE proc_name = 'policy_compression'
              AND hypertable_name = 'device_three_phase_3min'
        ) THEN
            PERFORM add_compression_policy('device_three_phase_3min', INTERVAL '3 days');
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs
            WHERE proc_name = 'policy_retention'
              AND hypertable_name = 'device_three_phase_3min'
        ) THEN
            PERFORM add_retention_policy('device_three_phase_3min', INTERVAL '90 days');
        END IF;
    END IF;
END $$;
