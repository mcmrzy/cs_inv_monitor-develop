-- Trusted identities are not backfilled from device reports or legacy hardware strings.
CREATE TABLE IF NOT EXISTS hardware_board_types (
 model VARCHAR(100) NOT NULL CHECK (btrim(model) <> ''),
 target_chip VARCHAR(50) NOT NULL CHECK (target_chip IN ('arm','dsp','esp','bms')),
 board_code VARCHAR(50) NOT NULL CHECK (board_code ~ '^[A-Z0-9][A-Z0-9._-]{0,49}$'),
 description VARCHAR(500) NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 PRIMARY KEY (model,target_chip,board_code)
);
CREATE TABLE IF NOT EXISTS device_hardware_registry (
 sn VARCHAR(64) PRIMARY KEY, verified_model VARCHAR(100) NOT NULL DEFAULT '',
 identity_state VARCHAR(30) NOT NULL DEFAULT 'unverified' CHECK (identity_state IN ('unverified','verified','conflict','service_pending','retired')),
 identity_revision BIGINT NOT NULL DEFAULT 0 CHECK (identity_revision>=0), frozen BOOLEAN NOT NULL DEFAULT FALSE,
 source VARCHAR(100) NOT NULL DEFAULT '', evidence_ref VARCHAR(500) NOT NULL DEFAULT '',
 verified_by BIGINT NOT NULL DEFAULT 0, verified_at TIMESTAMPTZ, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 UNIQUE(sn,verified_model)
);
CREATE TABLE IF NOT EXISTS device_hardware_modules (
 sn VARCHAR(64) NOT NULL, verified_model VARCHAR(100) NOT NULL, target_chip VARCHAR(50) NOT NULL CHECK (target_chip IN ('arm','dsp','esp','bms')),
 board_code VARCHAR(50), board_uid VARCHAR(128) NOT NULL DEFAULT '', state VARCHAR(30) NOT NULL CHECK (state IN ('verified','absent','conflict','unverified')),
 module_revision BIGINT NOT NULL CHECK (module_revision>0),
 protection_level VARCHAR(30) NOT NULL DEFAULT 'registry_verified' CHECK (protection_level IN ('registry_verified','device_enrolled','device_enforced')),
 PRIMARY KEY(sn,target_chip), FOREIGN KEY(sn,verified_model) REFERENCES device_hardware_registry(sn,verified_model),
 FOREIGN KEY(verified_model,target_chip,board_code) REFERENCES hardware_board_types(model,target_chip,board_code),
 CHECK ((state='absent' AND board_code IS NULL AND board_uid='') OR (state<>'absent' AND board_code IS NOT NULL))
);
CREATE TABLE IF NOT EXISTS device_hardware_history (
 id BIGSERIAL PRIMARY KEY, sn VARCHAR(64) NOT NULL REFERENCES device_hardware_registry(sn), action VARCHAR(30) NOT NULL,
 previous_revision BIGINT NOT NULL, identity_revision BIGINT NOT NULL, actor BIGINT NOT NULL, reason TEXT NOT NULL,
 evidence_ref VARCHAR(500) NOT NULL, before_snapshot JSONB NOT NULL, after_snapshot JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_hardware_history_sn ON device_hardware_history(sn,id DESC);
CREATE TABLE IF NOT EXISTS device_hardware_observations (
 id BIGSERIAL PRIMARY KEY, sn VARCHAR(64) NOT NULL, reported_model VARCHAR(100) NOT NULL DEFAULT '',
 scope VARCHAR(30) NOT NULL CHECK(scope IN ('legacy_system','arm','dsp','esp','bms')),
 reported_board_code VARCHAR(100) NOT NULL DEFAULT '', reported_board_uid VARCHAR(128) NOT NULL DEFAULT '',
 source VARCHAR(100) NOT NULL, reported_at TIMESTAMPTZ NOT NULL, received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_hardware_observation_latest ON device_hardware_observations(sn,scope,reported_at DESC,id DESC);
CREATE TABLE IF NOT EXISTS hardware_import_batches (
 id BIGSERIAL PRIMARY KEY, actor BIGINT NOT NULL, file_sha256 VARCHAR(64) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 UNIQUE(actor,file_sha256)
);
CREATE TABLE IF NOT EXISTS hardware_import_rows (
 batch_id BIGINT NOT NULL REFERENCES hardware_import_batches(id), row_index INT NOT NULL CHECK(row_index>0),
 row_data JSONB NOT NULL, valid BOOLEAN NOT NULL, errors JSONB NOT NULL DEFAULT '[]', status VARCHAR(30) NOT NULL,
 PRIMARY KEY(batch_id,row_index)
);
CREATE TABLE IF NOT EXISTS hardware_import_commits (
 batch_id BIGINT NOT NULL REFERENCES hardware_import_batches(id), idempotency_key VARCHAR(100) NOT NULL, request_digest VARCHAR(64) NOT NULL,
 PRIMARY KEY(batch_id,idempotency_key)
);
CREATE TABLE IF NOT EXISTS firmware_board_types (
 firmware_id BIGINT NOT NULL, model VARCHAR(100) NOT NULL, target_chip VARCHAR(50) NOT NULL, firmware_version VARCHAR(50) NOT NULL, board_code VARCHAR(50) NOT NULL,
 PRIMARY KEY(firmware_id,board_code),
 FOREIGN KEY(firmware_id,model,target_chip,firmware_version) REFERENCES firmware_versions(id,model,target_chip,version) ON DELETE CASCADE,
 FOREIGN KEY(model,target_chip,board_code) REFERENCES hardware_board_types(model,target_chip,board_code),
 CONSTRAINT uq_firmware_board_software UNIQUE(model,target_chip,firmware_version,board_code)
);
CREATE TABLE IF NOT EXISTS ota_compatibility_windows (
 id BIGSERIAL PRIMARY KEY, sn VARCHAR(64) NOT NULL REFERENCES device_hardware_registry(sn), target_chip VARCHAR(50) NOT NULL CHECK(target_chip IN ('arm','dsp','esp','bms')),
 firmware_id BIGINT NOT NULL REFERENCES firmware_versions(id) ON DELETE CASCADE,
 file_sha256 VARCHAR(64) NOT NULL CHECK(file_sha256 ~ '^[a-f0-9]{64}$'), expires_at TIMESTAMPTZ NOT NULL,
 identity_revision BIGINT NOT NULL CHECK(identity_revision>0), reason TEXT NOT NULL CHECK(btrim(reason)<>''),
 actor BIGINT NOT NULL, evidence_ref VARCHAR(500) NOT NULL CHECK(btrim(evidence_ref)<>''), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ota_compat_window ON ota_compatibility_windows(sn,target_chip,firmware_id,expires_at);
CREATE TABLE IF NOT EXISTS firmware_board_scope_audits (
 id BIGSERIAL PRIMARY KEY, firmware_id BIGINT NOT NULL REFERENCES firmware_versions(id), actor BIGINT NOT NULL,
 reason TEXT NOT NULL, evidence_ref VARCHAR(500) NOT NULL, before_codes JSONB NOT NULL, after_codes JSONB NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS reported_model VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS reported_hardware_version VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS identity_revision BIGINT;
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS module_revision BIGINT;
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS board_code VARCHAR(50) NOT NULL DEFAULT '';
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS board_uid VARCHAR(128) NOT NULL DEFAULT '';
-- Historical rows remain unsnapshotted. Dispatch must reject them rather than invent identity.
CREATE OR REPLACE FUNCTION snapshot_trusted_ota_identity() RETURNS trigger AS $$
DECLARE r device_hardware_registry%ROWTYPE; m device_hardware_modules%ROWTYPE; f firmware_versions%ROWTYPE;
BEGIN
 IF NEW.source='local' THEN RAISE EXCEPTION 'device_protection_required'; END IF;
 SELECT * INTO r FROM device_hardware_registry WHERE sn=NEW.device_sn FOR SHARE;
 IF NOT FOUND OR r.identity_state<>'verified' OR r.frozen THEN RAISE EXCEPTION 'identity_unverified or identity_conflict'; END IF;
 IF NOT EXISTS(SELECT 1 FROM devices WHERE sn=NEW.device_sn AND deleted_at IS NULL) THEN RAISE EXCEPTION 'device_not_found'; END IF;
 IF FOUND THEN
  SELECT * INTO m FROM device_hardware_modules WHERE sn=NEW.device_sn AND target_chip=NEW.target_chip FOR SHARE;
  IF NOT FOUND OR m.state<>'verified' THEN RAISE EXCEPTION 'module_identity_missing or module_absent'; END IF;
  SELECT * INTO f FROM firmware_versions WHERE id=NEW.firmware_id FOR SHARE;
  IF NOT FOUND OR f.release_status<>'published' OR f.status<>1 THEN RAISE EXCEPTION 'firmware_not_published'; END IF;
  IF f.model<>r.verified_model OR f.target_chip<>NEW.target_chip OR NOT EXISTS(SELECT 1 FROM firmware_board_types WHERE firmware_id=f.id AND model=r.verified_model AND target_chip=m.target_chip AND board_code=m.board_code) THEN RAISE EXCEPTION 'firmware_incompatible'; END IF;
  IF length(COALESCE(f.file_sha256,''))<>64 OR NOT EXISTS(SELECT 1 FROM ota_compatibility_windows w WHERE w.sn=r.sn AND w.target_chip=m.target_chip AND w.firmware_id=f.id AND w.file_sha256=f.file_sha256 AND w.identity_revision=r.identity_revision AND w.expires_at>NOW()) THEN RAISE EXCEPTION 'device_protection_required'; END IF;
  NEW.identity_revision:=r.identity_revision;
  NEW.module_revision:=m.module_revision;
  NEW.board_code:=COALESCE(m.board_code,''); NEW.board_uid:=COALESCE(m.board_uid,'');
 ELSE
  NEW.identity_revision:=NULL; NEW.module_revision:=NULL; NEW.board_code:=''; NEW.board_uid:='';
 END IF;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_snapshot_trusted_ota_identity ON device_upgrades;
CREATE TRIGGER trg_snapshot_trusted_ota_identity BEFORE INSERT ON device_upgrades FOR EACH ROW EXECUTE FUNCTION snapshot_trusted_ota_identity();
