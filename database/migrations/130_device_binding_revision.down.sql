DROP TRIGGER IF EXISTS devices_binding_revision ON devices;
DROP FUNCTION IF EXISTS record_device_binding_revision();
-- Retain binding_state_revisions: cache monotonicity survives rollbacks.
-- The old services ignore this table; never drop it in a live deployment.
