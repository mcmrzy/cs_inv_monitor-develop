-- 101_add_device_claim_and_transfer.down.sql
-- Rollback: Device Claim and Transfer Management
-- Removes claim tokens and transfer request tables re-created in migration 101
-- 注意：先删触发器再删函数（触发器依赖函数，顺序颠倒会报 cannot drop function）

DROP TRIGGER IF EXISTS trigger_device_claim_tokens_updated_at ON device_claim_tokens;
DROP TRIGGER IF EXISTS trigger_device_transfer_requests_updated_at ON device_transfer_requests;
DROP FUNCTION IF EXISTS trigger_updated_at_timestamp();
DROP FUNCTION IF EXISTS cleanup_expired_claim_tokens();
DROP INDEX IF EXISTS idx_claim_tokens_sn;
DROP INDEX IF EXISTS idx_claim_tokens_code_digest;
DROP INDEX IF EXISTS idx_claim_tokens_root_tenant;
DROP INDEX IF EXISTS idx_claim_tokens_expires;
DROP INDEX IF EXISTS idx_transfer_device;
DROP INDEX IF EXISTS idx_transfer_from_tenant;
DROP INDEX IF EXISTS idx_transfer_to_tenant;
DROP INDEX IF EXISTS idx_transfer_status;
DROP INDEX IF EXISTS idx_transfer_requester;
DROP TABLE IF EXISTS device_claim_tokens;
DROP TABLE IF EXISTS device_transfer_requests;
