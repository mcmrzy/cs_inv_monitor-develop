-- Migration 119 down: 恢复包含 operation 的幂等唯一索引
DROP INDEX IF EXISTS uq_ota_idem_user_device_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_ota_idem_user_device_op_key
    ON ota_idempotency_requests (user_id, device_sn, operation, idempotency_key);
