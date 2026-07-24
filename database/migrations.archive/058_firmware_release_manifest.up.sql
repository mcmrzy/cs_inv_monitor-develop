ALTER TABLE firmware_versions
    ADD COLUMN IF NOT EXISTS security_version BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS release_signature VARCHAR(88) NOT NULL DEFAULT '';

ALTER TABLE firmware_versions
    ADD CONSTRAINT firmware_security_version_uint32
        CHECK (security_version >= 0 AND security_version <= 4294967295);
