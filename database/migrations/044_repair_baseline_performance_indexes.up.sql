-- 044: Repair useful performance indexes that fresh baseline_version=22
-- databases missed because migration 002 is recorded as applied without
-- executing its body.

-- Migration 036 kept the original alarms table as alarms_old. Databases that
-- actually ran migration 002 can therefore still have these names attached
-- to the backup table. Migration 039 now handles that path directly, while
-- this compatibility block repairs databases where the older 039 body was
-- already applied.
DO $$
DECLARE
    owner_table TEXT;
BEGIN
    IF to_regclass('idx_alarms_device_time') IS NOT NULL THEN
        SELECT tbl.relname INTO owner_table
        FROM pg_index pi
        JOIN pg_class tbl ON tbl.oid = pi.indrelid
        WHERE pi.indexrelid = to_regclass('idx_alarms_device_time');

        IF owner_table = 'alarms_old' THEN
            IF to_regclass('idx_alarms_old_device_time') IS NOT NULL THEN
                RAISE EXCEPTION 'cannot preserve idx_alarms_device_time: idx_alarms_old_device_time already exists';
            END IF;
            IF obj_description(to_regclass('idx_alarms_device_time'), 'pg_class') IS NOT NULL THEN
                RAISE EXCEPTION 'cannot safely preserve commented legacy index idx_alarms_device_time';
            END IF;
            ALTER INDEX idx_alarms_device_time RENAME TO idx_alarms_old_device_time;
            COMMENT ON INDEX idx_alarms_old_device_time IS
                'migration 044 baseline index repair: renamed legacy idx_alarms_device_time';
        ELSIF owner_table <> 'alarms' THEN
            RAISE EXCEPTION 'idx_alarms_device_time belongs to unexpected table %', owner_table;
        END IF;
    END IF;

    owner_table := NULL;
    IF to_regclass('idx_alarms_pending') IS NOT NULL THEN
        SELECT tbl.relname INTO owner_table
        FROM pg_index pi
        JOIN pg_class tbl ON tbl.oid = pi.indrelid
        WHERE pi.indexrelid = to_regclass('idx_alarms_pending');

        IF owner_table = 'alarms_old' THEN
            IF to_regclass('idx_alarms_old_pending') IS NOT NULL THEN
                RAISE EXCEPTION 'cannot preserve idx_alarms_pending: idx_alarms_old_pending already exists';
            END IF;
            IF obj_description(to_regclass('idx_alarms_pending'), 'pg_class') IS NOT NULL THEN
                RAISE EXCEPTION 'cannot safely preserve commented legacy index idx_alarms_pending';
            END IF;
            ALTER INDEX idx_alarms_pending RENAME TO idx_alarms_old_pending;
            COMMENT ON INDEX idx_alarms_old_pending IS
                'migration 044 baseline index repair: renamed legacy idx_alarms_pending';
        ELSIF owner_table <> 'alarms' THEN
            RAISE EXCEPTION 'idx_alarms_pending belongs to unexpected table %', owner_table;
        END IF;
    END IF;
END $$;

DO $$
BEGIN
    IF to_regclass('idx_devices_user_station_deleted') IS NULL THEN
        CREATE INDEX idx_devices_user_station_deleted
            ON devices(user_id, station_id, deleted_at)
            WHERE deleted_at IS NULL;
        COMMENT ON INDEX idx_devices_user_station_deleted IS 'migration 044 baseline index repair';
    END IF;

    IF to_regclass('idx_devices_status_online') IS NULL THEN
        CREATE INDEX idx_devices_status_online
            ON devices(status, last_online_at DESC)
            WHERE status = 1;
        COMMENT ON INDEX idx_devices_status_online IS 'migration 044 baseline index repair';
    END IF;

    IF to_regclass('idx_alarms_device_time') IS NULL THEN
        CREATE INDEX idx_alarms_device_time
            ON alarms(device_sn, created_at DESC);
        COMMENT ON INDEX idx_alarms_device_time IS 'migration 044 baseline index repair';
    END IF;

    IF to_regclass('idx_alarms_pending') IS NULL THEN
        CREATE INDEX idx_alarms_pending
            ON alarms(status, created_at DESC)
            WHERE status = 0;
        COMMENT ON INDEX idx_alarms_pending IS 'migration 044 baseline index repair';
    END IF;

    IF to_regclass('idx_stations_user_deleted') IS NULL THEN
        CREATE INDEX idx_stations_user_deleted
            ON stations(user_id, deleted_at)
            WHERE deleted_at IS NULL;
        COMMENT ON INDEX idx_stations_user_deleted IS 'migration 044 baseline index repair';
    END IF;

    IF to_regclass('idx_device_alarms_sn_time') IS NULL THEN
        CREATE INDEX idx_device_alarms_sn_time
            ON device_alarms(device_sn, created_at DESC);
        COMMENT ON INDEX idx_device_alarms_sn_time IS 'migration 044 baseline index repair';
    END IF;
END $$;
