-- Extend the existing UUID work-order model; never recreate it as BIGSERIAL.
ALTER TABLE work_orders
    ADD COLUMN IF NOT EXISTS lock_version BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128),
    ADD COLUMN IF NOT EXISTS request_hash VARCHAR(64),
    ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_orders_creator_idempotency
    ON work_orders(creator_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

ALTER TABLE work_order_events
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_order_events_operator_idempotency
    ON work_order_events(operator_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS work_order_templates (
    id BIGSERIAL PRIMARY KEY,
    template_type VARCHAR(40) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL,
    title_template VARCHAR(200) NOT NULL,
    description_template TEXT NOT NULL DEFAULT '',
    default_priority VARCHAR(16) NOT NULL DEFAULT 'medium'
        CHECK (default_priority IN ('low', 'medium', 'high', 'urgent')),
    default_sla_hours INTEGER NOT NULL DEFAULT 24
        CHECK (default_sla_hours BETWEEN 1 AND 8760),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
