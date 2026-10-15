-- Pending commands are recovered from the durable task, with a bounded resend
-- interval. NULL means that delivery has not yet been attempted while online.
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS last_dispatched_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_device_upgrades_pending_delivery
    ON device_upgrades (last_dispatched_at, device_sn) WHERE status = 'pending';
