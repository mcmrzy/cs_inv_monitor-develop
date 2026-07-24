-- 071: Fix maintain_organization_insert_relations SECURITY DEFINER
--
-- The AFTER INSERT trigger maintain_organization_insert_relations inserts into
-- organization_closure, but the guard trigger guard_organization_closure_mutation
-- (updated in migration 069) only allows writes when:
--   1. pg_trigger_depth() >= 2, OR
--   2. current_user <> session_user (SECURITY DEFINER context)
--
-- If the function lost its SECURITY DEFINER attribute (e.g. due to partial
-- migration or manual intervention), the guard blocks closure writes and
-- createOrg returns 500.
--
-- This migration explicitly re-creates the function with SECURITY DEFINER,
-- ensuring the guard's current_user <> session_user check passes.

CREATE OR REPLACE FUNCTION maintain_organization_insert_relations()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.org_type = 'manufacturer' THEN
        INSERT INTO public.tenant_roots(root_tenant_id, organization_id)
        VALUES (NEW.root_tenant_id, NEW.id)
        ON CONFLICT (root_tenant_id) DO NOTHING;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM public.tenant_roots WHERE root_tenant_id = NEW.root_tenant_id) THEN
            RAISE EXCEPTION 'root tenant % is not registered', NEW.root_tenant_id
                USING ERRCODE = '23503';
        END IF;
        INSERT INTO public.organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)
        SELECT NEW.root_tenant_id, ancestor_id, NEW.id, depth + 1
        FROM public.organization_closure
        WHERE root_tenant_id = NEW.root_tenant_id
          AND descendant_id = NEW.parent_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'parent organization % has no closure facts', NEW.parent_id
                USING ERRCODE = '23503';
        END IF;
    END IF;

    INSERT INTO public.organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)
    VALUES (NEW.root_tenant_id, NEW.id, NEW.id, 0);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION maintain_organization_insert_relations() FROM PUBLIC;
