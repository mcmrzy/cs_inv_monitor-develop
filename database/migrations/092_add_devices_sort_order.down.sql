-- 092 回滚：移除 devices.sort_order 字段
DROP INDEX IF EXISTS idx_devices_station_sort;

ALTER TABLE devices
    DROP COLUMN IF EXISTS sort_order;
