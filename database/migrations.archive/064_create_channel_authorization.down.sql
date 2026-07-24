-- 059 down: remove channel authorization objects in reverse dependency order.

DROP TABLE IF EXISTS channel_migration_quarantine;
DROP TABLE IF EXISTS invitations;
DROP FUNCTION IF EXISTS consume_organization_quota(BIGINT, BIGINT, VARCHAR, BIGINT, BIGINT);
DROP FUNCTION IF EXISTS validate_organization_quota_limit() CASCADE;
DROP FUNCTION IF EXISTS validate_organization_quota_usage() CASCADE;
DROP TABLE IF EXISTS organization_quota_usage;
DROP TABLE IF EXISTS organization_quotas;
DROP TABLE IF EXISTS resource_grants;
DROP TABLE IF EXISTS authorization_resources;
DROP TABLE IF EXISTS role_permission_grants;
DROP TABLE IF EXISTS membership_role_assignments;
DROP TABLE IF EXISTS organization_memberships;
DROP FUNCTION IF EXISTS maintain_organization_insert_relations() CASCADE;
DROP FUNCTION IF EXISTS validate_organization_hierarchy() CASCADE;
DROP FUNCTION IF EXISTS guard_organization_closure_mutation() CASCADE;
DROP TABLE IF EXISTS organization_closure;
DROP TABLE IF EXISTS tenant_roots;
DROP TABLE IF EXISTS organizations;
