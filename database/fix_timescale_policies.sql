-- 修复 1min 聚合策略
SELECT add_continuous_aggregate_policy('device_telemetry_1min',
    start_offset    => INTERVAL '10 minutes',
    end_offset      => INTERVAL '2 minutes',
    schedule_interval => INTERVAL '5 minutes',
    if_not_exists   => TRUE
);

-- 修复 1hour 聚合策略
SELECT add_continuous_aggregate_policy('device_telemetry_1hour',
    start_offset    => INTERVAL '10 hours',
    end_offset      => INTERVAL '2 hours',
    schedule_interval => INTERVAL '3 hours',
    if_not_exists   => TRUE
);

-- 修复 1day 聚合策略
SELECT add_continuous_aggregate_policy('device_telemetry_1day',
    start_offset    => INTERVAL '10 days',
    end_offset      => INTERVAL '2 days',
    schedule_interval => INTERVAL '3 days',
    if_not_exists   => TRUE
);
