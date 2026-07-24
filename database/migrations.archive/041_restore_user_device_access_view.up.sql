-- 041: Restore the canonical user-to-device access view.
--
-- The legacy view only exposed delegated bindings in user_device_rel, so a
-- device's direct owner was missing. Some upgraded databases have no view at
-- all. Keep the public two-column contract and exclude soft-deleted devices
-- for both access paths.

CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
SELECT d.user_id, d.sn
FROM devices d
WHERE d.deleted_at IS NULL
UNION
SELECT udr.user_id, d.sn
FROM user_device_rel udr
JOIN devices d ON d.sn = udr.device_sn
WHERE d.deleted_at IS NULL;

COMMENT ON VIEW v_user_device_access IS
    'Canonical object-level device access: direct ownership plus delegated bindings, excluding soft-deleted devices';
