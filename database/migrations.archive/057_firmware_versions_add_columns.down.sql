ALTER TABLE firmware_versions DROP COLUMN IF EXISTS updated_at;
ALTER TABLE firmware_versions DROP COLUMN IF EXISTS main_version;
ALTER TABLE firmware_versions DROP COLUMN IF EXISTS target_chip;
ALTER TABLE firmware_versions DROP COLUMN IF EXISTS uploaded_by;
ALTER TABLE firmware_versions DROP COLUMN IF EXISTS file_sha256;
