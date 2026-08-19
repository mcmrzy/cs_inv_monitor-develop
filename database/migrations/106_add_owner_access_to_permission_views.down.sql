-- 回滚：恢复 076_drop_legacy_role_system 的纯组织体系视图定义
-- （移除 owner 直查分支）。
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
