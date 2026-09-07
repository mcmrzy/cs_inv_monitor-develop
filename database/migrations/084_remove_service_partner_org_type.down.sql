-- Migration 084 rollback: Restore 'service_partner' organization type

-- 1. Restore CHECK constraint with service_partner
ALTER TABLE organizations DROP CONSTRAINT IF EXISTS organizations_org_type_check;
ALTER TABLE organizations ADD CONSTRAINT organizations_org_type_check
    CHECK (org_type IN ('manufacturer', 'agent', 'distributor', 'installer', 'customer', 'service_partner'));

-- 2. Restore column comment
COMMENT ON COLUMN organizations.org_type IS 'Organization type in channel hierarchy: manufacturer (原厂), agent (代理商), distributor (经销商), installer (安装商), customer (终端用户), service_partner (服务合作伙伴)';

-- 3. Restore validate_org_hierarchy trigger with service_partner rule
CREATE OR REPLACE FUNCTION validate_org_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    parent_type VARCHAR(32);
BEGIN
    IF NEW.org_type = 'manufacturer' AND NEW.parent_id IS NOT NULL THEN
        RAISE EXCEPTION 'manufacturer must be root (no parent)'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.org_type != 'manufacturer' AND NEW.parent_id IS NULL THEN
        RAISE EXCEPTION 'non-manufacturer org must have a parent'
            USING ERRCODE = '23514';
    END IF;

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
