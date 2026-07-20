DROP TABLE IF EXISTS work_order_templates;
DROP INDEX IF EXISTS uq_work_order_events_operator_idempotency;
ALTER TABLE work_order_events DROP COLUMN IF EXISTS idempotency_key;
DROP INDEX IF EXISTS uq_work_orders_creator_idempotency;
ALTER TABLE work_orders
    DROP COLUMN IF EXISTS escalated_at,
    DROP COLUMN IF EXISTS request_hash,
    DROP COLUMN IF EXISTS idempotency_key,
    DROP COLUMN IF EXISTS lock_version;
