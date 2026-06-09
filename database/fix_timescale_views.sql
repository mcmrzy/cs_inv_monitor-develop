-- 连续聚合：1分钟降采样
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1min
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 minute', time) AS bucket,
    device_sn,
    model_code,
    AVG(total_active_power) AS avg_active_power,
    MAX(total_active_power) AS max_active_power,
    MIN(total_active_power) AS min_active_power,
    AVG(internal_temperature) AS avg_temperature,
    MAX(internal_temperature) AS max_temperature,
    LAST(daily_energy, time) - FIRST(daily_energy, time) AS energy_delta,
    LAST(work_state, time) AS work_state,
    LAST(fault_code, time) AS fault_code
FROM device_telemetry
GROUP BY bucket, device_sn, model_code
WITH NO DATA;

SELECT add_continuous_aggregate_policy('device_telemetry_1min',
    start_offset    => INTERVAL '2 minutes',
    end_offset      => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute',
    if_not_exists   => TRUE
);

-- 连续聚合：1小时降采样
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1hour
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_sn,
    model_code,
    AVG(total_active_power) AS avg_active_power,
    MAX(total_active_power) AS max_active_power,
    AVG(internal_temperature) AS avg_temperature,
    LAST(daily_energy, time) - FIRST(daily_energy, time) AS energy_delta,
    COUNT(*) AS sample_count,
    SUM(CASE WHEN total_active_power > 0 THEN 1 ELSE 0 END) AS run_minutes
FROM device_telemetry
GROUP BY bucket, device_sn, model_code
WITH NO DATA;

SELECT add_continuous_aggregate_policy('device_telemetry_1hour',
    start_offset    => INTERVAL '2 hours',
    end_offset      => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists   => TRUE
);

-- 连续聚合：1天降采样
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1day
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS bucket,
    device_sn,
    model_code,
    AVG(total_active_power) AS avg_active_power,
    MAX(total_active_power) AS max_active_power,
    SUM(CASE WHEN total_active_power > 0 THEN 1 ELSE 0 END) AS run_minutes,
    LAST(daily_energy, time) AS daily_energy
FROM device_telemetry
GROUP BY bucket, device_sn, model_code
WITH NO DATA;

SELECT add_continuous_aggregate_policy('device_telemetry_1day',
    start_offset    => INTERVAL '2 days',
    end_offset      => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists   => TRUE
);
