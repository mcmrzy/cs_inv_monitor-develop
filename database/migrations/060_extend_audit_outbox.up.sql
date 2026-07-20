-- 060: Extend immutable audit records and add durable idempotency/outbox stores.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'audit_logs'
          AND column_name = 'resource_id' AND data_type <> 'text'
    ) THEN
        ALTER TABLE audit_logs
            ALTER COLUMN resource_id TYPE TEXT USING resource_id::TEXT;
    END IF;
END;
$$;

ALTER TABLE audit_logs
    ADD COLUMN IF NOT EXISTS root_tenant_id BIGINT,
    ADD COLUMN IF NOT EXISTS active_organization_id BIGINT,
    ADD COLUMN IF NOT EXISTS request_id VARCHAR(128),
    ADD COLUMN IF NOT EXISTS result VARCHAR(20) NOT NULL DEFAULT 'success',
    ADD COLUMN IF NOT EXISTS failure_reason TEXT,
    ADD COLUMN IF NOT EXISTS before_data JSONB,
    ADD COLUMN IF NOT EXISTS after_data JSONB,
    ADD COLUMN IF NOT EXISTS event_schema_version VARCHAR(20) NOT NULL DEFAULT '1.0';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='audit_logs'::regclass AND conname='audit_logs_result_check') THEN
        ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_result_check
            CHECK (result IN ('success', 'denied', 'failed'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='audit_logs'::regclass AND conname='audit_logs_active_org_requires_root') THEN
        ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_active_org_requires_root
            CHECK (active_organization_id IS NULL OR root_tenant_id IS NOT NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='audit_logs'::regclass AND conname='fk_audit_logs_tenant_root') THEN
        ALTER TABLE audit_logs ADD CONSTRAINT fk_audit_logs_tenant_root
            FOREIGN KEY (root_tenant_id) REFERENCES tenant_roots(root_tenant_id) ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='audit_logs'::regclass AND conname='fk_audit_logs_operator') THEN
        ALTER TABLE audit_logs ADD CONSTRAINT fk_audit_logs_operator
            FOREIGN KEY (operator_id) REFERENCES users(id) ON DELETE RESTRICT NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='audit_logs'::regclass AND conname='fk_audit_logs_active_org_same_root') THEN
        ALTER TABLE audit_logs ADD CONSTRAINT fk_audit_logs_active_org_same_root
            FOREIGN KEY (root_tenant_id, active_organization_id)
            REFERENCES organizations(root_tenant_id, id) ON DELETE RESTRICT;
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_audit_logs_root_created
    ON audit_logs(root_tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_request
    ON audit_logs(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_active_org_fk
    ON audit_logs(root_tenant_id, active_organization_id)
    WHERE active_organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_operator_fk
    ON audit_logs(operator_id) WHERE operator_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS idempotency_responses (
    id BIGSERIAL PRIMARY KEY,
    root_tenant_id BIGINT NOT NULL REFERENCES tenant_roots(root_tenant_id) ON DELETE RESTRICT,
    actor_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    endpoint VARCHAR(255) NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint) >= 32),
    response_status INTEGER NOT NULL CHECK (response_status BETWEEN 200 AND 299),
    response_headers JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(response_headers) = 'object'),
    response_body JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    CONSTRAINT idempotency_response_expiry CHECK (expires_at IS NULL OR expires_at > created_at),
    CONSTRAINT uq_idempotency_response UNIQUE (root_tenant_id, actor_id, endpoint, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_responses_expiry
    ON idempotency_responses(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_idempotency_responses_actor_fk
    ON idempotency_responses(actor_id);

CREATE TABLE IF NOT EXISTS transactional_outbox (
    id BIGSERIAL PRIMARY KEY,
    event_id UUID NOT NULL UNIQUE,
    root_tenant_id BIGINT NOT NULL REFERENCES tenant_roots(root_tenant_id) ON DELETE RESTRICT,
    aggregate_type VARCHAR(80) NOT NULL,
    aggregate_id TEXT NOT NULL,
    event_type VARCHAR(128) NOT NULL,
    event_schema_version VARCHAR(20) NOT NULL,
    envelope JSONB NOT NULL CHECK (jsonb_typeof(envelope) = 'object'),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'publishing', 'published', 'failed')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    max_attempts INTEGER NOT NULL DEFAULT 10 CHECK (max_attempts > 0),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    locked_by VARCHAR(128),
    last_error TEXT,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT transactional_outbox_attempts_check CHECK (attempt_count <= max_attempts)
);

CREATE INDEX IF NOT EXISTS idx_transactional_outbox_dispatch
    ON transactional_outbox(status, next_attempt_at, id)
    WHERE status IN ('pending', 'failed');
CREATE INDEX IF NOT EXISTS idx_transactional_outbox_aggregate
    ON transactional_outbox(root_tenant_id, aggregate_type, aggregate_id, created_at);

CREATE OR REPLACE FUNCTION reject_audit_log_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs are immutable: % is not allowed', TG_OP
        USING ERRCODE = '55000';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION reject_audit_log_mutation();

-- Production role ownership is configured in Task 19/deployment because many
-- managed PostgreSQL services forbid CREATE ROLE in application migrations.
-- PUBLIC never receives mutation rights; the trigger remains defense in depth.
REVOKE UPDATE, DELETE ON audit_logs FROM PUBLIC;
