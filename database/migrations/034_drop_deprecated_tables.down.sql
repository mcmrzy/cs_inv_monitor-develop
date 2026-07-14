-- =====================================================
-- Migration 034 (DOWN): Restore deprecated table structures
-- =====================================================
-- Recreates the dropped tables with their original structure.
-- Only structure is restored — data is NOT recovered.
-- Sources: database/backup-schema-before-023-20260713-190544.sql
--          database/数据库说明文档.html
-- =====================================================

-- 1. Restore ota_records
CREATE TABLE IF NOT EXISTS ota_records (
    id              BIGSERIAL PRIMARY KEY,
    device_sn       VARCHAR(50) NOT NULL,
    firmware_id     BIGINT NOT NULL,
    old_version     VARCHAR(50),
    new_version     VARCHAR(50),
    status          VARCHAR(20) NOT NULL,   -- pending/downloading/upgrading/success/failed
    progress        INTEGER DEFAULT 0,
    error_message   TEXT,
    started_at      TIMESTAMP,
    completed_at    TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Restore device_model_protocol
CREATE TABLE IF NOT EXISTS device_model_protocol (
    id            BIGSERIAL PRIMARY KEY,
    model_id      INTEGER NOT NULL,
    topic_pattern VARCHAR(200) NOT NULL,
    parse_type    VARCHAR(32) NOT NULL DEFAULT 'json',
    parse_config  JSONB,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (model_id, topic_pattern)
);
CREATE INDEX IF NOT EXISTS idx_model_protocol_model ON device_model_protocol(model_id);
ALTER TABLE device_model_protocol
    ADD CONSTRAINT device_model_protocol_model_id_fkey
    FOREIGN KEY (model_id) REFERENCES device_models(id) ON DELETE CASCADE;

-- 3. Restore device_model_field (singular)
CREATE TABLE IF NOT EXISTS device_model_field (
    id            BIGSERIAL PRIMARY KEY,
    model_id      INTEGER NOT NULL,
    field_key     VARCHAR(64) NOT NULL,
    field_name    VARCHAR(128) NOT NULL,
    field_type    VARCHAR(32) NOT NULL,
    unit          VARCHAR(32),
    sort          INTEGER NOT NULL DEFAULT 0,
    is_show       BOOLEAN NOT NULL DEFAULT TRUE,
    is_control    BOOLEAN NOT NULL DEFAULT FALSE,
    parse_rule    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    group_name    VARCHAR(64) DEFAULT '',
    control_params JSONB DEFAULT '{}'::jsonb,
    UNIQUE (model_id, field_key)
);
CREATE INDEX IF NOT EXISTS idx_model_field_model ON device_model_field(model_id);
ALTER TABLE device_model_field
    ADD CONSTRAINT device_model_field_model_id_fkey
    FOREIGN KEY (model_id) REFERENCES device_models(id) ON DELETE CASCADE;
