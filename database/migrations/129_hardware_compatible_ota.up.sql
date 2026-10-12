-- Explicit hardware compatibility; legacy firmware stays unassigned until audited backfill.
CREATE TABLE IF NOT EXISTS device_hardware_versions (
    model VARCHAR(100) NOT NULL,
    version VARCHAR(50) NOT NULL CHECK (version = upper(btrim(version)) AND version ~ '^[A-Z0-9][A-Z0-9._-]{0,49}$'),
    description VARCHAR(500) NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (model, version)
);

INSERT INTO device_hardware_versions (model, version)
SELECT DISTINCT model, upper(btrim(hardware_version)) FROM devices
WHERE model IS NOT NULL AND btrim(model) <> '' AND deleted_at IS NULL
  AND upper(btrim(hardware_version)) ~ '^[A-Z0-9][A-Z0-9._-]{0,49}$'
ON CONFLICT DO NOTHING;

ALTER TABLE firmware_versions DROP CONSTRAINT IF EXISTS firmware_versions_model_version_key;
DROP INDEX IF EXISTS uq_firmware_versions_model_chip_version;
DROP INDEX IF EXISTS uq_firmware_model_target_version;
CREATE UNIQUE INDEX IF NOT EXISTS uq_firmware_hardware_identity
    ON firmware_versions (id, model, target_chip, version);

CREATE TABLE IF NOT EXISTS firmware_hardware_versions (
    firmware_id BIGINT NOT NULL,
    model VARCHAR(100) NOT NULL,
    target_chip VARCHAR(50) NOT NULL,
    firmware_version VARCHAR(50) NOT NULL,
    hardware_version VARCHAR(50) NOT NULL,
    PRIMARY KEY (firmware_id, hardware_version),
    FOREIGN KEY (firmware_id, model, target_chip, firmware_version)
        REFERENCES firmware_versions (id, model, target_chip, version) ON DELETE CASCADE,
    FOREIGN KEY (model, hardware_version) REFERENCES device_hardware_versions (model, version),
    CONSTRAINT uq_firmware_hardware_software UNIQUE (model, target_chip, firmware_version, hardware_version)
);

ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS hardware_version VARCHAR(50) NOT NULL DEFAULT '';
-- Historical rows deliberately remain blank: current hardware is not evidence of past hardware.
CREATE OR REPLACE FUNCTION snapshot_ota_hardware_version() RETURNS trigger AS $$
BEGIN
    NEW.hardware_version := COALESCE((SELECT hardware_version FROM devices WHERE sn = NEW.device_sn), '');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_snapshot_ota_hardware ON device_upgrades;
CREATE TRIGGER trg_snapshot_ota_hardware BEFORE INSERT ON device_upgrades
    FOR EACH ROW EXECUTE FUNCTION snapshot_ota_hardware_version();
