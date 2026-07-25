-- 075 down: This data migration is not safely reversible.
-- Rolling back would require deleting organizations, memberships, role
-- assignments, and permission grants created by the up migration, but
-- distinguishing migrated data from manually created data is not reliable.
--
-- To roll back, restore the database from a backup taken before migration 075.

RAISE EXCEPTION 'Migration 075 (migrate_users_to_organizations) is not reversible. Restore from backup to roll back.';
