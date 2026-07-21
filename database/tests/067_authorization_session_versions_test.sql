-- Contract checks for migration 067. All fixtures are rolled back.
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='users'
          AND column_name='session_version' AND data_type='bigint'
    ) THEN
        RAISE EXCEPTION 'users.session_version is missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='organization_memberships'
          AND column_name='authorization_version' AND data_type='bigint'
    ) THEN
        RAISE EXCEPTION 'organization_memberships.authorization_version is missing';
    END IF;
END;
$$;

INSERT INTO users(id, phone, password_hash, role)
VALUES (962001, 'migration067-user', 'hash', 5);
INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, code, name)
VALUES (962100, 962100, NULL, 'manufacturer', 'SQL-062', 'SQL 062 Manufacturer');
INSERT INTO organization_memberships(id, root_tenant_id, organization_id, user_id)
VALUES (962200, 962100, 962100, 962001);

DO $$
DECLARE
    current_session BIGINT;
    current_authorization BIGINT;
BEGIN
    UPDATE users SET session_version=session_version+1 WHERE id=962001
        RETURNING session_version INTO current_session;
    UPDATE organization_memberships
       SET authorization_version=authorization_version+1
     WHERE id=962200
        RETURNING authorization_version INTO current_authorization;
    IF current_session <> 2 OR current_authorization <> 2 THEN
        RAISE EXCEPTION 'version increments are not durable';
    END IF;
END;
$$;

INSERT INTO membership_role_assignments(
    id, root_tenant_id, organization_id, membership_id, role_code, assigned_by
) VALUES (962300, 962100, 962100, 962200, 'viewer', 962001);

DO $$
DECLARE
    current_authorization BIGINT;
BEGIN
    SELECT authorization_version INTO current_authorization
      FROM organization_memberships WHERE id=962200;
    IF current_authorization <> 3 THEN
        RAISE EXCEPTION 'role mutation did not invalidate access context';
    END IF;
END;
$$;

ROLLBACK;
