DROP INDEX IF EXISTS idx_firmware_versions_rollout;

ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS ck_firmware_rollout_type;
ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS ck_firmware_rollout_percent;

ALTER TABLE firmware_versions
    DROP COLUMN IF EXISTS rollback_to_firmware_id,
    DROP COLUMN IF EXISTS rollout_targets,
    DROP COLUMN IF EXISTS rollout_type,
    DROP COLUMN IF EXISTS rollout_percent;
