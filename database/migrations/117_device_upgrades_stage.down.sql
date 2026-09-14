-- 回滚 117：移除 device_upgrades.stage。
-- 前端会在 stage 缺失时回退到 status 展示，故回滚不残留 UI 故障。
ALTER TABLE device_upgrades DROP COLUMN IF EXISTS stage;
