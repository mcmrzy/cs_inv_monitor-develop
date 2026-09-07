-- 080_auto_bind_device_model_id.down.sql
-- 回滚：将自动绑定的 model_id 恢复为 NULL（不影响后续手动绑定）

UPDATE devices
SET model_id = NULL, updated_at = NOW()
WHERE model_id IS NOT NULL
  AND deleted_at IS NULL;
