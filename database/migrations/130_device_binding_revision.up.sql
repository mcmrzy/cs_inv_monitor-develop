-- Durable per-SN counters survive physical deletion and recreation.
CREATE TABLE IF NOT EXISTS binding_state_revisions (
    sn VARCHAR(64) PRIMARY KEY,
    revision BIGINT NOT NULL CHECK (revision > 0)
);
-- On re-enabling after a rollback, advance retained counters to account for
-- ownership changes made while the trigger was absent.
UPDATE binding_state_revisions SET revision=revision+1;
INSERT INTO binding_state_revisions(sn,revision) SELECT sn,1 FROM devices
ON CONFLICT(sn) DO NOTHING;

CREATE FUNCTION record_device_binding_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.sn IS NOT DISTINCT FROM OLD.sn
       AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id
       AND NEW.deleted_at IS NOT DISTINCT FROM OLD.deleted_at THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW.sn IS DISTINCT FROM OLD.sn) THEN
        INSERT INTO binding_state_revisions(sn,revision) VALUES(OLD.sn,1)
        ON CONFLICT(sn) DO UPDATE SET revision = binding_state_revisions.revision + 1;
    END IF;
    IF TG_OP != 'DELETE' THEN
        INSERT INTO binding_state_revisions(sn,revision) VALUES(NEW.sn,1)
        ON CONFLICT(sn) DO UPDATE SET revision = binding_state_revisions.revision + 1;
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$;
CREATE TRIGGER devices_binding_revision
AFTER INSERT OR DELETE OR UPDATE OF sn,user_id,deleted_at ON devices
FOR EACH ROW EXECUTE FUNCTION record_device_binding_revision();
