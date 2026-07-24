-- 069 down: restore original closure guard and remove ensure_tenant_root

DROP FUNCTION IF EXISTS ensure_tenant_root(BIGINT);

-- Restore the original strict closure guard.
CREATE OR REPLACE FUNCTION guard_organization_closure_mutation()
RETURNS TRIGGER AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'organization closure is maintained only by governed organization workflows'
            USING ERRCODE = '55000';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;
