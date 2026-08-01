-- 088 down: This data fix is not safely reversible.
-- Rolling back would require restoring the original (mismatched) role codes and
-- their old permission grants, which are overwritten by the up migration.
--
-- To roll back, restore the database from a backup taken before migration 088.

RAISE EXCEPTION 'Migration 088 (fix_member_identity_roles) is not reversible. Restore from backup to roll back.';
