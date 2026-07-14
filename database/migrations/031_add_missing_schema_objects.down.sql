-- 031_add_missing_schema_objects.down: 回滚 031 迁移
-- 按逆序删除 up 文件创建的对象：触发器 → 函数 → 表 → 列

-- 3. 删除 sync_device_timezone 触发器和函数
DROP TRIGGER IF EXISTS trg_sync_device_timezone ON devices;
DROP FUNCTION IF EXISTS sync_device_timezone();

-- 2. 删除 user_device_rel 表
DROP TABLE IF EXISTS user_device_rel;

-- 1. 删除 devices.model_id 列（含索引自动删除）
ALTER TABLE devices DROP COLUMN IF EXISTS model_id;
