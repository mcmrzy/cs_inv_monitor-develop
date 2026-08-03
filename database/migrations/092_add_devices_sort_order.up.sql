-- 092: 为 devices 表增加 sort_order 字段，支持 App 端设备卡片长按拖动排序
-- 幂等可重放：ALTER 使用 IF NOT EXISTS
ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- 电站内设备排序索引：按电站 + 排序值查询
CREATE INDEX IF NOT EXISTS idx_devices_station_sort
    ON devices(station_id, sort_order, id)
    WHERE deleted_at IS NULL;
