ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS firmware_security_version_uint32,
    DROP COLUMN IF EXISTS release_signature,
    DROP COLUMN IF EXISTS security_version;
