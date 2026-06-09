-- 002_add_performance_indexes: 高频查询索引优化
-- 目标: 消除 >100ms 的慢查询

BEGIN;

-- 设备列表查询: user_id + station_id + deleted_at 复合索引
CREATE INDEX IF NOT EXISTS idx_devices_user_station_deleted
    ON devices(user_id, station_id, deleted_at)
    WHERE deleted_at IS NULL;

-- 设备状态查询: 在线设备快速筛选
CREATE INDEX IF NOT EXISTS idx_devices_status_online
    ON devices(status, last_online_at DESC)
    WHERE status = 1;

-- 告警查询: device_sn + created_at DESC（支持分页）
CREATE INDEX IF NOT EXISTS idx_alarms_device_time
    ON alarms(device_sn, created_at DESC);

-- 告警未处理快速查询
CREATE INDEX IF NOT EXISTS idx_alarms_pending
    ON alarms(status, created_at DESC)
    WHERE status = 0;

-- 电站列表查询: user_id + deleted_at
CREATE INDEX IF NOT EXISTS idx_stations_user_deleted
    ON stations(user_id, deleted_at)
    WHERE deleted_at IS NULL;

-- 用户邮箱索引（支持邮箱登录）
CREATE INDEX IF NOT EXISTS idx_users_email ON users(phone) WHERE deleted_at IS NULL;

-- device_alarms 表索引（如果存在）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'device_alarms') THEN
        CREATE INDEX IF NOT EXISTS idx_device_alarms_sn_time
            ON device_alarms(device_sn, created_at DESC);
    END IF;
END $$;

-- device_telemetry 表索引（如果存在 TimescaleDB 超表）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'device_telemetry') THEN
        CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time
            ON device_telemetry(device_sn, time DESC);
    END IF;
END $$;

-- device_cmd_logs 表索引（如果存在）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'device_cmd_logs') THEN
        CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn_time
            ON device_cmd_logs(device_sn, sent_at DESC);
    END IF;
END $$;

-- device_day_data 表索引（如果存在）
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'device_day_data') THEN
        CREATE INDEX IF NOT EXISTS idx_day_data_sn_date
            ON device_day_data(device_sn, data_date DESC);
    END IF;
END $$;

INSERT INTO schema_migrations (version, name) VALUES (2, 'add_performance_indexes') ON CONFLICT DO NOTHING;

COMMIT;