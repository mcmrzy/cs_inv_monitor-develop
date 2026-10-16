-- Hardware records remain historical metadata. Upgrade eligibility is based on
-- the real device model, target module and published firmware, without requiring
-- registry verification, board scopes, evidence or a compatibility window.
CREATE OR REPLACE FUNCTION snapshot_trusted_ota_identity() RETURNS trigger AS $$
DECLARE d devices%ROWTYPE; r device_hardware_registry%ROWTYPE;
        m device_hardware_modules%ROWTYPE; f firmware_versions%ROWTYPE;
BEGIN
 IF NEW.target_chip IS NULL OR NEW.target_chip NOT IN ('arm','dsp','esp','bms') THEN
  RAISE EXCEPTION 'invalid target_chip';
 END IF;
 SELECT * INTO d FROM devices WHERE sn=NEW.device_sn AND deleted_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'device_not_found'; END IF;
 SELECT * INTO f FROM firmware_versions WHERE id=NEW.firmware_id FOR SHARE;
 IF NOT FOUND OR f.release_status<>'published' OR f.status<>1 THEN
  RAISE EXCEPTION 'firmware_not_published';
 END IF;
 IF f.model IS DISTINCT FROM d.model OR f.target_chip IS DISTINCT FROM NEW.target_chip THEN
  RAISE EXCEPTION 'firmware_incompatible';
 END IF;
 NEW.identity_revision:=NULL; NEW.module_revision:=NULL;
 NEW.board_code:=''; NEW.board_uid:='';
 SELECT * INTO r FROM device_hardware_registry WHERE sn=NEW.device_sn;
 IF FOUND THEN
  NEW.identity_revision:=r.identity_revision;
  SELECT * INTO m FROM device_hardware_modules WHERE sn=NEW.device_sn AND target_chip=NEW.target_chip;
  IF FOUND THEN
   NEW.module_revision:=m.module_revision;
   NEW.board_code:=COALESCE(m.board_code,''); NEW.board_uid:=COALESCE(m.board_uid,'');
  END IF;
 END IF;
 RETURN NEW;
END; $$ LANGUAGE plpgsql;
