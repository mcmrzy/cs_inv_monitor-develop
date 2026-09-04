-- 080_auto_bind_device_model_id.up.sql
-- 将所有 model 文本能匹配到 device_models.model_code 的设备，自动绑定 model_id
-- 解决存量设备 model_id 为 NULL 的问题

UPDATE devices d
SET model_id = dm.id, updated_at = NOW()
FROM device_models dm
WHERE d.model = dm.model_code
  AND d.model_id IS NULL
  AND dm.lifecycle_status != 'retired'
  AND d.deleted_at IS NULL;
