-- 074 down: Remove is_system_admin column.
-- Note: This migration is only safe to run before the data migration (075).

DROP INDEX IF EXISTS idx_users_is_system_admin;
ALTER TABLE users DROP COLUMN IF EXISTS is_system_admin;
