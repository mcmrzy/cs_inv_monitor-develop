-- 073 down: restore migration 070 versions of governed_move_org and
-- validate_organization_hierarchy (SECURITY DEFINER heuristic only, closure
-- rebuild that removes all subtree closure rows).

CREATE OR REPLACE FUNCTION validate_organization_hierarchy()
RETURNS TRIGGER AS $$
DECLARE
    parent_type VARCHAR(32);
BEGIN
    -- Allow SECURITY DEFINER functions (e.g. governed_move_org, ensure_tenant_root).
    IF current_user <> session_user THEN
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

CREATE OR REPLACE FUNCTION governed_move_org(
    p_org_id       BIGINT,
    p_new_parent   BIGINT,
    p_tenant_id    BIGINT
)
RETURNS TEXT AS $$
DECLARE
    v_org_type    VARCHAR(32);
    v_parent_type VARCHAR(32);
    v_is_ancestor  BOOLEAN;
BEGIN
    SELECT org_type INTO v_org_type
    FROM organizations
    WHERE id = p_org_id AND root_tenant_id = p_tenant_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN 'org_not_found';
    END IF;

    SELECT org_type INTO v_parent_type
    FROM organizations
    WHERE id = p_new_parent AND root_tenant_id = p_tenant_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN 'parent_not_found';
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM organization_closure
        WHERE root_tenant_id = p_tenant_id
          AND ancestor_id = p_org_id
          AND descendant_id = p_new_parent
          AND depth > 0
    ) INTO v_is_ancestor;
    IF v_is_ancestor THEN
        RETURN 'circular_reference';
    END IF;

    IF NOT (
        (v_org_type = 'agent' AND v_parent_type = 'manufacturer')
        OR (v_org_type = 'distributor' AND v_parent_type = 'agent')
        OR (v_org_type = 'customer' AND v_parent_type = 'distributor')
        OR (v_org_type = 'service_partner' AND v_parent_type IN ('manufacturer', 'agent', 'distributor'))
    ) THEN
        RETURN 'invalid_hierarchy';
    END IF;

    CREATE TEMP TABLE _sub_depth ON COMMIT DROP AS
    WITH RECURSIVE sub AS (
        SELECT id, 0 AS d
        FROM organizations
        WHERE id = p_org_id AND deleted_at IS NULL
        UNION ALL
        SELECT o.id, s.d + 1
        FROM organizations o
        JOIN sub s ON o.parent_id = s.id
        WHERE o.deleted_at IS NULL
    )
    SELECT id, d FROM sub;

    DELETE FROM organization_closure
    WHERE root_tenant_id = p_tenant_id
      AND descendant_id IN (SELECT id FROM _sub_depth);

    UPDATE organizations
    SET parent_id = p_new_parent, updated_at = NOW(), version = version + 1
    WHERE id = p_org_id AND root_tenant_id = p_tenant_id;

    INSERT INTO organization_closure (root_tenant_id, ancestor_id, descendant_id, depth)
    SELECT p_tenant_id,
           anc.ancestor_id,
           sub.id,
           anc.depth + 1 + sub.d
    FROM organization_closure anc
    CROSS JOIN _sub_depth sub
    WHERE anc.root_tenant_id = p_tenant_id
      AND anc.descendant_id = p_new_parent
    ON CONFLICT (root_tenant_id, ancestor_id, descendant_id) DO UPDATE
    SET depth = EXCLUDED.depth;

    DROP TABLE IF EXISTS _sub_depth;

    RETURN 'ok';
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION governed_move_org(BIGINT, BIGINT, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION governed_move_org(BIGINT, BIGINT, BIGINT) TO PUBLIC;
