-- Migration: Device Claim and Transfer Management
-- Purpose: Add claim tokens and transfer request tracking for multi-level channel ownership workflows
-- Version: 068
-- Date: 2026-07-21

-- ============================================
-- Table: device_claim_tokens
-- Stores claim codes for installer/distributor device claiming workflow
-- ============================================

CREATE TABLE IF NOT EXISTS device_claim_tokens (
    id BIGSERIAL PRIMARY KEY,
    sn VARCHAR(100) NOT NULL,
    claim_code VARCHAR(32) NOT NULL, -- URL-safe base64, 16 chars = 128-bit entropy
    claim_code_digest VARCHAR(64) NOT NULL, -- SHA-256 hex digest of raw code
    root_tenant_id BIGINT NOT NULL,
    assigned_organization_id BIGINT REFERENCES organizations(id) ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'unclaimed' 
        CHECK (status IN ('unclaimed', 'reserved', 'claimed')),
    created_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    expires_at TIMESTAMP NOT NULL,
    claimed_at TIMESTAMP,
    claimed_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(sn, root_tenant_id)
);

-- Indexes for efficient lookup
CREATE INDEX IF NOT EXISTS idx_claim_tokens_sn ON device_claim_tokens(sn);
CREATE INDEX IF NOT EXISTS idx_claim_tokens_code_digest ON device_claim_tokens(claim_code_digest);
CREATE INDEX IF NOT EXISTS idx_claim_tokens_root_tenant ON device_claim_tokens(root_tenant_id);
CREATE INDEX IF NOT EXISTS idx_claim_tokens_expires ON device_claim_tokens(expires_at) WHERE status != 'claimed';

-- ============================================
-- Table: device_transfer_requests
-- Tracks ownership transfer approval workflow between tenants
-- ============================================

CREATE TABLE IF NOT EXISTS device_transfer_requests (
    id BIGSERIAL PRIMARY KEY,
    device_sn VARCHAR(100) NOT NULL,
    from_root_tenant_id BIGINT NOT NULL,
    to_root_tenant_id BIGINT NOT NULL,
    requester_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reason TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' 
        CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    approved_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMP,
    rejected_reason TEXT,
    requested_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(device_sn, status)
);

-- Indexes for transfer management queries
CREATE INDEX IF NOT EXISTS idx_transfer_device ON device_transfer_requests(device_sn);
CREATE INDEX IF NOT EXISTS idx_transfer_from_tenant ON device_transfer_requests(from_root_tenant_id);
CREATE INDEX IF NOT EXISTS idx_transfer_to_tenant ON device_transfer_requests(to_root_tenant_id);
CREATE INDEX IF NOT EXISTS idx_transfer_status ON device_transfer_requests(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_transfer_requester ON device_transfer_requests(requester_user_id);

-- ============================================
-- Function: trigger_updated_at_timestamp()
-- Automatically updates updated_at timestamp on row modifications
-- ============================================

CREATE OR REPLACE FUNCTION trigger_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach triggers to both tables
DROP TRIGGER IF EXISTS trigger_device_claim_tokens_updated_at ON device_claim_tokens;
DROP TRIGGER IF EXISTS trigger_device_transfer_requests_updated_at ON device_transfer_requests;

CREATE TRIGGER trigger_device_claim_tokens_updated_at
    BEFORE UPDATE ON device_claim_tokens
    FOR EACH ROW
    EXECUTE FUNCTION trigger_updated_at_timestamp();

CREATE TRIGGER trigger_device_transfer_requests_updated_at
    BEFORE UPDATE ON device_transfer_requests
    FOR EACH ROW
    EXECUTE FUNCTION trigger_updated_at_timestamp();

-- ============================================
-- Function: clean_expired_claim_tokens()
-- Cleanup utility to remove expired unclaimed tokens
-- Should be run periodically (e.g., via cron job)
-- ============================================

CREATE OR REPLACE FUNCTION cleanup_expired_claim_tokens()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM device_claim_tokens 
    WHERE status = 'unclaimed' AND expires_at < NOW();
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Grant permissions (adjust as needed for your role structure)
-- ============================================

-- Grant permissions to the current database user (portable across environments)
DO $$
BEGIN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON device_claim_tokens TO ' || current_user;
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON device_transfer_requests TO ' || current_user;
    EXECUTE 'GRANT EXECUTE ON FUNCTION cleanup_expired_claim_tokens() TO ' || current_user;
    EXECUTE 'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ' || current_user;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping GRANT (non-fatal): %', SQLERRM;
END
$$;
