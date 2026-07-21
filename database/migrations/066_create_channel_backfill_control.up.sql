-- 066: Durable, resumable control plane for explicit channel backfill jobs.

CREATE TABLE IF NOT EXISTS channel_migration_runs (
    id UUID PRIMARY KEY,
    job_name VARCHAR(80) NOT NULL,
    mapping_digest CHAR(64) NOT NULL CHECK (mapping_digest ~ '^[0-9a-f]{64}$'),
    source_digest CHAR(64) NOT NULL CHECK (source_digest ~ '^[0-9a-f]{64}$'),
    source_watermark BIGINT NOT NULL CHECK (source_watermark >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'prepared'
        CHECK (status IN ('prepared', 'running', 'completed', 'failed', 'cancelled')),
    summary JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(summary) = 'object'),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT channel_migration_run_completion CHECK (
        (status IN ('completed', 'failed', 'cancelled') AND completed_at IS NOT NULL)
        OR (status IN ('prepared', 'running') AND completed_at IS NULL)
    ),
    UNIQUE(job_name, mapping_digest, source_digest)
);

CREATE TABLE IF NOT EXISTS channel_migration_checkpoints (
    run_id UUID NOT NULL REFERENCES channel_migration_runs(id) ON DELETE RESTRICT,
    job_name VARCHAR(80) NOT NULL,
    partition_key VARCHAR(80) NOT NULL DEFAULT 'organizations',
    mapping_digest CHAR(64) NOT NULL CHECK (mapping_digest ~ '^[0-9a-f]{64}$'),
    next_ordinal BIGINT NOT NULL DEFAULT 0 CHECK (next_ordinal >= 0),
    counters JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(counters) = 'object'),
    version BIGINT NOT NULL DEFAULT 1 CHECK (version > 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (run_id, partition_key),
    UNIQUE(run_id, job_name, partition_key, mapping_digest)
);

CREATE INDEX IF NOT EXISTS idx_channel_migration_checkpoints_run_fk
    ON channel_migration_checkpoints(run_id);

CREATE TABLE IF NOT EXISTS channel_migration_items (
    run_id UUID NOT NULL REFERENCES channel_migration_runs(id) ON DELETE RESTRICT,
    source_table VARCHAR(128) NOT NULL,
    source_key TEXT NOT NULL,
    source_user_id BIGINT,
    ordinal BIGINT NOT NULL CHECK (ordinal >= 0),
    depth INTEGER NOT NULL DEFAULT 0 CHECK (depth >= 0),
    parent_source_key TEXT,
    source_fingerprint CHAR(64) NOT NULL CHECK (source_fingerprint ~ '^[0-9a-f]{64}$'),
    expected JSONB NOT NULL CHECK (jsonb_typeof(expected) = 'object'),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'succeeded', 'quarantined', 'failed')),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    lease_owner VARCHAR(128),
    lease_until TIMESTAMPTZ,
    target_type VARCHAR(40),
    target_id BIGINT,
    last_error TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (run_id, source_table, source_key),
    UNIQUE(run_id, ordinal),
    CONSTRAINT channel_migration_item_lease_shape CHECK (
        (status = 'processing' AND lease_owner IS NOT NULL AND lease_until IS NOT NULL)
        OR (status <> 'processing')
    )
);

CREATE INDEX IF NOT EXISTS idx_channel_migration_items_claim
    ON channel_migration_items(run_id, status, depth, ordinal)
    WHERE status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS idx_channel_migration_items_lease
    ON channel_migration_items(status, lease_until)
    WHERE status = 'processing';

CREATE TABLE IF NOT EXISTS channel_migration_entity_map (
    source_table VARCHAR(128) NOT NULL,
    source_key TEXT NOT NULL,
    target_type VARCHAR(40) NOT NULL,
    target_id BIGINT NOT NULL,
    mapping_digest CHAR(64) NOT NULL CHECK (mapping_digest ~ '^[0-9a-f]{64}$'),
    source_fingerprint CHAR(64) NOT NULL CHECK (source_fingerprint ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_table, source_key, target_type),
    UNIQUE(target_type, target_id)
);

CREATE TABLE IF NOT EXISTS channel_migration_shadow_diffs (
    run_id UUID NOT NULL REFERENCES channel_migration_runs(id) ON DELETE RESTRICT,
    diff_type VARCHAR(64) NOT NULL,
    source_table VARCHAR(128) NOT NULL,
    source_key TEXT NOT NULL,
    reason_code VARCHAR(64) NOT NULL,
    expected JSONB,
    actual JSONB,
    details JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object'),
    diff_fingerprint CHAR(64) NOT NULL CHECK (diff_fingerprint ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (run_id, diff_type, source_table, source_key, reason_code)
);

CREATE INDEX IF NOT EXISTS idx_channel_migration_shadow_diffs_run_fk
    ON channel_migration_shadow_diffs(run_id, diff_type, reason_code);

ALTER TABLE channel_migration_quarantine
    ADD COLUMN IF NOT EXISTS first_run_id UUID REFERENCES channel_migration_runs(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS last_seen_run_id UUID REFERENCES channel_migration_runs(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS occurrence_count BIGINT NOT NULL DEFAULT 1 CHECK (occurrence_count > 0);

CREATE INDEX IF NOT EXISTS idx_channel_migration_quarantine_first_run_fk
    ON channel_migration_quarantine(first_run_id) WHERE first_run_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_channel_migration_quarantine_last_run_fk
    ON channel_migration_quarantine(last_seen_run_id) WHERE last_seen_run_id IS NOT NULL;
