-- Migration 086 (down): Restore legacy hierarchy trigger and function
--
-- Restores the pre-086 state:
--   1. validate_organization_hierarchy() — final legacy definition from
--      migration 073 (escape hatch app.allow_hierarchy_change + service_partner
--      rule; the service_partner org_type itself was removed later in 084).
--   2. trg_organizations_validate_hierarchy — BEFORE INSERT OR UPDATE OF
--      parent_id, root_tenant_id, org_type (original definition from migration
--      064).
--
-- NOTE: this legacy trigger conflicts with trg_org_hierarchy (084) and was the
-- root cause of "distributor cannot be parent of installer"; restoring it via
-- this down migration re-introduces that conflict, so rollback is intended only
-- for environments that also revert migrations 084+.

-- 1. Restore the legacy trigger function
CREATE OR REPLACE FUNCTION validate_organization_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    parent_type VARCHAR(32);
BEGIN
    -- Allow governed workflows: SECURITY DEFINER context (current_user differs
    -- from session_user) OR an explicit transaction-scoped escape hatch that the
    -- governed move workflow sets. The escape hatch is required because in CI/dev
    -- the function owner and the session role are frequently the same superuser.
    IF current_user <> session_user
       OR current_setting('app.allow_hierarchy_change', true) = 'true' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'UPDATE' AND (
        NEW.parent_id IS DISTINCT FROM OLD.parent_id
        OR NEW.root_tenant_id IS DISTINCT FROM OLD.root_tenant_id
        OR NEW.org_type IS DISTINCT FROM OLD.org_type
    ) THEN
        RAISE EXCEPTION 'direct organization hierarchy/type changes are forbidden; use the governed move workflow'
            USING ERRCODE = '55000';
    END IF;

    IF NEW.org_type = 'manufacturer' THEN
        IF NEW.parent_id IS NOT NULL OR NEW.id <> NEW.root_tenant_id THEN
            RAISE EXCEPTION 'manufacturer must be a self-identified root tenant'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.parent_id IS NULL OR NEW.parent_id = NEW.id THEN
        RAISE EXCEPTION 'non-root organization requires a different parent'
            USING ERRCODE = '23514';
    END IF;

    SELECT org_type INTO parent_type
    FROM public.organizations
    WHERE root_tenant_id = NEW.root_tenant_id
      AND id = NEW.parent_id
      AND deleted_at IS NULL
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'organization parent does not exist in root tenant %', NEW.root_tenant_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT (
        (NEW.org_type = 'agent' AND parent_type = 'manufacturer')
        OR (NEW.org_type = 'distributor' AND parent_type = 'agent')
        OR (NEW.org_type = 'customer' AND parent_type = 'distributor')
        OR (NEW.org_type = 'service_partner' AND parent_type IN ('manufacturer', 'agent', 'distributor'))
    ) THEN
        RAISE EXCEPTION 'illegal organization hierarchy: % cannot be parent of %', parent_type, NEW.org_type
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION validate_organization_hierarchy() FROM PUBLIC;

-- 2. Restore the legacy trigger
DROP TRIGGER IF EXISTS trg_organizations_validate_hierarchy ON organizations;
CREATE TRIGGER trg_organizations_validate_hierarchy
    BEFORE INSERT OR UPDATE OF parent_id, root_tenant_id, org_type ON organizations
    FOR EACH ROW EXECUTE FUNCTION validate_organization_hierarchy();
