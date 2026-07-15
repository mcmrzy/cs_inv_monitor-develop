-- Only remove objects that migration 043 itself created. Objects originating
-- from historical migrations 007/019 have no 043 ownership marker and remain.

DO $$
BEGIN
    IF to_regclass('idx_devices_installer') IS NOT NULL
       AND obj_description(to_regclass('idx_devices_installer'), 'pg_class') = 'migration 043 baseline repair' THEN
        DROP INDEX idx_devices_installer;
    END IF;

    IF to_regclass('idx_cmd_logs_sn_created') IS NOT NULL
       AND obj_description(to_regclass('idx_cmd_logs_sn_created'), 'pg_class') = 'migration 043 baseline repair' THEN
        DROP INDEX idx_cmd_logs_sn_created;
    END IF;

    IF to_regclass('idx_cmd_logs_status') IS NOT NULL
       AND obj_description(to_regclass('idx_cmd_logs_status'), 'pg_class') = 'migration 043 baseline repair' THEN
        DROP INDEX idx_cmd_logs_status;
    END IF;

    IF to_regclass('idx_cmd_logs_task_id') IS NOT NULL
       AND obj_description(to_regclass('idx_cmd_logs_task_id'), 'pg_class') = 'migration 043 baseline repair' THEN
        DROP INDEX idx_cmd_logs_task_id;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = to_regclass('devices')
          AND attname = 'installer_id'
          AND NOT attisdropped
          AND col_description(attrelid, attnum) = 'migration 043 baseline repair: installer user ID'
    ) THEN
        ALTER TABLE devices DROP COLUMN installer_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'data'
          AND NOT attisdropped
          AND col_description(attrelid, attnum) = 'migration 043 baseline repair: command response data'
    ) THEN
        ALTER TABLE device_cmd_logs DROP COLUMN data;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'status'
          AND NOT attisdropped
          AND col_description(attrelid, attnum) = 'migration 043 baseline repair: command lifecycle status'
    ) THEN
        ALTER TABLE device_cmd_logs DROP COLUMN status;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'params'
          AND NOT attisdropped
          AND col_description(attrelid, attnum) = 'migration 043 baseline repair: command parameters'
    ) THEN
        ALTER TABLE device_cmd_logs DROP COLUMN params;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = to_regclass('device_cmd_logs')
          AND attname = 'task_id'
          AND NOT attisdropped
          AND col_description(attrelid, attnum) = 'migration 043 baseline repair: command task identifier'
    ) THEN
        ALTER TABLE device_cmd_logs DROP COLUMN task_id;
    END IF;
END $$;
