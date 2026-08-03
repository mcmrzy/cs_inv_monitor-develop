-- Hotfix: ensure_tenant_root must provision root quota rows (idempotent).
-- The root manufacturer org is the top of the quota-inheritance chain;
-- child orgs inherit limits from it, so its quota rows must exist before
-- children can be created. Previously the function never inserted
-- organization_quotas rows, so creating a child org failed with
-- "descendant quota cannot exceed inherited ancestor limit" (23514) and the
-- transaction was rolled back ("commit unexpectedly resulted in rollback").
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
        -- Guarantee root quota rows (idempotent): the root manufacturer org is
        -- the top of the quota-inheritance chain; child orgs inherit limits
        -- from it, so its quota rows must exist before children can be created.
        INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id)
        SELECT p_tenant_id, v_org_id, q.resource_type, q.quota_limit, NULL
        FROM (VALUES
            ('members', 100),
            ('direct_child_organizations', 50),
            ('descendant_organizations', 200),
            ('inventory_devices', 1000),
            ('claimed_devices', 500),
            ('stations', 200),
            ('pending_invitations', 20)
        ) AS q(resource_type, quota_limit)
        ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;
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

    -- Guarantee root quota rows (idempotent): the root manufacturer org is
    -- the top of the quota-inheritance chain; child orgs inherit limits
    -- from it, so its quota rows must exist before children can be created.
    INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id)
    SELECT p_tenant_id, p_tenant_id, q.resource_type, q.quota_limit, NULL
    FROM (VALUES
        ('members', 100),
        ('direct_child_organizations', 50),
        ('descendant_organizations', 200),
        ('inventory_devices', 1000),
        ('claimed_devices', 500),
        ('stations', 200),
        ('pending_invitations', 20)
    ) AS q(resource_type, quota_limit)
    ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;

    RETURN p_tenant_id;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION ensure_tenant_root(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ensure_tenant_root(BIGINT) TO PUBLIC;
