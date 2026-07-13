-- 021_expand_continuous_aggregate_offset: 扩大连续聚合刷新窗口
-- 目的: 覆盖设备离线重连后补发的历史数据
-- 1分钟聚合: start_offset 从 2 minutes 扩大到 10 minutes
SELECT remove_continuous_aggregate_policy('device_telemetry_1min', if_exists => TRUE);
SELECT add_continuous_aggregate_policy('device_telemetry_1min',
    start_offset    => INTERVAL '10 minutes',
    end_offset      => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute',
    if_not_exists   => TRUE
);

-- 1小时聚合: start_offset 从 2 hours 扩大到 6 hours
SELECT remove_continuous_aggregate_policy('device_telemetry_1hour', if_exists => TRUE);
SELECT add_continuous_aggregate_policy('device_telemetry_1hour',
    start_offset    => INTERVAL '6 hours',
    end_offset      => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists   => TRUE
);

-- 1天聚合: start_offset 从 2 days 扩大到 4 days
SELECT remove_continuous_aggregate_policy('device_telemetry_1day', if_exists => TRUE);
SELECT add_continuous_aggregate_policy('device_telemetry_1day',
    start_offset    => INTERVAL '4 days',
    end_offset      => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists   => TRUE
);
