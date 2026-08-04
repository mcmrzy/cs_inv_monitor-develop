-- 095 回滚：移除设备别名/备注、全局设备排序与电站排序字段
DROP INDEX IF EXISTS idx_devices_user_global_sort;
DROP INDEX IF EXISTS idx_stations_user_sort;

ALTER TABLE devices
    DROP COLUMN IF EXISTS alias,
    DROP COLUMN IF EXISTS remark,
    DROP COLUMN IF EXISTS global_sort_order;

ALTER TABLE stations
    DROP COLUMN IF EXISTS sort_order;
