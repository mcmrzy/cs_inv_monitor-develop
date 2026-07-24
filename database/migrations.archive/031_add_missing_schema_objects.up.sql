-- 031_add_missing_schema_objects: 补齐代码中引用但缺少迁移文件的数据库对象
-- 涵盖三个对象：
--   1. devices.model_id 列（Go 代码多处引用，如 telemetry_repository.go、model_registry_repository.go）
--   2. user_device_rel 表（Go 代码 8 处引用，如 repositories.go、ota_repository.go、dashboard_handler.go）
--   3. sync_device_timezone() 函数及触发器（生产备份 schema 中存在，用于设备时区与电站时区同步）
-- 所有 DDL 使用 IF NOT EXISTS / CREATE OR REPLACE 确保幂等性

-- ============================================
-- 1. devices.model_id 列
-- ============================================
-- 关联 device_models 表，Go 代码通过 d.model_id 进行型号关联查询
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model_id BIGINT REFERENCES device_models(id);
CREATE INDEX IF NOT EXISTS idx_devices_model_id ON devices(model_id) WHERE model_id IS NOT NULL;

-- ============================================
-- 2. user_device_rel 表
-- ============================================
-- 用户-设备关联表，记录用户与设备的绑定关系
-- 生产备份中已存在此表（BIGSERIAL + UNIQUE 约束），本迁移补齐 FK 约束和索引
CREATE TABLE IF NOT EXISTS user_device_rel (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_sn VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_sn)
);
CREATE INDEX IF NOT EXISTS idx_user_device_rel_user ON user_device_rel(user_id);
CREATE INDEX IF NOT EXISTS idx_user_device_rel_sn ON user_device_rel(device_sn);

-- ============================================
-- 3. sync_device_timezone() 函数及触发器
-- ============================================
-- 设备 station_id 变更时自动从电站同步时区
-- 使用生产备份中的健壮版本：检查 station_id 是否实际变更 + COALESCE 默认时区
CREATE OR REPLACE FUNCTION sync_device_timezone()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.station_id IS NOT NULL AND (OLD.station_id IS NULL OR OLD.station_id != NEW.station_id) THEN
        SELECT COALESCE(s.timezone, 'Asia/Shanghai')
        INTO NEW.timezone
        FROM stations s
        WHERE s.id = NEW.station_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_device_timezone ON devices;
CREATE TRIGGER trg_sync_device_timezone
    BEFORE INSERT OR UPDATE OF station_id ON devices
    FOR EACH ROW EXECUTE FUNCTION sync_device_timezone();
