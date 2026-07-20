DROP VIEW IF EXISTS v_user_station_access;

-- Restore the pre-059 canonical owner/delegation contract without deleting data.
CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
SELECT device.user_id, device.sn
FROM devices device
WHERE device.deleted_at IS NULL
UNION
SELECT relation.user_id, device.sn
FROM user_device_rel relation
JOIN devices device ON device.sn = relation.device_sn
WHERE device.deleted_at IS NULL;

DROP VIEW IF EXISTS v_user_hierarchy;
