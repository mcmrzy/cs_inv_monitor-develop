-- 070 down: restore strict trigger and drop governed_move_org

DROP FUNCTION IF EXISTS governed_move_org(BIGINT, BIGINT, BIGINT);

-- Restore the strict validate_organization_hierarchy without SECURITY DEFINER bypass.
CREATE OR REPLACE FUNCTION validate_organization_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    parent_type VARCHAR(32);
BEGIN
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
