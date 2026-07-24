CREATE TABLE IF NOT EXISTS work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','closed')),
    priority VARCHAR(16) NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
    device_sn VARCHAR(64),
    creator_id BIGINT NOT NULL,
    assigned_to BIGINT,
    template_type VARCHAR(40),
    resolution TEXT,
    sla_deadline TIMESTAMPTZ,
    sla_overdue_count INTEGER NOT NULL DEFAULT 0,
    escalated_count INTEGER NOT NULL DEFAULT 0,
    resolved_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_orders_status ON work_orders(status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_work_orders_people ON work_orders(creator_id, assigned_to);
CREATE INDEX IF NOT EXISTS idx_work_orders_device ON work_orders(device_sn) WHERE device_sn IS NOT NULL;

CREATE TABLE IF NOT EXISTS work_order_events (
    id BIGSERIAL PRIMARY KEY,
    work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    status VARCHAR(24) NOT NULL,
    operator_id BIGINT NOT NULL,
    remark TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS work_order_attachments (
    id BIGSERIAL PRIMARY KEY,
    work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,
    uploaded_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
