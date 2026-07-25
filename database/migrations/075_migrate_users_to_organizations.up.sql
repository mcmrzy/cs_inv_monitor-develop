-- 075: Migrate existing users from legacy role/parent_id system to the new
-- organization + membership + role_assignment + permission_grant system.
--
-- This migration is idempotent: it skips users who already have an active
-- organization membership.
--
-- Hierarchy mapping:
--   role=0 (SUPER_ADMIN) → manufacturer root org, is_system_admin=true
--   role=1 (ADMIN)       → agent org,      role_code='org_admin'
--   role=2 (OPERATOR)    → agent org,      role_code='channel_manager'
--   role=3 (DEALER)      → distributor org, role_code='operator'
--   role=4 (INSTALLER)   → service_partner org, role_code='installer'
--   role=5 (END_USER)    → customer org (or join parent org), role_code='viewer'
--
-- Org hierarchy rules (enforced by validate_organization_hierarchy trigger):
--   manufacturer > agent > distributor > customer/service_partner

-- Use the escape hatch for the hierarchy guard in case we need to insert
-- orgs whose parent type doesn't exactly match the strict trigger rules
-- (e.g. an installer whose old parent was an end-user).
SET LOCAL app.allow_hierarchy_change = 'true';

DO $$
DECLARE
    v_user RECORD;
    v_root_tenant BIGINT;
    v_parent_org_id BIGINT;
    v_parent_org_type VARCHAR(32);
    v_org_id BIGINT;
    v_membership_id BIGINT;
    v_role_assignment_id BIGINT;
    v_org_type VARCHAR(32);
    v_role_code VARCHAR(64);
    v_data_scope VARCHAR(40);
    v_perm RECORD;
    v_perm_code TEXT;
    v_count INTEGER := 0;
    v_skipped INTEGER := 0;
    v_manufacturer_count INTEGER := 0;
BEGIN
    -- ================================================================
    -- Step 1: Ensure at least one manufacturer root exists.
    -- If no role=0 users exist, create a system manufacturer using the
    -- first available user ID as the tenant root.
    -- ================================================================
    SELECT COUNT(*) INTO v_manufacturer_count FROM tenant_roots;
    IF v_manufacturer_count = 0 THEN
        -- Pick the lowest-ID active user as the system manufacturer root.
        SELECT id INTO v_root_tenant FROM users WHERE deleted_at IS NULL ORDER BY id LIMIT 1;
        IF v_root_tenant IS NOT NULL THEN
            PERFORM ensure_tenant_root(v_root_tenant);
            RAISE NOTICE 'Created system manufacturer root with tenant_id=%', v_root_tenant;
        END IF;
    END IF;

    -- ================================================================
    -- Step 2: Process role=0 (SUPER_ADMIN) users.
    -- Each gets a manufacturer root org and a membership.
    -- ================================================================
    FOR v_user IN SELECT id, COALESCE(nickname, phone, 'User_' || id) AS name
                  FROM users WHERE role = 0 AND deleted_at IS NULL
                  AND id NOT IN (
                      SELECT user_id FROM organization_memberships WHERE status = 'active'
                  )
                  ORDER BY id
    LOOP
        -- ensure_tenant_root creates the manufacturer org, tenant_roots, and closure.
        PERFORM ensure_tenant_root(v_user.id);

        -- Create membership for the super admin in their manufacturer org.
        BEGIN
            INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
            VALUES (v_user.id, v_user.id, v_user.id, 'active');
            v_count := v_count + 1;
        EXCEPTION WHEN unique_violation THEN
            v_skipped := v_skipped + 1;
        END;
    END LOOP;
    RAISE NOTICE 'Step 2 (super_admins): processed=%, skipped=%', v_count, v_skipped;

    -- ================================================================
    -- Step 3: Process role=1 (ADMIN) and role=2 (OPERATOR) users.
    -- Both become 'agent' orgs under a manufacturer.
    -- role=1 → role_code='org_admin'
    -- role=2 → role_code='channel_manager'
    -- data_scope = 'organization_and_descendants'
    -- ================================================================
    v_count := 0; v_skipped := 0;
    FOR v_user IN SELECT id, role, COALESCE(nickname, phone, 'User_' || id) AS name, parent_id
                  FROM users WHERE role IN (1, 2) AND deleted_at IS NULL
                  AND id NOT IN (
                      SELECT user_id FROM organization_memberships WHERE status = 'active'
                  )
                  ORDER BY role, id
    LOOP
        -- Determine root tenant from parent's membership, or fall back to first manufacturer.
        v_root_tenant := NULL;
        IF v_user.parent_id IS NOT NULL THEN
            SELECT om.root_tenant_id INTO v_root_tenant
            FROM organization_memberships om
            WHERE om.user_id = v_user.parent_id AND om.status = 'active'
            LIMIT 1;
        END IF;
        IF v_root_tenant IS NULL THEN
            SELECT root_tenant_id INTO v_root_tenant FROM tenant_roots ORDER BY root_tenant_id LIMIT 1;
        END IF;
        IF v_root_tenant IS NULL THEN
            RAISE WARNING 'Cannot find root tenant for user % (role=%), skipping', v_user.id, v_user.role;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        -- Find manufacturer org in this tenant.
        SELECT id INTO v_parent_org_id
        FROM organizations
        WHERE root_tenant_id = v_root_tenant AND org_type = 'manufacturer' AND deleted_at IS NULL
        LIMIT 1;
        IF v_parent_org_id IS NULL THEN
            RAISE WARNING 'No manufacturer org for tenant %, skipping user %', v_root_tenant, v_user.id;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        -- Set role-specific values.
        IF v_user.role = 1 THEN
            v_role_code := 'org_admin';
        ELSE
            v_role_code := 'channel_manager';
        END IF;
        v_org_type := 'agent';
        v_data_scope := 'organization_and_descendants';

        -- Create agent org.
        INSERT INTO organizations (root_tenant_id, parent_id, org_type, name, status)
        VALUES (v_root_tenant, v_parent_org_id, v_org_type, v_user.name, 'active')
        RETURNING id INTO v_org_id;

        -- Create membership.
        INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
        VALUES (v_root_tenant, v_org_id, v_user.id, 'active')
        RETURNING id INTO v_membership_id;

        -- Create role assignment.
        INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status)
        VALUES (v_root_tenant, v_org_id, v_membership_id, v_role_code, 'active')
        RETURNING id INTO v_role_assignment_id;

        -- Create permission grants from old role_permissions.
        FOR v_perm IN SELECT resource, action FROM role_permissions WHERE role = v_user.role AND is_allowed = true
        LOOP
            v_perm_code := v_perm.resource || ':' || v_perm.action;
            BEGIN
                INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
                VALUES (v_root_tenant, v_org_id, v_role_assignment_id, v_perm_code, v_data_scope);
            EXCEPTION WHEN unique_violation THEN
                NULL; -- Already exists
            END;
        END LOOP;

        -- Migrate quotas.
        IF EXISTS (SELECT 1 FROM users WHERE id = v_user.id AND device_limit IS NOT NULL) THEN
            INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit)
            SELECT v_root_tenant, v_org_id, 'claimed_devices', device_limit
            FROM users WHERE id = v_user.id
            ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;
        END IF;
        IF EXISTS (SELECT 1 FROM users WHERE id = v_user.id AND user_limit IS NOT NULL) THEN
            INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit)
            SELECT v_root_tenant, v_org_id, 'members', user_limit
            FROM users WHERE id = v_user.id
            ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;
        END IF;

        v_count := v_count + 1;
    END LOOP;
    RAISE NOTICE 'Step 3 (admin/operator): processed=%, skipped=%', v_count, v_skipped;

    -- ================================================================
    -- Step 4: Process role=3 (DEALER) users.
    -- Become 'distributor' orgs under an agent.
    -- role_code='operator', data_scope='organization_and_descendants'
    -- ================================================================
    v_count := 0; v_skipped := 0;
    FOR v_user IN SELECT id, COALESCE(nickname, phone, 'User_' || id) AS name, parent_id
                  FROM users WHERE role = 3 AND deleted_at IS NULL
                  AND id NOT IN (
                      SELECT user_id FROM organization_memberships WHERE status = 'active'
                  )
                  ORDER BY id
    LOOP
        v_root_tenant := NULL;
        v_parent_org_id := NULL;
        v_parent_org_type := NULL;

        -- Try to find parent's org.
        IF v_user.parent_id IS NOT NULL THEN
            SELECT om.root_tenant_id, om.organization_id, o.org_type
            INTO v_root_tenant, v_parent_org_id, v_parent_org_type
            FROM organization_memberships om
            JOIN organizations o ON o.root_tenant_id = om.root_tenant_id AND o.id = om.organization_id
            WHERE om.user_id = v_user.parent_id AND om.status = 'active' AND o.deleted_at IS NULL
            LIMIT 1;
        END IF;

        -- If no parent org, or parent is not agent/manufacturer, find an agent org.
        IF v_parent_org_id IS NULL OR v_parent_org_type NOT IN ('agent', 'manufacturer') THEN
            IF v_root_tenant IS NULL THEN
                SELECT root_tenant_id INTO v_root_tenant FROM tenant_roots ORDER BY root_tenant_id LIMIT 1;
            END IF;
            -- Find an agent org in this tenant.
            SELECT id INTO v_parent_org_id
            FROM organizations
            WHERE root_tenant_id = v_root_tenant AND org_type = 'agent' AND deleted_at IS NULL AND status = 'active'
            LIMIT 1;
            -- If no agent, use manufacturer (the trigger requires distributor's parent to be agent,
            -- but we have the escape hatch set).
            IF v_parent_org_id IS NULL THEN
                SELECT id INTO v_parent_org_id
                FROM organizations
                WHERE root_tenant_id = v_root_tenant AND org_type = 'manufacturer' AND deleted_at IS NULL
                LIMIT 1;
            END IF;
        END IF;

        IF v_parent_org_id IS NULL THEN
            RAISE WARNING 'Cannot find parent org for dealer user %, skipping', v_user.id;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        v_role_code := 'operator';
        v_org_type := 'distributor';
        v_data_scope := 'organization_and_descendants';

        INSERT INTO organizations (root_tenant_id, parent_id, org_type, name, status)
        VALUES (v_root_tenant, v_parent_org_id, v_org_type, v_user.name, 'active')
        RETURNING id INTO v_org_id;

        INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
        VALUES (v_root_tenant, v_org_id, v_user.id, 'active')
        RETURNING id INTO v_membership_id;

        INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status)
        VALUES (v_root_tenant, v_org_id, v_membership_id, v_role_code, 'active')
        RETURNING id INTO v_role_assignment_id;

        FOR v_perm IN SELECT resource, action FROM role_permissions WHERE role = 3 AND is_allowed = true
        LOOP
            v_perm_code := v_perm.resource || ':' || v_perm.action;
            BEGIN
                INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
                VALUES (v_root_tenant, v_org_id, v_role_assignment_id, v_perm_code, v_data_scope);
            EXCEPTION WHEN unique_violation THEN NULL;
            END;
        END LOOP;

        -- Migrate quotas.
        IF EXISTS (SELECT 1 FROM users WHERE id = v_user.id AND device_limit IS NOT NULL) THEN
            INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit)
            SELECT v_root_tenant, v_org_id, 'claimed_devices', device_limit
            FROM users WHERE id = v_user.id
            ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;
        END IF;
        IF EXISTS (SELECT 1 FROM users WHERE id = v_user.id AND user_limit IS NOT NULL) THEN
            INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit)
            SELECT v_root_tenant, v_org_id, 'members', user_limit
            FROM users WHERE id = v_user.id
            ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING;
        END IF;

        v_count := v_count + 1;
    END LOOP;
    RAISE NOTICE 'Step 4 (dealers): processed=%, skipped=%', v_count, v_skipped;

    -- ================================================================
    -- Step 5: Process role=4 (INSTALLER) users.
    -- Become 'service_partner' orgs under agent/distributor/customer.
    -- role_code='installer', data_scope='organization'
    -- ================================================================
    v_count := 0; v_skipped := 0;
    FOR v_user IN SELECT id, COALESCE(nickname, phone, 'User_' || id) AS name, parent_id
                  FROM users WHERE role = 4 AND deleted_at IS NULL
                  AND id NOT IN (
                      SELECT user_id FROM organization_memberships WHERE status = 'active'
                  )
                  ORDER BY id
    LOOP
        v_root_tenant := NULL;
        v_parent_org_id := NULL;
        v_parent_org_type := NULL;

        IF v_user.parent_id IS NOT NULL THEN
            SELECT om.root_tenant_id, om.organization_id, o.org_type
            INTO v_root_tenant, v_parent_org_id, v_parent_org_type
            FROM organization_memberships om
            JOIN organizations o ON o.root_tenant_id = om.root_tenant_id AND o.id = om.organization_id
            WHERE om.user_id = v_user.parent_id AND om.status = 'active' AND o.deleted_at IS NULL
            LIMIT 1;
        END IF;

        -- If parent org type is not valid for service_partner, find a valid one.
        IF v_parent_org_id IS NULL OR v_parent_org_type NOT IN ('agent', 'distributor', 'customer', 'manufacturer') THEN
            IF v_root_tenant IS NULL THEN
                SELECT root_tenant_id INTO v_root_tenant FROM tenant_roots ORDER BY root_tenant_id LIMIT 1;
            END IF;
            -- Find any valid parent org (prefer agent, then distributor).
            SELECT id INTO v_parent_org_id
            FROM organizations
            WHERE root_tenant_id = v_root_tenant AND org_type IN ('agent', 'distributor') AND deleted_at IS NULL AND status = 'active'
            ORDER BY org_type  -- agent before distributor
            LIMIT 1;
            IF v_parent_org_id IS NULL THEN
                SELECT id INTO v_parent_org_id
                FROM organizations
                WHERE root_tenant_id = v_root_tenant AND org_type = 'manufacturer' AND deleted_at IS NULL
                LIMIT 1;
            END IF;
        END IF;

        IF v_parent_org_id IS NULL THEN
            RAISE WARNING 'Cannot find parent org for installer user %, skipping', v_user.id;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        v_role_code := 'installer';
        v_org_type := 'service_partner';
        v_data_scope := 'organization';

        INSERT INTO organizations (root_tenant_id, parent_id, org_type, name, status)
        VALUES (v_root_tenant, v_parent_org_id, v_org_type, v_user.name, 'active')
        RETURNING id INTO v_org_id;

        INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
        VALUES (v_root_tenant, v_org_id, v_user.id, 'active')
        RETURNING id INTO v_membership_id;

        INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status)
        VALUES (v_root_tenant, v_org_id, v_membership_id, v_role_code, 'active')
        RETURNING id INTO v_role_assignment_id;

        FOR v_perm IN SELECT resource, action FROM role_permissions WHERE role = 4 AND is_allowed = true
        LOOP
            v_perm_code := v_perm.resource || ':' || v_perm.action;
            BEGIN
                INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
                VALUES (v_root_tenant, v_org_id, v_role_assignment_id, v_perm_code, v_data_scope);
            EXCEPTION WHEN unique_violation THEN NULL;
            END;
        END LOOP;

        v_count := v_count + 1;
    END LOOP;
    RAISE NOTICE 'Step 5 (installers): processed=%, skipped=%', v_count, v_skipped;

    -- ================================================================
    -- Step 6: Process role=5 (END_USER) users.
    -- Become 'customer' orgs under agent/distributor, or join parent's org.
    -- role_code='viewer', data_scope='self'
    -- ================================================================
    v_count := 0; v_skipped := 0;
    FOR v_user IN SELECT id, COALESCE(nickname, phone, 'User_' || id) AS name, parent_id
                  FROM users WHERE role = 5 AND deleted_at IS NULL
                  AND id NOT IN (
                      SELECT user_id FROM organization_memberships WHERE status = 'active'
                  )
                  ORDER BY id
    LOOP
        v_root_tenant := NULL;
        v_parent_org_id := NULL;
        v_parent_org_type := NULL;

        IF v_user.parent_id IS NOT NULL THEN
            SELECT om.root_tenant_id, om.organization_id, o.org_type
            INTO v_root_tenant, v_parent_org_id, v_parent_org_type
            FROM organization_memberships om
            JOIN organizations o ON o.root_tenant_id = om.root_tenant_id AND o.id = om.organization_id
            WHERE om.user_id = v_user.parent_id AND om.status = 'active' AND o.deleted_at IS NULL
            LIMIT 1;
        END IF;

        -- If no parent org found, find any agent or distributor in the system.
        IF v_parent_org_id IS NULL THEN
            IF v_root_tenant IS NULL THEN
                SELECT root_tenant_id INTO v_root_tenant FROM tenant_roots ORDER BY root_tenant_id LIMIT 1;
            END IF;
            SELECT id INTO v_parent_org_id
            FROM organizations
            WHERE root_tenant_id = v_root_tenant
              AND org_type IN ('agent', 'distributor', 'service_partner', 'manufacturer')
              AND deleted_at IS NULL AND status = 'active'
            ORDER BY CASE org_type WHEN 'agent' THEN 1 WHEN 'distributor' THEN 2 WHEN 'service_partner' THEN 3 ELSE 4 END
            LIMIT 1;
        END IF;

        IF v_parent_org_id IS NULL THEN
            RAISE WARNING 'Cannot find parent org for end user %, skipping', v_user.id;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        v_role_code := 'viewer';
        v_org_type := 'customer';
        v_data_scope := 'self';

        -- Create customer org under the parent.
        INSERT INTO organizations (root_tenant_id, parent_id, org_type, name, status)
        VALUES (v_root_tenant, v_parent_org_id, v_org_type, v_user.name, 'active')
        RETURNING id INTO v_org_id;

        INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
        VALUES (v_root_tenant, v_org_id, v_user.id, 'active')
        RETURNING id INTO v_membership_id;

        INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status)
        VALUES (v_root_tenant, v_org_id, v_membership_id, v_role_code, 'active')
        RETURNING id INTO v_role_assignment_id;

        FOR v_perm IN SELECT resource, action FROM role_permissions WHERE role = 5 AND is_allowed = true
        LOOP
            v_perm_code := v_perm.resource || ':' || v_perm.action;
            BEGIN
                INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
                VALUES (v_root_tenant, v_org_id, v_role_assignment_id, v_perm_code, v_data_scope);
            EXCEPTION WHEN unique_violation THEN NULL;
            END;
        END LOOP;

        v_count := v_count + 1;
    END LOOP;
    RAISE NOTICE 'Step 6 (end_users): processed=%, skipped=%', v_count, v_skipped;

    -- ================================================================
    -- Step 7: Verification - count users without memberships.
    -- ================================================================
    SELECT COUNT(*) INTO v_count
    FROM users u
    WHERE u.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM organization_memberships om WHERE om.user_id = u.id AND om.status = 'active');

    IF v_count > 0 THEN
        RAISE WARNING 'Migration complete but % users still have no organization membership', v_count;
    ELSE
        RAISE NOTICE 'Migration complete: all active users have organization memberships.';
    END IF;
END;
$$;

-- Reset the escape hatch.
RESET app.allow_hierarchy_change;
