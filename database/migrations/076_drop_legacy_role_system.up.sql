-- Migration: Drop legacy role system columns and tables
-- This migration removes all remnants of the old numeric-role-based permission system.
-- Prerequisite: Migration 074 (is_system_admin) and 075 (organizations) must have run.

BEGIN;

-- 1. Drop all legacy views that depend on users.role / users.parent_id
DROP VIEW IF EXISTS v_user_station_access CASCADE;
DROP VIEW IF EXISTS v_user_hierarchy CASCADE;
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
-- Users can access devices owned by members of their org and descendant orgs.
-- System admins have access to all devices.
CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
SELECT DISTINCT
    viewer_om.user_id,
    d.sn AS device_sn
FROM organization_memberships viewer_om
JOIN organization_closure oc ON oc.ancestor_id = viewer_om.organization_id
JOIN organization_memberships owner_om
    ON owner_om.organization_id = oc.descendant_id
    AND owner_om.status = 'active'
JOIN devices d ON d.user_id = owner_om.user_id AND d.deleted_at IS NULL
WHERE viewer_om.status = 'active'
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
'Organization-based device access view: users can access devices owned by members of their organization and descendant organizations. System admins have access to all devices.';

-- 5. Recreate v_user_station_access based on organization hierarchy
-- Users can access stations owned by members of their org and descendant orgs.
-- System admins have access to all stations.
CREATE OR REPLACE VIEW v_user_station_access (user_id, station_id) AS
SELECT DISTINCT
    viewer_om.user_id,
    s.id AS station_id
FROM organization_memberships viewer_om
JOIN organization_closure oc ON oc.ancestor_id = viewer_om.organization_id
JOIN organization_memberships owner_om
    ON owner_om.organization_id = oc.descendant_id
    AND owner_om.status = 'active'
JOIN stations s ON s.user_id = owner_om.user_id AND s.deleted_at IS NULL
WHERE viewer_om.status = 'active'
UNION
-- System admins have access to all stations
SELECT
    u.id AS user_id,
    s.id AS station_id
FROM users u
CROSS JOIN stations s
WHERE u.is_system_admin = true
  AND u.deleted_at IS NULL
  AND s.deleted_at IS NULL;

COMMENT ON VIEW v_user_station_access IS
'Organization-based station access view: users can access stations owned by members of their organization and descendant organizations. System admins have access to all stations.';

-- 6. Recreate v_user_hierarchy based on organization closure
-- Maps each user to all users in their org and descendant orgs (replaces parent_id tree).
-- depth=0 means self, depth>0 means org-level descendant.
CREATE OR REPLACE VIEW v_user_hierarchy (ancestor_id, descendant_id, depth) AS
SELECT DISTINCT
    actor_om.user_id AS ancestor_id,
    descendant_om.user_id AS descendant_id,
    CASE WHEN actor_om.organization_id = descendant_om.organization_id THEN 0
         ELSE oc.depth
    END AS depth
FROM organization_memberships actor_om
JOIN organization_closure oc ON oc.ancestor_id = actor_om.organization_id
JOIN organization_memberships descendant_om
    ON descendant_om.organization_id = oc.descendant_id
    AND descendant_om.status = 'active'
WHERE actor_om.status = 'active';

COMMENT ON VIEW v_user_hierarchy IS
'Organization-based user hierarchy view: maps each user to all users within their organization and descendant organizations. Replaces the legacy parent_id recursive tree.';

COMMIT;
