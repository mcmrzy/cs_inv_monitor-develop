-- Migration 115: Backfill orphan users into the shared 「用户组织」
--
-- 背景：自助注册已改为在注册事务内建立个人 customer 组织身份（迁移 107），
-- 但仍有其它建户入口不会建身份（例如管理后台 CreateTenant 直接 INSERT users），
-- 这类用户没有活跃 organization_memberships，登录后 permissions 为空、
-- 数据视图无权限，且会话上下文退化成"本人充当租户根"的孤岛。
--
-- 本迁移做两件事：
--   1. 建立共享「用户组织」（code='default-users'），挂系统制造商根组织下。
--      根租户口径与迁移 075/107 一致：最低 root_tenant_id 的活跃 manufacturer 组织。
--   2. 为所有"活跃、非系统管理员、无活跃 membership"的用户，在该组织下补建
--      个人 customer 组织身份（organizations + membership + customer 角色 +
--      默认授权），与代码侧 UserRepository.CreateUserWithOrgIdentity 完全一致。
--
-- 为什么是"每个用户一个子组织"而不是同一个组织的多个成员：
--   v_user_station_access 的组织闭包分支会包含同组织成员，若注册用户直接成为
--   同一组织的成员，用户之间会互相看到并操作对方的电站。个人子组织只共享父
--   节点，闭包不会跨用户命中。设备侧 v_user_device_access 只看 devices.user_id
--   与显式绑定，本就与组织无关。
--
--   共享「用户组织」为什么是一整条链而不是单个组织：
--   validate_org_hierarchy 的规则是 agent←manufacturer、distributor←agent、
--   installer←distributor、customer←installer|manufacturer，承载个人 customer
--   组织的父节点只能落在 installer 层，因此需要补齐 agent / distributor 两级。
--   中间层不承载成员、不下挂其它渠道组织，只用于满足层级约束。
--
-- 幂等可重放：已有活跃 membership 的用户跳过；组织按 (root_tenant_id, LOWER(code))
-- 部分唯一索引判存；授权按 (role_assignment_id, permission_code) ON CONFLICT 去重。
-- closure / tenant_roots 均由 trg_organizations_insert_relations 自动维护，
-- 本迁移不直接改 closure，因此无需 app.allow_closure_write 逃生舱。

DO $$
DECLARE
    v_root_tenant BIGINT;
    v_manufacturer_org BIGINT;
    v_users_org BIGINT;
    v_parent BIGINT;
    v_org BIGINT;
    v_level RECORD;
    v_user RECORD;
    v_org_id BIGINT;
    v_membership_id BIGINT;
    v_assignment_id BIGINT;
    v_created INTEGER := 0;
BEGIN
    -- 1. 系统制造商根组织（多租户时取最低 root_tenant_id）。
    --    必须 JOIN tenant_roots：库里可能存在没有 tenant_roots 行的 manufacturer
    --    组织（历史遗留/直接插入），而 trg_organizations_insert_relations 在建子
    --    组织时会校验 root tenant 已注册，选中这类组织会直接 23503 失败。
    SELECT o.root_tenant_id, o.id INTO v_root_tenant, v_manufacturer_org
    FROM organizations o
    JOIN tenant_roots tr ON tr.root_tenant_id = o.root_tenant_id
    WHERE o.org_type = 'manufacturer'
      AND o.deleted_at IS NULL
      AND o.status = 'active'
    ORDER BY o.root_tenant_id
    LIMIT 1;

    IF v_manufacturer_org IS NULL THEN
        RAISE NOTICE 'Migration 115: no active manufacturer root org found, nothing to backfill';
        RETURN;
    END IF;

    -- 2. 共享「用户组织」链：agent → distributor → installer(用户组织)。
    --    逐级判存后创建，closure / tenant_roots 由触发器自动维护。
    v_parent := v_manufacturer_org;

    FOR v_level IN
        SELECT * FROM (VALUES
            ('agent',       'default-users-agent',       '用户组织·渠道层'),
            ('distributor', 'default-users-distributor', '用户组织·分销层'),
            ('installer',   'default-users',             '用户组织')
        ) AS t(org_type, code, name)
    LOOP
        v_org := NULL;
        SELECT id INTO v_org
        FROM organizations
        WHERE root_tenant_id = v_root_tenant
          AND LOWER(code) = v_level.code
          AND deleted_at IS NULL
        ORDER BY id
        LIMIT 1;

        IF v_org IS NULL THEN
            INSERT INTO organizations (root_tenant_id, parent_id, org_type, code, name, status)
            VALUES (v_root_tenant, v_parent, v_level.org_type, v_level.code, v_level.name, 'active')
            RETURNING id INTO v_org;
            RAISE NOTICE 'Migration 115: created shared org % (id=%)', v_level.code, v_org;
        END IF;

        v_parent := v_org;
    END LOOP;

    v_users_org := v_parent;

    -- 3. 为孤儿用户补建个人 customer 组织身份
    FOR v_user IN
        SELECT u.id, COALESCE(NULLIF(u.nickname, ''), 'User_' || u.id) AS name
        FROM users u
        WHERE u.deleted_at IS NULL
          AND u.status = 1
          AND u.is_system_admin = false
          AND NOT EXISTS (
              SELECT 1 FROM organization_memberships m
              WHERE m.user_id = u.id AND m.status = 'active'
          )
        ORDER BY u.id
    LOOP
        -- 个别用户可能已存在同 code 的个人组织（历史重放/部分失败），复用而不重建
        SELECT id INTO v_org_id
        FROM organizations
        WHERE root_tenant_id = v_root_tenant
          AND code = 'personal-' || v_user.id
          AND deleted_at IS NULL
        ORDER BY id
        LIMIT 1;

        IF v_org_id IS NULL THEN
            INSERT INTO organizations (root_tenant_id, parent_id, org_type, code, name, status)
            VALUES (v_root_tenant, v_users_org, 'customer', 'personal-' || v_user.id, v_user.name, 'active')
            RETURNING id INTO v_org_id;
        END IF;

        INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
        VALUES (v_root_tenant, v_org_id, v_user.id, 'active')
        ON CONFLICT (root_tenant_id, organization_id, user_id) WHERE status = 'active' DO NOTHING
        RETURNING id INTO v_membership_id;

        IF v_membership_id IS NULL THEN
            SELECT id INTO v_membership_id
            FROM organization_memberships
            WHERE root_tenant_id = v_root_tenant
              AND organization_id = v_org_id
              AND user_id = v_user.id
              AND status = 'active'
            LIMIT 1;
        END IF;

        IF v_membership_id IS NULL THEN
            CONTINUE;
        END IF;

        INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status, version)
        VALUES (v_root_tenant, v_org_id, v_membership_id, 'customer', 'active', 1)
        ON CONFLICT (membership_id, role_code) WHERE status = 'active' DO NOTHING
        RETURNING id INTO v_assignment_id;

        IF v_assignment_id IS NULL THEN
            SELECT id INTO v_assignment_id
            FROM membership_role_assignments
            WHERE membership_id = v_membership_id
              AND role_code = 'customer'
              AND status = 'active'
            LIMIT 1;
        END IF;

        IF v_assignment_id IS NULL THEN
            CONTINUE;
        END IF;

        -- 权限码与代码侧 RoleDefaultPermissions["customer"] 保持一致
        INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
        SELECT v_root_tenant, v_org_id, v_assignment_id, p.code, 'organization'
        FROM unnest(ARRAY[
            'dashboard:view',
            'devices:view', 'devices:create', 'devices:edit', 'devices:control',
            'stations:view', 'stations:create', 'stations:edit',
            'alerts:view',
            'firmware:view',
            'notifications:view'
        ]) AS p(code)
        ON CONFLICT (role_assignment_id, permission_code) DO NOTHING;

        v_created := v_created + 1;
    END LOOP;

    RAISE NOTICE 'Migration 115: backfilled % orphan users into shared users org %', v_created, v_users_org;
END $$;
