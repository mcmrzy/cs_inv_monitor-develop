-- Contract checks for migration 064. Run after applying migration 064.
-- All fixtures are rolled back.

BEGIN;

DO $$
DECLARE
    required_table TEXT;
BEGIN
    FOREACH required_table IN ARRAY ARRAY[
        'tenant_roots', 'organizations', 'organization_closure',
        'organization_memberships', 'membership_role_assignments',
        'role_permission_grants', 'authorization_resources', 'resource_grants',
        'organization_quotas', 'organization_quota_usage', 'invitations',
        'channel_migration_quarantine'
    ] LOOP
        IF to_regclass('public.' || required_table) IS NULL THEN
            RAISE EXCEPTION 'missing required table %', required_table;
        END IF;
    END LOOP;
END;
$$;

INSERT INTO users(id, phone, password_hash, role) VALUES
    (959001, 'migration064-sql-1', 'hash', 1),
    (959002, 'migration064-sql-2', 'hash', 5);

INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, code, name) VALUES
    (959100, 959100, NULL, 'manufacturer', 'SQL-ROOT-A', 'SQL Manufacturer A'),
    (959101, 959100, 959100, 'agent', 'SQL-AGENT-A', 'SQL Agent A'),
    (959102, 959100, 959101, 'distributor', 'SQL-DIST-A', 'SQL Distributor A'),
    (959103, 959100, 959102, 'customer', 'SQL-CUSTOMER-A', 'SQL Customer A'),
    (959200, 959200, NULL, 'manufacturer', 'SQL-ROOT-B', 'SQL Manufacturer B'),
    (959201, 959200, 959200, 'agent', 'SQL-AGENT-B', 'SQL Agent B');

DO $$
DECLARE
    actual_depth INTEGER;
    pair RECORD;
BEGIN
    FOR pair IN SELECT * FROM (VALUES
        (959100::BIGINT, 3), (959101::BIGINT, 2),
        (959102::BIGINT, 1), (959103::BIGINT, 0)
    ) AS expected(ancestor_id, depth)
    LOOP
        SELECT depth INTO actual_depth
        FROM organization_closure
        WHERE root_tenant_id=959100
          AND ancestor_id=pair.ancestor_id
          AND descendant_id=959103;
        IF actual_depth IS DISTINCT FROM pair.depth THEN
            RAISE EXCEPTION 'unexpected closure depth for %: %', pair.ancestor_id, actual_depth;
        END IF;
    END LOOP;

    BEGIN
        INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, name)
        VALUES (959110, 959100, 959100, 'customer', 'Illegal skipped customer');
        RAISE EXCEPTION 'expected illegal hierarchy to fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE organizations SET parent_id=959102 WHERE id=959101;
        RAISE EXCEPTION 'expected direct organization move to fail';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
END;
$$;

INSERT INTO organization_memberships(id, root_tenant_id, organization_id, user_id)
VALUES (959300, 959100, 959101, 959001);
INSERT INTO membership_role_assignments(id, root_tenant_id, organization_id, membership_id, role_code)
VALUES (959400, 959100, 959101, 959300, 'channel_manager');
INSERT INTO role_permission_grants(
    root_tenant_id, organization_id, role_assignment_id,
    permission_code, data_scope, scope_definition
) VALUES (
    959100, 959101, 959400,
    'device:unbind', 'organization_and_descendants', '{"organization_ids":[959101]}'::jsonb
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM role_permission_grants
        WHERE role_assignment_id=959400
          AND permission_code='device:unbind'
          AND data_scope='organization_and_descendants'
    ) THEN
        RAISE EXCEPTION 'permission and scope must be stored on one grant row';
    END IF;
END;
$$;

INSERT INTO invitations(
    root_tenant_id, organization_id, recipient, token_key_id, token_digest, expires_at
) VALUES (
    959100, 959101, ' Alice@Example.COM ', 'sql-key-1',
    decode(repeat('ab', 32), 'hex'), NOW() + INTERVAL '1 day'
);

DO $$
DECLARE
    token_columns TEXT[];
BEGIN
    SELECT ARRAY_AGG(column_name::TEXT ORDER BY column_name)
    INTO token_columns
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='invitations' AND column_name LIKE '%token%';
    IF token_columns <> ARRAY['token_digest', 'token_key_id']::TEXT[] THEN
        RAISE EXCEPTION 'invitations expose unexpected token columns: %', token_columns;
    END IF;

    BEGIN
        INSERT INTO invitations(
            root_tenant_id, organization_id, recipient, token_key_id, token_digest, expires_at
        ) VALUES (
            959100, 959101, 'alice@example.com', 'sql-key-2',
            decode(repeat('cd', 32), 'hex'), NOW() + INTERVAL '1 day'
        );
        RAISE EXCEPTION 'expected duplicate pending invitation to fail';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
END;
$$;

INSERT INTO organization_quotas(root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id) VALUES
    (959100, 959100, 'inventory_devices', 10, NULL),
    (959100, 959101, 'inventory_devices', 10, 959100);
SELECT consume_organization_quota(959100, 959101, 'inventory_devices', 7, 2);

DO $$
BEGIN
    BEGIN
        PERFORM consume_organization_quota(959100, 959101, 'inventory_devices', 0, 2);
        RAISE EXCEPTION 'expected quota overflow to fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

INSERT INTO authorization_resources(root_tenant_id, organization_id, resource_type, resource_id) VALUES
    (959100, 959101, 'device', 'SN-SQL-A'),
    (959200, 959201, 'device', 'SN-SQL-B');

DO $$
BEGIN
    BEGIN
        INSERT INTO resource_grants(
            root_tenant_id, organization_id, resource_type, resource_id,
            subject_type, subject_organization_id, permissions
        ) VALUES (
            959100, 959101, 'device', 'SN-SQL-B',
            'organization', 959101, ARRAY['view']::TEXT[]
        );
        RAISE EXCEPTION 'expected cross-tenant resource grant to fail';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;
