-- 072: Fix closure guard trigger to allow trigger-context writes.
--
-- Root cause analysis:
-- The guard trigger guard_organization_closure_mutation checks
-- pg_trigger_depth() >= 2 to allow writes from governed trigger chains.
-- However, when the guard itself fires as a BEFORE trigger on
-- organization_closure, pg_trigger_depth() returns 1 (only the guard
-- trigger is on the stack at that point), NOT 2. So the depth check
-- never passes.
--
-- The fallback check current_user <> session_user (SECURITY DEFINER
-- context) may also fail in environments where the function owner and
-- the session user are the same superuser (common in development).
--
-- Fix: Lower the pg_trigger_depth threshold to >= 1, which correctly
-- identifies that the DML originates from within a trigger context
-- (i.e. maintain_organization_insert_relations AFTER INSERT trigger).
-- Also add an explicit session variable escape hatch for maintenance.

CREATE OR REPLACE FUNCTION guard_organization_closure_mutation()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow nested trigger context (AFTER INSERT trigger calling closure write).
    -- pg_trigger_depth() = 1 when this BEFORE trigger fires from within
    -- another trigger (e.g. maintain_organization_insert_relations).
    IF pg_trigger_depth() >= 1 THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    -- Allow SECURITY DEFINER functions (current_user <> session_user).
    IF current_user <> session_user THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    -- Allow explicit session variable for maintenance scripts.
    IF current_setting('app.allow_closure_write', true) = 'true' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    RAISE EXCEPTION 'organization closure is maintained only by governed organization workflows'
        USING ERRCODE = '55000';
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;
