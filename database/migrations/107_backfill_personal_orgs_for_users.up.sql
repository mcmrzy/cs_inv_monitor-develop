-- Migration 107: Backfill personal customer organizations for orphan users
--
-- 背景：自助注册（EmailRegister / PhoneRegister / JVerifyLogin）此前只写
-- users 表，不建立组织身份。组织权限体系（membership_role_assignments +
-- role_permission_grants + v_user_station_access / v_user_device_access 视图）
-- 完全依赖 organization_memberships，导致纯注册用户：
--   1. 登录响应 permissions 为空（网关非 GET 请求全部 403）
--   2. 视图无数据权限（自己创建的电站/设备 403 permission denied）
-- 注册流程已改为创建用户时同步建立个人 customer 组织身份（Go 侧
-- UserRepository.CreateUserWithOrgIdentity，角色=customer，挂 manufacturer
-- 根组织下）。本迁移为存量孤儿用户补建同样的身份，幂等可重放：
--   - 仅处理无活跃 membership 的活跃非管理员用户
--   - 个人组织以 code='personal-<user_id>' 标记，down 可精确回滚
--   - closure / tenant_roots 由 trg_organizations_insert_relations 自动维护
--   - 权限集与 RoleDefaultPermissions["customer"] 保持一致

DO $$
DECLARE
    v_user RECORD;
    v_root_tenant BIGINT;
    v_manufacturer_org BIGINT;
    v_org_id BIGINT;
    v_membership_id BIGINT;
    v_assignment_id BIGINT;
    v_count INTEGER := 0;
BEGIN
    -- manufacturer 根组织（多租户时取第一个）
    SELECT o.root_tenant_id, o.id INTO v_root_tenant, v_manufacturer_org
    FROM organizations o
    JOIN tenant_roots tr ON tr.root_tenant_id = o.root_tenant_id
    WHERE o.org_type = 'manufacturer'
      AND o.deleted_at IS NULL
      AND o.status = 'active'
    ORDER BY o.root_tenant_id
    LIMIT 1;

    IF v_manufacturer_org IS NULL THEN
        RAISE NOTICE 'Migration 107: no active manufacturer root org found, nothing to backfill';
        RETURN;
    END IF;

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
        INSERT INTO organizations (root_tenant_id, parent_id, org_type, code, name, status)
        VALUES (v_root_tenant, v_manufacturer_org, 'customer', 'personal-' || v_user.id, v_user.name, 'active')
        RETURNING id INTO v_org_id;

        INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
        VALUES (v_root_tenant, v_org_id, v_user.id, 'active')
        RETURNING id INTO v_membership_id;

        INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status, version)
        VALUES (v_root_tenant, v_org_id, v_membership_id, 'customer', 'active', 1)
        RETURNING id INTO v_assignment_id;

        INSERT INTO role_permission_grants (root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope)
        SELECT v_root_tenant, v_org_id, v_assignment_id, p.code, 'organization'
        FROM unnest(ARRAY[
            'dashboard:view',
            'devices:view', 'devices:create', 'devices:edit',
            'stations:view', 'stations:create', 'stations:edit',
            'alerts:view',
            'firmware:view',
            'notifications:view'
        ]) AS p(code)
        ON CONFLICT (role_assignment_id, permission_code) DO NOTHING;

        v_count := v_count + 1;
    END LOOP;

    RAISE NOTICE 'Migration 107: backfilled % orphan users', v_count;
END $$;
