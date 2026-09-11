-- Migration 116: Revert the shared 「用户组织」 introduced by migration 115
--
-- 背景（为什么要撤）：115 把自助注册用户挂到同一个「用户组织」链下。组织必然
-- 属于某个 root_tenant_id，所以这一步等于让所有自助注册用户**共享同一个根租户**。
-- 而现有的横向越权防线是按根租户判定的，共享租户后全部失效，已由集成测试
-- tests/integration/cross_tenant_test.go 实测确认：
--   - 用户 B 可以转移用户 A 的设备           (TestCrossTenant_TransferDeviceNonAdmin)
--   - 用户 B 可以在列表里看到用户 A 的组织    (TestCrossTenant_ListOrgsOnlyOwnTenant)
--   - 用户 B 可以为用户 A 的设备生成领用码    (TestCrossTenant_GenerateClaimCodeForOtherTenantDevice)
-- 这些防线要改成基于所有权/组织成员身份才能支撑共享租户，属于另一批改动；
-- 在那之前必须回到"每用户一个租户根"的隔离模型。
--
-- 本迁移只撤销 115 建立的身份，使其恢复为"无活跃组织身份"的孤儿状态；
-- 用户在下次登录时由 auth_handler.generateLoginTokenPair 调用的
-- UserRepository.EnsureUserOrgIdentity 幂等补建**自己的**租户根与个人组织
-- （与迁移 107 的存量模型一致，用户之间互不可见）。
--
-- 只处理 code 前缀 default-users 的链，以及挂在链末 installer 之下的
-- personal-* 组织；不触碰其它租户下的存量个人组织。

DO $$
DECLARE
    v_chain_ids BIGINT[];
    v_users_org BIGINT;
    v_removed INTEGER := 0;
BEGIN
    SELECT array_agg(id) INTO v_chain_ids
    FROM organizations
    WHERE LOWER(code) LIKE 'default-users%'
      AND deleted_at IS NULL;

    IF v_chain_ids IS NULL THEN
        RAISE NOTICE 'Migration 116: no shared users org chain found, nothing to revert';
        RETURN;
    END IF;

    SELECT id INTO v_users_org
    FROM organizations
    WHERE LOWER(code) = 'default-users' AND deleted_at IS NULL
    LIMIT 1;

    -- closure 受 guard_organization_closure_mutation 保护，直接删需逃生舱
    SET LOCAL app.allow_closure_write = 'true';

    IF v_users_org IS NOT NULL THEN
        -- 115 建的个人组织：默认授权 → 角色分配 → 成员关系 → 组织
        DELETE FROM role_permission_grants g
        USING membership_role_assignments ra, organizations o
        WHERE g.role_assignment_id = ra.id
          AND o.id = ra.organization_id
          AND o.code LIKE 'personal-%'
          AND o.parent_id = v_users_org;

        DELETE FROM membership_role_assignments ra
        USING organizations o
        WHERE o.root_tenant_id = ra.root_tenant_id
          AND o.id = ra.organization_id
          AND o.code LIKE 'personal-%'
          AND o.parent_id = v_users_org;

        DELETE FROM organization_memberships m
        USING organizations o
        WHERE m.root_tenant_id = o.root_tenant_id
          AND m.organization_id = o.id
          AND o.code LIKE 'personal-%'
          AND o.parent_id = v_users_org;

        GET DIAGNOSTICS v_removed = ROW_COUNT;

        DELETE FROM organization_closure c
        USING organizations o
        WHERE c.descendant_id = o.id
          AND o.code LIKE 'personal-%'
          AND o.parent_id = v_users_org;
    END IF;

    -- 链自身的 closure 行
    DELETE FROM organization_closure
    WHERE descendant_id = ANY(v_chain_ids) OR ancestor_id = ANY(v_chain_ids);

    RESET app.allow_closure_write;

    -- 个人组织本体
    IF v_users_org IS NOT NULL THEN
        DELETE FROM organizations
        WHERE code LIKE 'personal-%' AND parent_id = v_users_org;
    END IF;

    -- 链本体：自下而上（installer → distributor → agent）
    DELETE FROM organizations WHERE LOWER(code) LIKE 'default-users%' AND deleted_at IS NULL;

    -- 迁移 115 的记录一并移除：其文件已删除，留着会让历史与实际不一致
    DELETE FROM schema_migrations WHERE version = 115;

    RAISE NOTICE 'Migration 116: reverted shared users org chain, removed % personal org memberships',
        v_removed;
END $$;
