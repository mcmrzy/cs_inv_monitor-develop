-- Migration: Drop legacy role system columns and tables
-- This migration removes all remnants of the old numeric-role-based permission system.
-- Prerequisite: Migration 074 (is_system_admin) and 075 (organizations) must have run.

BEGIN;

-- 1. Drop the legacy v_user_device_access view (depends on users.parent_id)
DROP VIEW IF EXISTS v_user_device_access CASCADE;

-- 2. Drop legacy columns from users table
ALTER TABLE users DROP COLUMN IF EXISTS role;
ALTER TABLE users DROP COLUMN IF EXISTS parent_id;
ALTER TABLE users DROP COLUMN IF EXISTS device_limit;
ALTER TABLE users DROP COLUMN IF EXISTS user_limit;

-- 3. Drop legacy permission tables
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS admin_permissions;

-- 4. Recreate v_user_device_access based on organization hierarchy
-- The new view uses organization_memberships + organization_closure for access scope
CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
SELECT DISTINCT
    om.user_id,
    d.sn AS device_sn
FROM organization_memberships om
JOIN organizations o ON o.id = om.organization_id
JOIN organization_closure oc ON oc.ancestor_id = o.id
JOIN organizations child_org ON child_org.id = oc.descendant_id
LEFT JOIN devices d ON d.organization_id = child_org.id AND d.deleted_at IS NULL
WHERE om.deleted_at IS NULL
  AND o.deleted_at IS NULL
  AND d.sn IS NOT NULL
UNION
-- System admins have access to all devices
SELECT
    u.id AS user_id,
    d.sn AS device_sn
FROM users u
CROSS JOIN devices d
WHERE u.is_system_admin = true
  AND u.deleted_at IS NULL
  AND d.deleted_at IS NULL;

COMMENT ON VIEW v_user_device_access IS
'Organization-based device access view: users can access devices belonging to their organization and all descendant organizations. System admins have access to all devices.';

COMMIT;
