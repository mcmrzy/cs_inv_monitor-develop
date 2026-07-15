-- Only remove indexes that migration 044 itself created. Indexes originating
-- from historical migration 002 have no 044 ownership marker and remain.

DO $$
BEGIN
    IF to_regclass('idx_device_alarms_sn_time') IS NOT NULL
       AND obj_description(to_regclass('idx_device_alarms_sn_time'), 'pg_class') = 'migration 044 baseline index repair' THEN
        DROP INDEX idx_device_alarms_sn_time;
    END IF;

    IF to_regclass('idx_stations_user_deleted') IS NOT NULL
       AND obj_description(to_regclass('idx_stations_user_deleted'), 'pg_class') = 'migration 044 baseline index repair' THEN
        DROP INDEX idx_stations_user_deleted;
    END IF;

    IF to_regclass('idx_alarms_pending') IS NOT NULL
       AND obj_description(to_regclass('idx_alarms_pending'), 'pg_class') = 'migration 044 baseline index repair' THEN
        DROP INDEX idx_alarms_pending;
    END IF;

    IF to_regclass('idx_alarms_device_time') IS NOT NULL
       AND obj_description(to_regclass('idx_alarms_device_time'), 'pg_class') = 'migration 044 baseline index repair' THEN
        DROP INDEX idx_alarms_device_time;
    END IF;

    IF to_regclass('idx_devices_status_online') IS NOT NULL
       AND obj_description(to_regclass('idx_devices_status_online'), 'pg_class') = 'migration 044 baseline index repair' THEN
        DROP INDEX idx_devices_status_online;
    END IF;

    IF to_regclass('idx_devices_user_station_deleted') IS NOT NULL
       AND obj_description(to_regclass('idx_devices_user_station_deleted'), 'pg_class') = 'migration 044 baseline index repair' THEN
        DROP INDEX idx_devices_user_station_deleted;
    END IF;

    IF to_regclass('idx_alarms_old_pending') IS NOT NULL
       AND obj_description(to_regclass('idx_alarms_old_pending'), 'pg_class') =
           'migration 044 baseline index repair: renamed legacy idx_alarms_pending' THEN
        ALTER INDEX idx_alarms_old_pending RENAME TO idx_alarms_pending;
        COMMENT ON INDEX idx_alarms_pending IS NULL;
    END IF;

    IF to_regclass('idx_alarms_old_device_time') IS NOT NULL
       AND obj_description(to_regclass('idx_alarms_old_device_time'), 'pg_class') =
           'migration 044 baseline index repair: renamed legacy idx_alarms_device_time' THEN
        ALTER INDEX idx_alarms_old_device_time RENAME TO idx_alarms_device_time;
        COMMENT ON INDEX idx_alarms_device_time IS NULL;
    END IF;
END $$;
