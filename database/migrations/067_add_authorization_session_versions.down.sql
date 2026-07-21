DROP TRIGGER IF EXISTS trg_organization_subtree_authorization_version ON organizations;
DROP TRIGGER IF EXISTS trg_resource_grant_authorization_version ON resource_grants;
DROP TRIGGER IF EXISTS trg_permission_grant_authorization_version ON role_permission_grants;
DROP TRIGGER IF EXISTS trg_role_assignment_authorization_version ON membership_role_assignments;
DROP TRIGGER IF EXISTS trg_memberships_version_rotation ON organization_memberships;
DROP TRIGGER IF EXISTS trg_users_session_version_rotation ON users;
DROP FUNCTION IF EXISTS enforce_membership_version_rotation();
DROP FUNCTION IF EXISTS enforce_user_session_version_rotation();
DROP FUNCTION IF EXISTS bump_organization_subtree_authorization_version();
DROP FUNCTION IF EXISTS bump_resource_grant_authorization_version();
DROP FUNCTION IF EXISTS bump_resource_grant_subject_authorization_version(BIGINT, BIGINT, BIGINT);
DROP FUNCTION IF EXISTS bump_permission_grant_authorization_version();
DROP FUNCTION IF EXISTS bump_role_assignment_authorization_version();
DROP FUNCTION IF EXISTS bump_membership_authorization_version(BIGINT, BIGINT);

ALTER TABLE organization_memberships
    DROP CONSTRAINT IF EXISTS organization_memberships_authorization_version_check,
    DROP COLUMN IF EXISTS authorization_version;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_session_version_check,
    DROP COLUMN IF EXISTS session_version;
