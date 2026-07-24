-- 002_add_performance_indexes: indexes for frequent queries.
BEGIN;

CREATE INDEX IF NOT EXISTS idx_devices_user_station_deleted
    ON devices(user_id, station_id, deleted_at)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_devices_status_online
    ON devices(status, last_online_at DESC)
    WHERE status = 1;

CREATE INDEX IF NOT EXISTS idx_alarms_device_time
    ON alarms(device_sn, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_alarms_pending
    ON alarms(status, created_at DESC)
    WHERE status = 0;

CREATE INDEX IF NOT EXISTS idx_stations_user_deleted
    ON stations(user_id, deleted_at)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_users_email
    ON users(phone)
    WHERE deleted_at IS NULL;

DO $$
BEGIN
    IF to_regclass('public.device_alarms') IS NOT NULL THEN
        CREATE INDEX IF NOT EXISTS idx_device_alarms_sn_time
            ON device_alarms(device_sn, created_at DESC);
    END IF;
    IF to_regclass('public.device_telemetry') IS NOT NULL THEN
        CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time
            ON device_telemetry(device_sn, time DESC);
    END IF;
    IF to_regclass('public.device_cmd_logs') IS NOT NULL THEN
        CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn_time
            ON device_cmd_logs(device_sn, sent_at DESC);
    END IF;
    IF to_regclass('public.device_day_data') IS NOT NULL THEN
        CREATE INDEX IF NOT EXISTS idx_day_data_sn_date
            ON device_day_data(device_sn, data_date DESC);
    END IF;
END $$;

INSERT INTO schema_migrations(version, name)
VALUES (2, 'add_performance_indexes')
ON CONFLICT DO NOTHING;

COMMIT;
