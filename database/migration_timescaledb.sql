-- ============================================
-- TimescaleDB 时序数据库迁移脚本
-- 适用: PostgreSQL 15+ 已安装 timescaledb 扩展
-- 执行: psql -U postgres -d inv_mqtt -f migration_timescaledb.sql
-- ============================================

-- 4.1 启用 TimescaleDB 扩展
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 4.2 将 device_telemetry 转换为超表
-- 一行 SQL，零侵入
SELECT create_hypertable('device_telemetry', 'time', if_not_exists => TRUE);

-- 4.2 启用自动压缩策略（7 天前的数据自动压缩，压缩比约 10:1）
SELECT add_compression_policy('device_telemetry', INTERVAL '7 days', if_not_exists => TRUE);

-- 启用压缩时对常用字段进行分段压缩，提升查询性能
ALTER TABLE device_telemetry SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_sn',
    timescaledb.compress_orderby = 'time DESC'
);

-- 4.3 连续聚合：替代 device_minute_data（1 分钟降采样）
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1min
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 minute', time) AS bucket,
    device_sn,
    AVG(total_active_power) AS avg_active_power,
    MAX(total_active_power) AS max_active_power,
    AVG(internal_temperature) AS avg_temperature,
    MAX(internal_temperature) AS max_temperature,
    LAST(daily_energy, time) - FIRST(daily_energy, time) AS energy_delta,
    LAST(work_state, time) AS work_state,
    LAST(fault_code, time) AS fault_code
FROM device_telemetry
GROUP BY bucket, device_sn;

-- 1 分钟聚合刷新策略
SELECT add_continuous_aggregate_policy('device_telemetry_1min',
    start_offset    => INTERVAL '2 minutes',
    end_offset      => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute',
    if_not_exists   => TRUE
);

-- 连续聚合：替代 device_hour_data（1 小时降采样）
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1hour
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_sn,
    AVG(total_active_power) AS avg_active_power,
    MAX(total_active_power) AS max_active_power,
    AVG(internal_temperature) AS avg_temperature,
    MAX(internal_temperature) AS max_temperature,
    LAST(daily_energy, time) - FIRST(daily_energy, time) AS energy_delta,
    COUNT(*) AS sample_count,
    SUM(CASE WHEN total_active_power > 0 THEN 1 ELSE 0 END) AS run_minutes
FROM device_telemetry
GROUP BY bucket, device_sn;

SELECT add_continuous_aggregate_policy('device_telemetry_1hour',
    start_offset    => INTERVAL '2 hours',
    end_offset      => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists   => TRUE
);

-- 连续聚合：替代 device_day_data（1 天降采样）
CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_1day
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS bucket,
    device_sn,
    AVG(total_active_power) AS avg_active_power,
    MAX(total_active_power) AS max_active_power,
    AVG(internal_temperature) AS avg_temperature,
    LAST(daily_energy, time) - FIRST(daily_energy, time) AS daily_energy,
    SUM(CASE WHEN total_active_power > 0 THEN 1 ELSE 0 END) AS run_minutes
FROM device_telemetry
GROUP BY bucket, device_sn;

SELECT add_continuous_aggregate_policy('device_telemetry_1day',
    start_offset    => INTERVAL '2 days',
    end_offset      => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists   => TRUE
);

-- 4.4 PG 分职：设备元数据保留在 PG，时序查询走连续聚合视图
-- device_telemetry 超表自动分区管理，无需手动 TTL

-- 可选：按时间自动删除原始数据保留策略
-- SELECT add_retention_policy('device_telemetry', INTERVAL '90 days', if_not_exists => TRUE);
