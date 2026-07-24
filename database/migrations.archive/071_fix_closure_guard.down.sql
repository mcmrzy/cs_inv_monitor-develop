-- 071 down: restore maintain_organization_insert_relations without SECURITY DEFINER
-- (matching the pre-fix state; effectively a no-op if the original migration 064
-- definition was already SECURITY DEFINER)

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
