ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS template_type VARCHAR(50);
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS sla_deadline TIMESTAMP;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS sla_overdue_count INTEGER DEFAULT 0;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS attachments JSONB;
CREATE INDEX IF NOT EXISTS idx_wo_sla ON work_orders(sla_deadline);
CREATE INDEX IF NOT EXISTS idx_wo_status_priority ON work_orders(status, priority);
