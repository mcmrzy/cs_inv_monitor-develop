-- Restore the old key only when no divergent hardware builds exist. A conflict aborts the rollback.
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM firmware_versions GROUP BY model, target_chip, version HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Cannot roll back hardware OTA: multiple hardware builds share a software version';
    END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_firmware_model_target_version ON firmware_versions (model, target_chip, version);
DROP TRIGGER IF EXISTS trg_snapshot_ota_hardware ON device_upgrades;
DROP FUNCTION IF EXISTS snapshot_ota_hardware_version();
ALTER TABLE device_upgrades DROP COLUMN IF EXISTS hardware_version;
DROP TABLE IF EXISTS firmware_hardware_versions;
DROP INDEX IF EXISTS uq_firmware_hardware_identity;
DROP TABLE IF EXISTS device_hardware_versions;
