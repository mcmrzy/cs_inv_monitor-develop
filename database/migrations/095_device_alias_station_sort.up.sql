-- 095: 设备别名/备注 + 电站排序 + 全局设备排序
-- 1) devices 增加 alias/remark（App 设备编辑页可修改）
-- 2) devices 增加 global_sort_order（/devices 全局列表拖动排序，
--    与 sort_order 电站内排序语义独立，互不覆盖）
-- 3) stations 增加 sort_order（首页电站卡片拖动排序）
-- 幂等可重放：ALTER 使用 IF NOT EXISTS
ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS alias VARCHAR(100);

ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS remark TEXT;

ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS global_sort_order INTEGER NOT NULL DEFAULT 0;

ALTER TABLE stations
    ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- 全局设备排序索引：按用户 + 排序值查询
CREATE INDEX IF NOT EXISTS idx_devices_user_global_sort
    ON devices(user_id, global_sort_order, id)
    WHERE deleted_at IS NULL;

-- 电站排序索引：按用户 + 排序值查询
CREATE INDEX IF NOT EXISTS idx_stations_user_sort
    ON stations(user_id, sort_order, id)
    WHERE deleted_at IS NULL;
