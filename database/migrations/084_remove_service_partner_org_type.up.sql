-- Migration 084: Remove 'service_partner' organization type
-- The service_partner type is no longer needed in the channel hierarchy.
-- Hierarchy is now strictly: manufacturer -> agent -> distributor -> installer -> customer

-- 1. Reassign any existing service_partner orgs to 'customer' (safest fallback)
UPDATE organizations SET org_type = 'customer' WHERE org_type = 'service_partner';

-- 2. Drop and recreate the CHECK constraint without service_partner
ALTER TABLE organizations DROP CONSTRAINT IF EXISTS organizations_org_type_check;
ALTER TABLE organizations ADD CONSTRAINT organizations_org_type_check
    CHECK (org_type IN ('manufacturer', 'agent', 'distributor', 'installer', 'customer'));

-- 3. Update column comment
COMMENT ON COLUMN organizations.org_type IS 'Organization type in channel hierarchy: manufacturer (原厂), agent (代理商), distributor (经销商), installer (安装商), customer (终端用户)';

-- 4. Recreate validate_org_hierarchy trigger without service_partner rule
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
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;
