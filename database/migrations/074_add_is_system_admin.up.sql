-- 074: Add is_system_admin column to users table.
-- Replaces the role=0 super-admin bypass with an explicit boolean flag.
-- This is the first step of the legacy role system removal.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_system_admin BOOLEAN NOT NULL DEFAULT false;

-- Migrate existing super-admins (role=0) to the new flag.
UPDATE users SET is_system_admin = true WHERE role = 0 AND deleted_at IS NULL;

COMMENT ON COLUMN users.is_system_admin IS '系统超级管理员标记，绕过所有权限检查。替代旧 role=0 逻辑。';

-- Add index for fast lookups.
CREATE INDEX IF NOT EXISTS idx_users_is_system_admin ON users(is_system_admin) WHERE is_system_admin = true AND deleted_at IS NULL;
