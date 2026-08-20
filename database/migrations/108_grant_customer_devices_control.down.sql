-- 108 down: This data backfill is not safely reversible.
-- Rolling back would require deleting the devices:control grants of customer
-- role assignments, but distinguishing migrated grants from manually
-- configured grants (e.g. via the admin role-permission UI) is not reliable.
--
-- To roll back, restore the database from a backup taken before migration 108.

RAISE EXCEPTION 'Migration 108 (grant_customer_devices_control) is not reversible. Restore from backup to roll back.';
