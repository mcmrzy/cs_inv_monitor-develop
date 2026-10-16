DROP INDEX IF EXISTS idx_device_upgrades_pending_delivery;
ALTER TABLE device_upgrades DROP COLUMN IF EXISTS last_dispatched_at;
