-- 003_timescaledb_compression: TimescaleDB 压缩策略
-- 目标: 7天以上的 chunk 自动压缩，节省存储空间
-- 幂等: 检查 TimescaleDB 扩展是否存在，检查压缩策略是否已设置

BEGIN;

-- 检查 TimescaleDB 扩展是否安装
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        RAISE NOTICE 'TimescaleDB extension not installed, skipping compression policies';
    END IF;
END $$;

-- 启用 device_telemetry 压缩（如果超表存在且 TimescaleDB 已安装）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb')
       AND EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_telemetry') THEN
        ALTER TABLE device_telemetry SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'time DESC'
        );

        -- 仅在压缩策略不存在时添加
        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs j
            JOIN timescaledb_information.hypertables h ON h.hypertable_name = 'device_telemetry'
            WHERE j.proc_name = 'policy_compression'
              AND j.hypertable_name = 'device_telemetry'
        ) THEN
            PERFORM add_compression_policy('device_telemetry', INTERVAL '7 days');
            RAISE NOTICE 'Compression policy added for device_telemetry';
        ELSE
            RAISE NOTICE 'Compression policy already exists for device_telemetry';
        END IF;
    ELSE
        RAISE NOTICE 'device_telemetry hypertable not found or TimescaleDB not installed, skipping';
    END IF;
END $$;

-- 启用 device_alarms 压缩（如果超表存在且 TimescaleDB 已安装）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb')
       AND EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_alarms') THEN
        ALTER TABLE device_alarms SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'created_at DESC'
        );

        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs j
            WHERE j.proc_name = 'policy_compression'
              AND j.hypertable_name = 'device_alarms'
        ) THEN
            PERFORM add_compression_policy('device_alarms', INTERVAL '30 days');
            RAISE NOTICE 'Compression policy added for device_alarms';
        ELSE
            RAISE NOTICE 'Compression policy already exists for device_alarms';
        END IF;
    ELSE
        RAISE NOTICE 'device_alarms hypertable not found or TimescaleDB not installed, skipping';
    END IF;
END $$;

-- 启用 device_cmd_logs 压缩（如果超表存在且 TimescaleDB 已安装）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb')
       AND EXISTS (SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'device_cmd_logs') THEN
        ALTER TABLE device_cmd_logs SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'sent_at DESC'
        );

        IF NOT EXISTS (
            SELECT 1 FROM timescaledb_information.jobs j
            WHERE j.proc_name = 'policy_compression'
              AND j.hypertable_name = 'device_cmd_logs'
        ) THEN
            PERFORM add_compression_policy('device_cmd_logs', INTERVAL '7 days');
            RAISE NOTICE 'Compression policy added for device_cmd_logs';
        ELSE
            RAISE NOTICE 'Compression policy already exists for device_cmd_logs';
        END IF;
    ELSE
        RAISE NOTICE 'device_cmd_logs hypertable not found or TimescaleDB not installed, skipping';
    END IF;
END $$;

INSERT INTO schema_migrations (version, name) VALUES (3, 'timescaledb_compression') ON CONFLICT DO NOTHING;

COMMIT;
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