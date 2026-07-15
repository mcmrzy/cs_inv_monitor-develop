-- 039 DOWN: Restore the migration-038 table shapes.
-- Data written to the five migration-039 tables is intentionally not copied
-- into the incompatible 038 layouts. Core business tables are preserved.

DROP TABLE IF EXISTS device_alarm_snapshots CASCADE;
DROP TABLE IF EXISTS device_parallel_events CASCADE;
DROP TABLE IF EXISTS device_parallel_state CASCADE;
DROP TABLE IF EXISTS device_alarm_events CASCADE;
DROP TABLE IF EXISTS device_three_phase_3min CASCADE;

DROP FUNCTION IF EXISTS normalize_device_alarm_event();
DROP FUNCTION IF EXISTS normalize_device_parallel_state();
DROP FUNCTION IF EXISTS normalize_device_parallel_event();
DROP FUNCTION IF EXISTS normalize_device_three_phase_sample();

DROP TRIGGER IF EXISTS trg_alarms_compat_columns ON alarms;
DROP FUNCTION IF EXISTS normalize_alarms_compat_columns();

ALTER TABLE alarms
    DROP COLUMN IF EXISTS updated_at,
    DROP COLUMN IF EXISTS message,
    DROP COLUMN IF EXISTS level,
    DROP COLUMN IF EXISTS type;

-- Restore migration 038's alarm event hypertable.
CREATE TABLE device_alarm_events (
    id            BIGSERIAL,
    device_sn     VARCHAR(50) NOT NULL,
    station_id    BIGINT,
    source        SMALLINT NOT NULL,
    code          INTEGER NOT NULL,
    level         SMALLINT NOT NULL,
    state         SMALLINT NOT NULL,
    active_at     TIMESTAMPTZ NOT NULL,
    recovered_at  TIMESTAMPTZ,
    raw_data      JSONB,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, active_at)
);

CREATE INDEX idx_alarm_events_device_time
    ON device_alarm_events(device_sn, active_at DESC);
CREATE INDEX idx_alarm_events_active
    ON device_alarm_events(device_sn, source, code) WHERE state = 1;

SELECT create_hypertable(
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

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_compression'
          AND hypertable_schema = 'public'
          AND hypertable_name = 'device_alarm_events'
    ) THEN
        PERFORM add_compression_policy('device_alarm_events', INTERVAL '30 days');
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name = 'policy_retention'
          AND hypertable_schema = 'public'
          AND hypertable_name = 'device_alarm_events'
    ) THEN
        PERFORM add_retention_policy('device_alarm_events', INTERVAL '1 year');
    END IF;
END $$;

CREATE TABLE device_alarm_snapshots (
    id                   BIGSERIAL PRIMARY KEY,
    device_sn            VARCHAR(50) NOT NULL,
    alarm_event_id       BIGINT,
    snapshot_type        VARCHAR(16) NOT NULL,
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
    raw_snapshot         JSONB NOT NULL,
    captured_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alarm_snapshots_event
    ON device_alarm_snapshots(alarm_event_id);
CREATE INDEX idx_alarm_snapshots_device_time
    ON device_alarm_snapshots(device_sn, captured_at DESC);

CREATE TABLE device_parallel_state (
    station_id          BIGINT PRIMARY KEY,
    master_sn           VARCHAR(50) NOT NULL,
    mode                VARCHAR(20) NOT NULL,
    count               SMALLINT NOT NULL DEFAULT 0,
    total_rated_power   INTEGER NOT NULL DEFAULT 0,
    total_active_power  DOUBLE PRECISION NOT NULL DEFAULT 0,
    sync_state          VARCHAR(20) NOT NULL DEFAULT 'idle',
    machines            JSONB NOT NULL DEFAULT '[]'::jsonb,
    reported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE device_parallel_events (
    id              BIGSERIAL PRIMARY KEY,
    station_id      BIGINT NOT NULL,
    master_sn       VARCHAR(50) NOT NULL,
    event_type      VARCHAR(32) NOT NULL,
    mode            VARCHAR(20),
    count           SMALLINT,
    sync_state      VARCHAR(20),
    machines_before JSONB,
    machines_after  JSONB,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_parallel_events_station_time
    ON device_parallel_events(station_id, occurred_at DESC);

CREATE TABLE device_three_phase_3min (
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

CREATE UNIQUE INDEX idx_three_phase_unique
    ON device_three_phase_3min(device_sn, event_time, data_hash);
CREATE INDEX idx_three_phase_device_time
    ON device_three_phase_3min(device_sn, event_time DESC);

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
