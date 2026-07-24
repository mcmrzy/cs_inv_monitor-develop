-- 067: Persist the versions embedded in organization-bound access tokens.
-- Version increments are performed in the same transaction as the user,
-- membership, role or grant mutation so old access tokens fail immediately.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_version BIGINT;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE session_version IS NOT NULL AND session_version <= 0) THEN
        RAISE EXCEPTION 'users.session_version contains non-positive values';
    END IF;
END;
$$;
UPDATE users SET session_version=1 WHERE session_version IS NULL;
ALTER TABLE users ALTER COLUMN session_version SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN session_version SET NOT NULL;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_session_version_check;
ALTER TABLE users
    ADD CONSTRAINT users_session_version_check CHECK (session_version > 0) NOT VALID;
ALTER TABLE users VALIDATE CONSTRAINT users_session_version_check;

ALTER TABLE organization_memberships
    ADD COLUMN IF NOT EXISTS authorization_version BIGINT;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM organization_memberships WHERE authorization_version IS NOT NULL AND authorization_version <= 0) THEN
        RAISE EXCEPTION 'organization_memberships.authorization_version contains non-positive values';
    END IF;
END;
$$;
UPDATE organization_memberships SET authorization_version=1 WHERE authorization_version IS NULL;
ALTER TABLE organization_memberships ALTER COLUMN authorization_version SET DEFAULT 1;
ALTER TABLE organization_memberships ALTER COLUMN authorization_version SET NOT NULL;

ALTER TABLE organization_memberships
    DROP CONSTRAINT IF EXISTS organization_memberships_authorization_version_check;
ALTER TABLE organization_memberships
    ADD CONSTRAINT organization_memberships_authorization_version_check
        CHECK (authorization_version > 0) NOT VALID;
ALTER TABLE organization_memberships
    VALIDATE CONSTRAINT organization_memberships_authorization_version_check;

CREATE OR REPLACE FUNCTION bump_membership_authorization_version(
    p_root_tenant_id BIGINT,
    p_membership_id BIGINT
) RETURNS VOID AS $$
BEGIN
    UPDATE public.organization_memberships
       SET authorization_version=authorization_version+1,
           updated_at=NOW()
     WHERE root_tenant_id=p_root_tenant_id AND id=p_membership_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION bump_membership_authorization_version(BIGINT, BIGINT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION bump_role_assignment_authorization_version()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        PERFORM bump_membership_authorization_version(OLD.root_tenant_id, OLD.membership_id);
    END IF;
    IF TG_OP = 'INSERT' OR (
        TG_OP = 'UPDATE' AND
        (NEW.root_tenant_id, NEW.membership_id) IS DISTINCT FROM (OLD.root_tenant_id, OLD.membership_id)
    ) THEN
        PERFORM bump_membership_authorization_version(NEW.root_tenant_id, NEW.membership_id);
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION bump_permission_grant_authorization_version()
RETURNS TRIGGER AS $$
DECLARE
    assignment_root BIGINT;
    assignment_membership BIGINT;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        SELECT root_tenant_id,membership_id
          INTO assignment_root,assignment_membership
          FROM public.membership_role_assignments
         WHERE id=OLD.role_assignment_id;
        IF assignment_membership IS NOT NULL THEN
            PERFORM bump_membership_authorization_version(assignment_root, assignment_membership);
        END IF;
    END IF;
    IF TG_OP = 'INSERT' OR (
        TG_OP = 'UPDATE' AND NEW.role_assignment_id IS DISTINCT FROM OLD.role_assignment_id
    ) THEN
        SELECT root_tenant_id,membership_id
          INTO assignment_root,assignment_membership
          FROM public.membership_role_assignments
         WHERE id=NEW.role_assignment_id;
        IF assignment_membership IS NOT NULL THEN
            PERFORM bump_membership_authorization_version(assignment_root, assignment_membership);
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION bump_resource_grant_subject_authorization_version(
    grant_root BIGINT,
    grant_subject_org BIGINT,
    grant_subject_membership BIGINT
) RETURNS VOID AS $$
BEGIN
    IF grant_subject_membership IS NOT NULL THEN
        PERFORM bump_membership_authorization_version(grant_root, grant_subject_membership);
    ELSE
        UPDATE public.organization_memberships
           SET authorization_version=authorization_version+1,
               updated_at=NOW()
         WHERE root_tenant_id=grant_root AND organization_id=grant_subject_org;
    END IF;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION bump_resource_grant_subject_authorization_version(BIGINT, BIGINT, BIGINT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION bump_resource_grant_authorization_version()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        PERFORM bump_resource_grant_subject_authorization_version(
            OLD.root_tenant_id, OLD.subject_organization_id, OLD.subject_membership_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR (
        TG_OP = 'UPDATE' AND
        (NEW.root_tenant_id, NEW.subject_organization_id, NEW.subject_membership_id)
            IS DISTINCT FROM
        (OLD.root_tenant_id, OLD.subject_organization_id, OLD.subject_membership_id)
    ) THEN
        PERFORM bump_resource_grant_subject_authorization_version(
            NEW.root_tenant_id, NEW.subject_organization_id, NEW.subject_membership_id
        );
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION bump_organization_subtree_authorization_version()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
        UPDATE public.organization_memberships m
           SET authorization_version=m.authorization_version+1,
               updated_at=NOW()
          FROM public.organization_closure c
         WHERE c.root_tenant_id=NEW.root_tenant_id
           AND c.ancestor_id=NEW.id
           AND m.root_tenant_id=c.root_tenant_id
           AND m.organization_id=c.descendant_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION enforce_user_session_version_rotation()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.password_hash IS DISTINCT FROM OLD.password_hash
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
        IF NEW.session_version <= OLD.session_version THEN
            NEW.session_version := OLD.session_version + 1;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION enforce_membership_version_rotation()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.root_tenant_id IS DISTINCT FROM OLD.root_tenant_id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
        IF NEW.version <= OLD.version THEN
            NEW.version := OLD.version + 1;
        END IF;
        IF NEW.authorization_version <= OLD.authorization_version THEN
            NEW.authorization_version := OLD.authorization_version + 1;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

DROP TRIGGER IF EXISTS trg_users_session_version_rotation ON users;
CREATE TRIGGER trg_users_session_version_rotation
    BEFORE UPDATE OF password_hash, status, deleted_at ON users
    FOR EACH ROW EXECUTE FUNCTION enforce_user_session_version_rotation();

DROP TRIGGER IF EXISTS trg_memberships_version_rotation ON organization_memberships;
CREATE TRIGGER trg_memberships_version_rotation
    BEFORE UPDATE OF root_tenant_id, organization_id, user_id, status, expires_at ON organization_memberships
    FOR EACH ROW EXECUTE FUNCTION enforce_membership_version_rotation();

DROP TRIGGER IF EXISTS trg_role_assignment_authorization_version ON membership_role_assignments;
CREATE TRIGGER trg_role_assignment_authorization_version
    AFTER INSERT OR UPDATE OR DELETE ON membership_role_assignments
    FOR EACH ROW EXECUTE FUNCTION bump_role_assignment_authorization_version();

DROP TRIGGER IF EXISTS trg_permission_grant_authorization_version ON role_permission_grants;
CREATE TRIGGER trg_permission_grant_authorization_version
    AFTER INSERT OR UPDATE OR DELETE ON role_permission_grants
    FOR EACH ROW EXECUTE FUNCTION bump_permission_grant_authorization_version();

DROP TRIGGER IF EXISTS trg_resource_grant_authorization_version ON resource_grants;
CREATE TRIGGER trg_resource_grant_authorization_version
    AFTER INSERT OR UPDATE OR DELETE ON resource_grants
    FOR EACH ROW EXECUTE FUNCTION bump_resource_grant_authorization_version();

DROP TRIGGER IF EXISTS trg_organization_subtree_authorization_version ON organizations;
CREATE TRIGGER trg_organization_subtree_authorization_version
    AFTER UPDATE OF status, deleted_at ON organizations
    FOR EACH ROW EXECUTE FUNCTION bump_organization_subtree_authorization_version();
