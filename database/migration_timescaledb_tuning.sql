-- ============================================================
-- TimescaleDB Hypertable + Retention + Compression
-- Run AFTER schema.sql on a PostgreSQL with TimescaleDB extension
-- ============================================================

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Convert device_telemetry to hypertable (if not already)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.hypertables
        WHERE hypertable_name = 'device_telemetry'
    ) THEN
        PERFORM create_hypertable('device_telemetry', 'time',
            chunk_time_interval => INTERVAL '1 day',
            if_not_exists => TRUE
        );
    END IF;
END $$;

-- Retention: auto-drop chunks older than 90 days
SELECT add_retention_policy('device_telemetry', INTERVAL '90 days', if_not_exists => TRUE);

-- Compression: compress chunks older than 7 days
ALTER TABLE device_telemetry SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_sn',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('device_telemetry', INTERVAL '7 days', if_not_exists => TRUE);

-- Indexes for compressed queries
CREATE INDEX IF NOT EXISTS idx_telemetry_sn_topic_time
    ON device_telemetry(device_sn, topic, time DESC);

-- Continuous aggregate: hourly device stats (optional, enables fast dashboard queries)
CREATE MATERIALIZED VIEW IF NOT EXISTS device_hourly_stats
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_sn,
    AVG(total_active_power) AS avg_power,
    MAX(total_active_power) AS max_power,
    LAST(daily_energy, time) AS latest_daily_energy,
    AVG(internal_temperature) AS avg_temp
FROM device_telemetry
WHERE topic = 'data/realtime'
GROUP BY bucket, device_sn
WITH NO DATA;

-- Refresh policy for continuous aggregate
SELECT add_continuous_aggregate_policy('device_hourly_stats',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);
