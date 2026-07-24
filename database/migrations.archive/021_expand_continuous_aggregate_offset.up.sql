-- 021_expand_continuous_aggregate_offset: 扩大连续聚合刷新窗口
-- 目的: 覆盖设备离线重连后补发的历史数据

BEGIN;

-- 旧连续聚合是可选组件；全新 schema 或尚未执行 migration_timescaledb.sql 时安全跳过。
DO $$
BEGIN
    IF to_regclass('device_telemetry_1min') IS NOT NULL THEN
        PERFORM remove_continuous_aggregate_policy('device_telemetry_1min', if_exists => TRUE);
        PERFORM add_continuous_aggregate_policy('device_telemetry_1min',
            start_offset => INTERVAL '10 minutes', end_offset => INTERVAL '1 minute',
            schedule_interval => INTERVAL '1 minute', if_not_exists => TRUE);
    END IF;
    IF to_regclass('device_telemetry_1hour') IS NOT NULL THEN
        PERFORM remove_continuous_aggregate_policy('device_telemetry_1hour', if_exists => TRUE);
        PERFORM add_continuous_aggregate_policy('device_telemetry_1hour',
            start_offset => INTERVAL '6 hours', end_offset => INTERVAL '1 hour',
            schedule_interval => INTERVAL '1 hour', if_not_exists => TRUE);
    END IF;
    IF to_regclass('device_telemetry_1day') IS NOT NULL THEN
        PERFORM remove_continuous_aggregate_policy('device_telemetry_1day', if_exists => TRUE);
        PERFORM add_continuous_aggregate_policy('device_telemetry_1day',
            start_offset => INTERVAL '4 days', end_offset => INTERVAL '1 day',
            schedule_interval => INTERVAL '1 day', if_not_exists => TRUE);
    END IF;
END $$;

INSERT INTO schema_migrations (version, name) VALUES (21, 'expand_continuous_aggregate_offset') ON CONFLICT DO NOTHING;

COMMIT;
