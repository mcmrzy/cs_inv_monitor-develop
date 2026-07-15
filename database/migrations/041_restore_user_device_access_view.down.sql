-- Restore the legacy relation-only view shape. The two-column API remains
-- available so rolling back application code does not leave a missing object.

CREATE OR REPLACE VIEW v_user_device_access (user_id, device_sn) AS
SELECT udr.user_id, udr.device_sn
FROM user_device_rel udr;

COMMENT ON VIEW v_user_device_access IS
    'Legacy delegated device access only';
