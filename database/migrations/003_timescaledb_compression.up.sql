-- 003_timescaledb_compression: TimescaleDB 压缩策略
-- 目标: 7天以上的 chunk 自动压缩，节省存储空间

BEGIN;

-- 启用 device_telemetry 压缩（如果超表存在）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_telemetry') THEN
        ALTER TABLE device_telemetry SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'time DESC'
        );

        PERFORM add_compression_policy('device_telemetry', INTERVAL '7 days');

        RAISE NOTICE 'Compression policy added for device_telemetry';
    ELSE
        RAISE NOTICE 'device_telemetry hypertable not found, skipping';
    END IF;
END $$;

-- 启用 device_alarms 压缩（如果超表存在）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_alarms') THEN
        ALTER TABLE device_alarms SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'created_at DESC'
        );

        PERFORM add_compression_policy('device_alarms', INTERVAL '30 days');

        RAISE NOTICE 'Compression policy added for device_alarms';
    ELSE
        RAISE NOTICE 'device_alarms hypertable not found, skipping';
    END IF;
END $$;

-- 启用 device_cmd_logs 压缩（如果超表存在）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_cmd_logs') THEN
        ALTER TABLE device_cmd_logs SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'sent_at DESC'
        );

        PERFORM add_compression_policy('device_cmd_logs', INTERVAL '7 days');

        RAISE NOTICE 'Compression policy added for device_cmd_logs';
    ELSE
        RAISE NOTICE 'device_cmd_logs hypertable not found, skipping';
    END IF;
END $$;

INSERT INTO schema_migrations (version, name) VALUES (3, 'timescaledb_compression') ON CONFLICT DO NOTHING;

COMMIT;