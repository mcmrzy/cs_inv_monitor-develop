-- 112 down: 回滚心跳 V2 储能 BMS 扩展组（bms 45 值）
-- 顺序与 up 相反：先删 protocol_fields（RESTRICT 引用），再还原 schema_hash，最后删 catalog 键。

-- 1. 删除 heartbeat v2 组 'bms' 全部字段注册
DELETE FROM device_protocol_fields pf
USING device_protocol_versions pv
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code='bms';

-- 2. 还原 schema_hash 至 V2.1
UPDATE device_protocol_versions
SET schema_hash = 'heartbeat-v2-csl10-6k2-v2.1-20260805', updated_at = NOW()
WHERE protocol_code = 'heartbeat' AND version = 2;

-- 3. 删除本迁移新增的 catalog 键（仅 bms 类目，避免误删）
DELETE FROM telemetry_field_catalog WHERE category = 'bms' AND field_key LIKE 'bms\_%';
