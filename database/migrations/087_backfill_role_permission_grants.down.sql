-- 087 down: This data backfill is not safely reversible.
-- Rolling back would require deleting permission grants created by the up
-- migration, but distinguishing migrated grants from manually configured
-- grants (e.g. via the admin role-permission UI) is not reliable.
--
-- To roll back, restore the database from a backup taken before migration 087.

RAISE EXCEPTION 'Migration 087 (backfill_role_permission_grants) is not reversible. Restore from backup to roll back.';
