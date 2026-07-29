-- Migration 082: Add organization hierarchy constraint
-- Enforces strict parent-child type rules for the 5-level channel hierarchy:
-- manufacturer -> agent -> distributor -> installer -> customer

-- Add hierarchy validation function
CREATE OR REPLACE FUNCTION validate_org_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    parent_type VARCHAR(32);
BEGIN
    -- manufacturer must be root (no parent)
    IF NEW.org_type = 'manufacturer' AND NEW.parent_id IS NOT NULL THEN
        RAISE EXCEPTION 'manufacturer must be root (no parent)'
            USING ERRCODE = '23514';
    END IF;

    -- non-manufacturer must have a parent
    IF NEW.org_type != 'manufacturer' AND NEW.parent_id IS NULL THEN
        RAISE EXCEPTION 'non-manufacturer org must have a parent'
            USING ERRCODE = '23514';
    END IF;

    -- validate parent type matches hierarchy rules
    IF NEW.parent_id IS NOT NULL THEN
        SELECT org_type INTO parent_type
        FROM organizations
        WHERE root_tenant_id = NEW.root_tenant_id
          AND id = NEW.parent_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'parent organization does not exist'
                USING ERRCODE = '23503';
        END IF;

        IF NEW.org_type = 'agent' AND parent_type != 'manufacturer' THEN
            RAISE EXCEPTION 'agent parent must be manufacturer, got %', parent_type
                USING ERRCODE = '23514';
        ELSIF NEW.org_type = 'distributor' AND parent_type != 'agent' THEN
            RAISE EXCEPTION 'distributor parent must be agent, got %', parent_type
                USING ERRCODE = '23514';
        ELSIF NEW.org_type = 'installer' AND parent_type != 'distributor' THEN
            RAISE EXCEPTION 'installer parent must be distributor, got %', parent_type
                USING ERRCODE = '23514';
        ELSIF NEW.org_type = 'customer' AND parent_type NOT IN ('installer', 'manufacturer') THEN
            RAISE EXCEPTION 'customer parent must be installer or manufacturer, got %', parent_type
                USING ERRCODE = '23514';
        ELSIF NEW.org_type = 'service_partner' AND parent_type NOT IN ('manufacturer', 'agent') THEN
            RAISE EXCEPTION 'service_partner parent must be manufacturer or agent, got %', parent_type
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

-- Create trigger
DROP TRIGGER IF EXISTS trg_org_hierarchy ON organizations;
CREATE TRIGGER trg_org_hierarchy
    BEFORE INSERT OR UPDATE OF org_type, parent_id ON organizations
    FOR EACH ROW EXECUTE FUNCTION validate_org_hierarchy();
