-- Independent OTA idempotency is keyed by the user/device/request key.
-- The operation is payload metadata, not part of the request identity.
DROP INDEX IF EXISTS uq_ota_idem_user_device_op_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_ota_idem_user_device_key
    ON ota_idempotency_requests (user_id, device_sn, idempotency_key);

