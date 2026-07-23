-- 069: Add ensure_tenant_root helper and relax closure guard for SECURITY DEFINER.
--
-- The closure guard previously rejected ALL direct DML on organization_closure
-- (pg_trigger_depth < 2).  This made it impossible for application code to fix
-- stale root-tenant rows left behind by interrupted test runs.
--
-- The updated guard now also allows DML when current_user differs from
-- session_user, which is the standard PostgreSQL indicator that execution is
-- inside a SECURITY DEFINER function.  This lets ensure_tenant_root() maintain
-- closure entries directly.

-- ============================================================================
-- 1. Relax closure guard to allow SECURITY DEFINER functions
-- ============================================================================

CREATE OR REPLACE FUNCTION guard_organization_closure_mutation()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow nested trigger chains (normal governed workflows).
    IF pg_trigger_depth() >= 2 THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    -- Allow SECURITY DEFINER functions (current_user <> session_user).
    IF current_user <> session_user THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    RAISE EXCEPTION 'organization closure is maintained only by governed organization workflows'
        USING ERRCODE = '55000';
END;
$$ LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp;

-- ============================================================================
-- 2. ensure_tenant_root — idempotent root-org provisioning
-- ============================================================================

CREATE OR REPLACE FUNCTION ensure_tenant_root(p_tenant_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
    v_org_id BIGINT;
    v_stale_root BIGINT;
BEGIN
    -- Fast path: root org already correctly provisioned for this tenant.
    SELECT id INTO v_org_id
    FROM organizations
    WHERE id = p_tenant_id
      AND root_tenant_id = p_tenant_id
      AND org_type = 'manufacturer'
      AND deleted_at IS NULL;

    IF FOUND THEN
        -- Guarantee tenant_roots row (idempotent).
        INSERT INTO tenant_roots(root_tenant_id, organization_id)
        VALUES (p_tenant_id, v_org_id)
        ON CONFLICT (root_tenant_id) DO NOTHING;
        -- Guarantee self-closure entry (idempotent).
        INSERT INTO organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)
        VALUES (p_tenant_id, v_org_id, v_org_id, 0)
        ON CONFLICT (root_tenant_id, ancestor_id, descendant_id) DO NOTHING;
        RETURN v_org_id;
    END IF;

    -- A stale org with the same PK (id = p_tenant_id) may exist from a
    -- previous test run or interrupted provisioning.  Move it to a negative
    -- ID so the real root org can claim the slot.  Only 'id' is changed;
    -- the BEFORE UPDATE trigger fires on UPDATE OF parent_id, root_tenant_id,
    -- org_type and is therefore NOT invoked.
    SELECT root_tenant_id INTO v_stale_root
    FROM organizations
    WHERE id = p_tenant_id AND deleted_at IS NULL;

    IF FOUND THEN
        -- Clean up all stale data for this tenant before moving the root row.
        -- This handles child orgs, memberships, invitations, and closure entries
        -- left behind by previous test runs or interrupted provisioning.
        -- Deletion order respects FK ON DELETE RESTRICT constraints.

        -- 1. Remove rows from leaf tables that reference stale orgs.
        DELETE FROM role_permission_grants WHERE root_tenant_id = v_stale_root;
        DELETE FROM resource_grants WHERE root_tenant_id = v_stale_root;
        DELETE FROM authorization_resources WHERE root_tenant_id = v_stale_root;
        DELETE FROM organization_quota_usage WHERE root_tenant_id = v_stale_root;
        DELETE FROM organization_quotas WHERE root_tenant_id = v_stale_root;
        DELETE FROM invitations WHERE root_tenant_id = v_stale_root;
        DELETE FROM membership_role_assignments WHERE root_tenant_id = v_stale_root;
        DELETE FROM organization_memberships WHERE root_tenant_id = v_stale_root;

        -- 2. Clear audit_logs FK (SET active_organization_id to NULL).
        UPDATE audit_logs SET active_organization_id = NULL
            WHERE root_tenant_id = v_stale_root;

        -- 3. Remove closure entries (guard allows SECURITY DEFINER).
        DELETE FROM organization_closure WHERE root_tenant_id = v_stale_root;

        -- 4. Remove tenant_roots entry.
        DELETE FROM tenant_roots WHERE root_tenant_id = v_stale_root;

        -- 5. Delete child orgs iteratively (leaves first to satisfy self-ref FK).
        LOOP
            DELETE FROM organizations
                WHERE root_tenant_id = v_stale_root
                  AND id <> p_tenant_id
                  AND NOT EXISTS (
                      SELECT 1 FROM organizations c
                      WHERE c.root_tenant_id = v_stale_root
                        AND c.parent_id = organizations.id
                        AND c.id <> organizations.id
                  );
            EXIT WHEN NOT FOUND;
        END LOOP;

        -- 6. Move the stale root org out of the way (negative ID).
        UPDATE organizations SET id = -id WHERE id = p_tenant_id;
    END IF;

    -- Insert the root manufacturer org (triggers fire normally).
    INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, name, status, version)
    VALUES (p_tenant_id, p_tenant_id, NULL, 'manufacturer', 'Root Tenant', 'active', 1);
    -- AFTER INSERT trigger already created tenant_roots + self-closure.

    -- Sync the BIGSERIAL sequence past all existing IDs so future
    -- auto-generated IDs never collide with manually-specified ones.
    PERFORM setval(
        'organizations_id_seq',
        GREATEST((SELECT COALESCE(MAX(id), 0) FROM organizations), p_tenant_id)
    );

    RETURN p_tenant_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION ensure_tenant_root(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ensure_tenant_root(BIGINT) TO PUBLIC;
