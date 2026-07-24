-- 043: Repair objects that fresh baseline_version=22 databases missed because
-- migrations 007 and 019 are recorded as applied without executing their bodies.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'task_id'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE device_cmd_logs ADD COLUMN task_id VARCHAR(64);
        COMMENT ON COLUMN device_cmd_logs.task_id IS 'migration 043 baseline repair: command task identifier';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'params'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE device_cmd_logs ADD COLUMN params JSONB DEFAULT '{}'::jsonb;
        COMMENT ON COLUMN device_cmd_logs.params IS 'migration 043 baseline repair: command parameters';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'status'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE device_cmd_logs ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
        COMMENT ON COLUMN device_cmd_logs.status IS 'migration 043 baseline repair: command lifecycle status';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'data'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE device_cmd_logs ADD COLUMN data JSONB DEFAULT '{}'::jsonb;
        COMMENT ON COLUMN device_cmd_logs.data IS 'migration 043 baseline repair: command response data';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('devices')
          AND attname = 'installer_id'
          AND NOT attisdropped
    ) THEN
        ALTER TABLE devices ADD COLUMN installer_id BIGINT;
        COMMENT ON COLUMN devices.installer_id IS 'migration 043 baseline repair: installer user ID';
    END IF;
END $$;

DO $$
BEGIN
    IF to_regclass('idx_cmd_logs_task_id') IS NULL THEN
        CREATE INDEX idx_cmd_logs_task_id ON device_cmd_logs(task_id);
        COMMENT ON INDEX idx_cmd_logs_task_id IS 'migration 043 baseline repair';
    END IF;

    IF to_regclass('idx_cmd_logs_status') IS NULL THEN
        CREATE INDEX idx_cmd_logs_status ON device_cmd_logs(status);
        COMMENT ON INDEX idx_cmd_logs_status IS 'migration 043 baseline repair';
    END IF;

    IF to_regclass('idx_cmd_logs_sn_created') IS NULL THEN
        CREATE INDEX idx_cmd_logs_sn_created ON device_cmd_logs(device_sn, sent_at DESC);
        COMMENT ON INDEX idx_cmd_logs_sn_created IS 'migration 043 baseline repair';
    END IF;

    IF to_regclass('idx_devices_installer') IS NULL THEN
        CREATE INDEX idx_devices_installer ON devices(installer_id);
        COMMENT ON INDEX idx_devices_installer IS 'migration 043 baseline repair';
    END IF;
END $$;
