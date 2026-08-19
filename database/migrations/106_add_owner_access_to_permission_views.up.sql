-- 自助注册用户的数据访问权限修复：
-- v_user_station_access / v_user_device_access 原先只有"组织成员"与
-- "系统管理员"两个分支，纯注册用户（未加入任何组织、非管理员）即使
-- 创建了电站、绑定了设备，也会在 GET /api/v1/stations/:id、
-- GET /api/v1/stations/:id/weather 等接口被拒（403 permission denied）。
-- 新增 owner 直查分支：资源持有者（user_id）天然可访问自己的电站/设备；
-- 组织体系继续管理跨用户共享与管理范围；Assign 转让通过更新 user_id
-- 自动把 owner 权限转移给新持有者，语义不变。

CREATE OR REPLACE VIEW v_user_station_access (user_id, station_id) AS
-- Owner branch: users can always access stations they own
SELECT
    s.user_id,
    s.id AS station_id
FROM stations s
WHERE s.deleted_at IS NULL
UNION
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
'Organization-based station access view: owners can always access their own stations; users can access stations owned by members of their organization and descendant organizations. System admins have access to all stations.';

CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
-- Owner branch: users can always access devices they own
SELECT
    d.user_id,
    d.sn AS device_sn
FROM devices d
WHERE d.deleted_at IS NULL
  AND d.sn IS NOT NULL
UNION
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
  AND d.deleted_at IS NULL
  AND d.sn IS NOT NULL;

COMMENT ON VIEW v_user_device_access IS
'Organization-based device access view: owners can always access their own devices; users can access devices owned by members of their organization and descendant organizations. System admins have access to all devices.';
