-- Unify organization, device and station visibility on the develop schema.
-- Existing user_device_rel data remains authoritative and is never recreated.

CREATE OR REPLACE VIEW v_user_hierarchy AS
WITH RECURSIVE hierarchy AS (
    SELECT u.id AS ancestor_id,
           u.id AS descendant_id,
           0 AS depth,
           ARRAY[u.id]::BIGINT[] AS path
    FROM users u
    WHERE u.deleted_at IS NULL

    UNION ALL

    SELECT h.ancestor_id,
           child.id AS descendant_id,
           h.depth + 1,
           h.path || child.id
    FROM hierarchy h
    JOIN users child ON child.parent_id = h.descendant_id
    WHERE child.deleted_at IS NULL
      AND NOT child.id = ANY(h.path)
      AND h.depth < 32
)
SELECT ancestor_id, descendant_id, depth
FROM hierarchy;

CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
SELECT DISTINCT access.user_id, access.device_sn
FROM (
    SELECT actor.id, device.sn
    FROM users actor
    JOIN devices device ON TRUE
    WHERE actor.role = 0
      AND actor.deleted_at IS NULL
      AND device.deleted_at IS NULL

    UNION

    SELECT actor.id, device.sn
    FROM users actor
    JOIN v_user_hierarchy hierarchy ON hierarchy.ancestor_id = actor.id
    JOIN devices device
      ON device.user_id = hierarchy.descendant_id
      OR device.installer_id = hierarchy.descendant_id
    WHERE actor.role BETWEEN 1 AND 3
      AND actor.deleted_at IS NULL
      AND device.deleted_at IS NULL

    UNION

    SELECT actor.id, device.sn
    FROM users actor
    JOIN v_user_hierarchy hierarchy ON hierarchy.ancestor_id = actor.id
    JOIN user_device_rel relation ON relation.user_id = hierarchy.descendant_id
    JOIN devices device ON device.sn = relation.device_sn
    WHERE actor.role BETWEEN 1 AND 3
      AND actor.deleted_at IS NULL
      AND device.deleted_at IS NULL

    UNION

    SELECT installer.id, device.sn
    FROM users installer
    JOIN devices device
      ON device.user_id = installer.id OR device.installer_id = installer.id
    WHERE installer.role = 4
      AND installer.deleted_at IS NULL
      AND device.deleted_at IS NULL

    UNION

    SELECT installer.id, device.sn
    FROM users installer
    JOIN user_device_rel relation ON relation.user_id = installer.id
    JOIN devices device ON device.sn = relation.device_sn
    WHERE installer.role = 4
      AND installer.deleted_at IS NULL
      AND device.deleted_at IS NULL

    UNION

    SELECT owner.id, device.sn
    FROM users owner
    JOIN devices device ON device.user_id = owner.id
    WHERE owner.role = 5
      AND owner.deleted_at IS NULL
      AND device.deleted_at IS NULL
) AS access(user_id, device_sn);

CREATE OR REPLACE VIEW v_user_station_access (user_id, station_id) AS
SELECT DISTINCT access.user_id, access.station_id
FROM (
    SELECT actor.id, station.id
    FROM users actor
    JOIN stations station ON TRUE
    WHERE actor.role = 0
      AND actor.deleted_at IS NULL
      AND station.deleted_at IS NULL

    UNION

    SELECT actor.id, station.id
    FROM users actor
    JOIN v_user_hierarchy hierarchy ON hierarchy.ancestor_id = actor.id
    JOIN stations station ON station.user_id = hierarchy.descendant_id
    WHERE actor.role BETWEEN 1 AND 3
      AND actor.deleted_at IS NULL
      AND station.deleted_at IS NULL

    UNION

    SELECT installer.id, station.id
    FROM users installer
    JOIN stations station ON station.user_id = installer.id
    WHERE installer.role = 4
      AND installer.deleted_at IS NULL
      AND station.deleted_at IS NULL

    UNION

    SELECT installer.id, station.id
    FROM users installer
    JOIN devices device ON device.installer_id = installer.id
    JOIN stations station ON station.id = device.station_id
    WHERE installer.role = 4
      AND installer.deleted_at IS NULL
      AND device.deleted_at IS NULL
      AND station.deleted_at IS NULL

    UNION

    SELECT owner.id, station.id
    FROM users owner
    JOIN stations station ON station.user_id = owner.id
    WHERE owner.role = 5
      AND owner.deleted_at IS NULL
      AND station.deleted_at IS NULL
) AS access(user_id, station_id);
