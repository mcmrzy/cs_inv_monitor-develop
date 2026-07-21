//go:build integration

package integration

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestFreshDatabaseBaselineAndMigrations mirrors the production migrator:
// schema.sql is the version-22 baseline and numbered migrations after 22 are
// applied transactionally in order.
func TestFreshDatabaseBaselineAndMigrations(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")

	// The API test database is already on the latest baseline. Replaying every
	// historical migration there tests accidental idempotency, not the forward
	// upgrade path. Use a disposable database so 001..latest execute in order
	// against an actually empty PostgreSQL/TimescaleDB instance.
	adminCfg := cfg
	adminCfg.DBName = "postgres"
	adminPool := ConnectDB(t, adminCfg)
	defer adminPool.Close()

	ctx := context.Background()
	dbName := fmt.Sprintf("inv_migration_test_%d", time.Now().UnixNano())
	_, err := adminPool.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err, "create disposable migration database")

	migrationCfg := cfg
	migrationCfg.DBName = dbName
	pool := ConnectDB(t, migrationCfg)
	defer func() {
		pool.Close()
		_, _ = adminPool.Exec(ctx, `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1`, dbName)
		_, dropErr := adminPool.Exec(ctx, "DROP DATABASE IF EXISTS "+dbName)
		assert.NoError(t, dropErr, "drop disposable migration database")
	}()

	migrationsDir := findMigrationsDir(t)
	files := collectUpMigrations(t, migrationsDir)
	require.NotEmpty(t, files, "no migration files found")
	schemaPath := filepath.Join(filepath.Dir(migrationsDir), "schema.sql")
	schemaSQL, err := os.ReadFile(schemaPath)
	require.NoError(t, err, "read baseline schema")

	_, err = pool.Exec(ctx, `CREATE TABLE schema_migrations (
		version BIGINT PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`)
	require.NoError(t, err, "create migration history")

	const baselineVersion = 22
	baselineTx, err := pool.Begin(ctx)
	require.NoError(t, err)
	_, err = baselineTx.Exec(ctx, string(schemaSQL))
	require.NoError(t, err, "execute baseline schema")
	_, err = baselineTx.Exec(ctx, `INSERT INTO schema_migrations(version,name) VALUES(0,'baseline_schema')`)
	require.NoError(t, err)
	for _, f := range files {
		if f.Number > baselineVersion {
			continue
		}
		_, err = baselineTx.Exec(ctx,
			`INSERT INTO schema_migrations(version,name) VALUES($1,$2) ON CONFLICT DO NOTHING`,
			f.Number, f.Name)
		require.NoError(t, err)
	}
	require.NoError(t, baselineTx.Commit(ctx), "commit baseline schema")

	for _, f := range files {
		if f.Number <= baselineVersion {
			continue
		}
		if ok := t.Run(f.Name, func(t *testing.T) {
			sql, err := os.ReadFile(filepath.Join(migrationsDir, f.Name))
			require.NoError(t, err, "read migration file %s", f.Name)

			tx, err := pool.Begin(ctx)
			require.NoError(t, err)
			defer func() { _ = tx.Rollback(ctx) }()
			_, err = tx.Exec(ctx, string(sql))
			require.NoError(t, err, "execute migration %s", f.Name)
			_, err = tx.Exec(ctx,
				`INSERT INTO schema_migrations(version,name) VALUES($1,$2)`,
				f.Number, f.Name)
			require.NoError(t, err, "record migration %s", f.Name)
			require.NoError(t, tx.Commit(ctx), "commit migration %s", f.Name)
		}); !ok {
			break
		}
	}
}

func TestMigration064ChannelAuthorizationConstraints(t *testing.T) {
	withDisposableChannelMigrationDatabase(t, func(ctx context.Context, pool *pgxpool.Pool, migrationsDir string) {
		migration064 := readMigrationFile(t, migrationsDir, "064_create_channel_authorization.up.sql")
		for attempt := 1; attempt <= 2; attempt++ {
			_, err := pool.Exec(ctx, migration064)
			require.NoError(t, err, "migration 064 execution %d must be idempotent", attempt)
		}

		requiredTables := []string{
			"tenant_roots",
			"organizations",
			"organization_closure",
			"organization_memberships",
			"membership_role_assignments",
			"role_permission_grants",
			"authorization_resources",
			"resource_grants",
			"organization_quotas",
			"organization_quota_usage",
			"invitations",
			"channel_migration_quarantine",
		}
		for _, table := range requiredTables {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, table).Scan(&exists))
			assert.True(t, exists, "migration 064 must create %s", table)
		}

		_, err := pool.Exec(ctx, `
			INSERT INTO users(id, phone, password_hash, role) VALUES
				(59001, 'migration064-user-1', 'hash', 1),
				(59002, 'migration064-user-2', 'hash', 5)
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, code, name, status) VALUES
				(59100, 59100, NULL, 'manufacturer', 'ROOT-A', 'Manufacturer A', 'active'),
				(59101, 59100, 59100, 'agent', 'AGENT-A', 'Agent A', 'active'),
				(59102, 59100, 59101, 'distributor', 'DIST-A', 'Distributor A', 'active'),
				(59103, 59100, 59102, 'customer', 'CUSTOMER-A', 'Customer A', 'active'),
				(59200, 59200, NULL, 'manufacturer', 'ROOT-B', 'Manufacturer B', 'active'),
				(59201, 59200, 59200, 'agent', 'AGENT-B', 'Agent B', 'active')
		`)
		require.NoError(t, err)

		_, err = pool.Exec(ctx, `
			INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, name)
			VALUES (59300, 59300, NULL, 'agent', 'Invalid non-manufacturer root')
		`)
		require.Error(t, err, "every root tenant must be a manufacturer organization")
		var selfClosureCount int
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM organization_closure
			WHERE ancestor_id=descendant_id AND depth=0
			  AND descendant_id IN (59100,59101,59102,59103,59200,59201)
		`).Scan(&selfClosureCount))
		assert.Equal(t, 6, selfClosureCount, "every organization must receive a depth-zero self closure")
		var customerAncestors int
		require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM organization_closure WHERE root_tenant_id=59100 AND descendant_id=59103`).Scan(&customerAncestors))
		assert.Equal(t, 4, customerAncestors, "insert must copy every parent ancestor plus self")
		for ancestorID, expectedDepth := range map[int64]int{59100: 3, 59101: 2, 59102: 1, 59103: 0} {
			var depth int
			require.NoError(t, pool.QueryRow(ctx, `
				SELECT depth FROM organization_closure
				WHERE root_tenant_id=59100 AND ancestor_id=$1 AND descendant_id=59103
			`, ancestorID).Scan(&depth))
			assert.Equal(t, expectedDepth, depth, "customer closure depth from ancestor %d", ancestorID)
		}
		_, err = pool.Exec(ctx, `UPDATE organization_closure SET depth=1 WHERE root_tenant_id=59100 AND ancestor_id=59101 AND descendant_id=59101`)
		require.Error(t, err, "self closure depth other than zero must be rejected")
		_, err = pool.Exec(ctx, `INSERT INTO organization_closure(root_tenant_id,ancestor_id,descendant_id,depth) VALUES(59100,59103,59101,1)`)
		require.Error(t, err, "applications must not forge same-tenant closure ancestors")
		_, err = pool.Exec(ctx, `DELETE FROM organization_closure WHERE root_tenant_id=59100 AND ancestor_id=59100 AND descendant_id=59103`)
		require.Error(t, err, "applications must not remove real closure ancestors")

		_, err = pool.Exec(ctx, `
			INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, name)
			VALUES (59104, 59100, 59200, 'distributor', 'Cross tenant child')
		`)
		require.Error(t, err, "an organization parent from another root tenant must be rejected")
		_, err = pool.Exec(ctx, `INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,name) VALUES (59104,59100,59100,'customer','Skipped distributor')`)
		require.Error(t, err, "customer must not skip the agent/distributor hierarchy")
		_, err = pool.Exec(ctx, `INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name) VALUES (59104,59100,59101,'service_partner','SERVICE-A','Service partner')`)
		require.NoError(t, err, "service partner may attach to an agent")
		_, err = pool.Exec(ctx, `UPDATE organizations SET parent_id=59102 WHERE id=59104`)
		require.Error(t, err, "direct parent changes must be rejected until the governed move flow exists")
		_, err = pool.Exec(ctx, `UPDATE organizations SET root_tenant_id=59200 WHERE id=59104`)
		require.Error(t, err, "direct root changes must always be rejected")
		_, err = pool.Exec(ctx, `UPDATE organizations SET org_type='service_partner' WHERE id=59101`)
		require.Error(t, err, "organization type changes must not invalidate existing child hierarchy")
		_, err = pool.Exec(ctx, `INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,name) VALUES (59105,59100,59105,'agent','Self parent')`)
		require.Error(t, err, "an organization must not parent itself")

		_, err = pool.Exec(ctx, `UPDATE organizations SET deleted_at=NOW() WHERE id=59104`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name) VALUES (59106,59100,59100,'service_partner','service-a','Replacement service partner')`)
		require.NoError(t, err, "soft-deleted organization codes may be reused")
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_closure(root_tenant_id, ancestor_id, descendant_id, depth)
			VALUES (59100, 59100, 59201, 1)
		`)
		require.Error(t, err, "a closure edge across root tenants must be rejected")

		_, err = pool.Exec(ctx, `
			INSERT INTO organization_memberships(id, root_tenant_id, organization_id, user_id, status)
			VALUES (59300, 59100, 59101, 59001, 'active')
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_memberships(root_tenant_id, organization_id, user_id, status)
			VALUES (59100, 59101, 59001, 'active')
		`)
		require.Error(t, err, "only one active membership is allowed for an organization/user pair")
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_memberships(root_tenant_id, organization_id, user_id, status)
			VALUES (59200, 59101, 59002, 'active')
		`)
		require.Error(t, err, "membership organization and root tenant must match")

		_, err = pool.Exec(ctx, `
			INSERT INTO membership_role_assignments(id, root_tenant_id, organization_id, membership_id, role_code, status)
			VALUES
				(59400, 59100, 59101, 59300, 'channel_manager', 'active'),
				(59401, 59100, 59101, 59300, 'viewer', 'active')
		`)
		require.NoError(t, err, "one membership must support multiple role assignments")
		_, err = pool.Exec(ctx, `
			INSERT INTO role_permission_grants(
				root_tenant_id, organization_id, role_assignment_id,
				permission_code, data_scope, scope_definition
			) VALUES (
				59100, 59101, 59400,
				'device:unbind', 'organization_and_descendants', '{"organization_ids":[59101]}'::jsonb
			)
		`)
		require.NoError(t, err)
		var permissionCode, dataScope string
		var scopeDefinition string
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT permission_code, data_scope, scope_definition::text
			FROM role_permission_grants WHERE role_assignment_id=59400
		`).Scan(&permissionCode, &dataScope, &scopeDefinition))
		assert.Equal(t, "device:unbind", permissionCode)
		assert.Equal(t, "organization_and_descendants", dataScope)
		assert.JSONEq(t, `{"organization_ids":[59101]}`, scopeDefinition,
			"permission and data scope must be persisted on the same grant row")

		_, err = pool.Exec(ctx, `
			INSERT INTO invitations(
				root_tenant_id, organization_id, recipient, token_key_id, token_digest, status, expires_at
			) VALUES (
				59100, 59101, ' Alice@Example.COM ', 'invite-key-1', decode(repeat('ab',32),'hex'), 'pending', NOW()+INTERVAL '1 day'
			)
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO invitations(
				root_tenant_id, organization_id, recipient, token_key_id, token_digest, status, expires_at
			) VALUES (
				59100, 59101, 'alice@example.com', 'invite-key-2', decode(repeat('cd',32),'hex'), 'pending', NOW()+INTERVAL '1 day'
			)
		`)
		require.Error(t, err, "normalized recipient may have only one pending invitation per organization")

		rows, err := pool.Query(ctx, `
			SELECT column_name FROM information_schema.columns
			WHERE table_schema='public' AND table_name='invitations' AND column_name LIKE '%token%'
			ORDER BY column_name
		`)
		require.NoError(t, err)
		var tokenColumns []string
		for rows.Next() {
			var column string
			require.NoError(t, rows.Scan(&column))
			tokenColumns = append(tokenColumns, column)
		}
		rows.Close()
		require.NoError(t, rows.Err())
		assert.Equal(t, []string{"token_digest", "token_key_id"}, tokenColumns,
			"invitations must never persist a plaintext token")

		_, err = pool.Exec(ctx, `
			INSERT INTO organization_quotas(root_tenant_id, organization_id, resource_type, quota_limit)
			VALUES (59100, 59101, 'not_a_quota', 1)
		`)
		require.Error(t, err, "quota resource codes must come from the fixed contract")
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_quotas(root_tenant_id, organization_id, resource_type, quota_limit)
			VALUES (59100, 59101, 'inventory_devices', -1)
		`)
		require.Error(t, err, "quota limits must be non-negative")
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_quotas(root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id) VALUES
				(59100, 59100, 'inventory_devices', 10, NULL),
				(59100, 59101, 'inventory_devices', 10, 59100)
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_quota_usage(root_tenant_id, organization_id, resource_type, used_count)
			VALUES (59100, 59101, 'inventory_devices', -1)
		`)
		require.Error(t, err, "quota usage must be non-negative")
		_, err = pool.Exec(ctx, `
			INSERT INTO organization_quota_usage(root_tenant_id, organization_id, resource_type, used_count, reserved_count)
			VALUES (59100, 59101, 'inventory_devices', 9, 2)
		`)
		require.Error(t, err, "direct writes must enforce used plus reserved against the quota")
		_, err = pool.Exec(ctx, `SELECT consume_organization_quota(59100,59101,'inventory_devices',7,2)`)
		require.NoError(t, err, "the atomic quota entry point must reserve within the limit")
		_, err = pool.Exec(ctx, `SELECT consume_organization_quota(59100,59101,'inventory_devices',0,2)`)
		require.Error(t, err, "the atomic quota entry point must reject overflow")
		_, err = pool.Exec(ctx, `UPDATE organization_quotas SET quota_limit=8 WHERE root_tenant_id=59100 AND organization_id=59101 AND resource_type='inventory_devices'`)
		require.Error(t, err, "quota limits must not be lowered below current usage plus reservations")
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59100,'stations',1,NULL),(59100,59101,'stations',1,59100)`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59103,'stations',2,59101)`)
		require.Error(t, err, "a descendant quota must not exceed its inherited ancestor limit")
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59103,'stations',1,59104)`)
		require.Error(t, err, "quota inheritance must reference a real ancestor, not a sibling")
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59100,'members',10,NULL),(59100,59101,'members',5,59100)`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59103,'members',10,59100)`)
		require.Error(t, err, "a descendant must not bypass a stricter intermediate ancestor quota")
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59100,'claimed_devices',10,NULL),(59100,59103,'claimed_devices',10,59100)`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id) VALUES(59100,59101,'claimed_devices',5,59100)`)
		require.Error(t, err, "a stricter intermediate quota must not be added below an existing looser descendant quota")
		_, err = pool.Exec(ctx, `DELETE FROM organization_quotas WHERE root_tenant_id=59100 AND organization_id=59100 AND resource_type='stations'`)
		require.Error(t, err, "an inherited parent quota must not be deleted while descendants reference it")
		_, err = pool.Exec(ctx, `UPDATE organization_quota_usage SET resource_type='stations' WHERE root_tenant_id=59100 AND organization_id=59101 AND resource_type='inventory_devices'`)
		require.Error(t, err, "quota usage re-keying must revalidate against the destination limit")

		_, err = pool.Exec(ctx, `
			INSERT INTO authorization_resources(root_tenant_id, organization_id, resource_type, resource_id) VALUES
				(59100,59101,'device','SN-USER-GRANT'),
				(59100,59101,'device','SN-WRONG-USER-GRANT'),
				(59200,59201,'device','SN-CROSS-TENANT')
		`)
		require.NoError(t, err)

		_, err = pool.Exec(ctx, `
			INSERT INTO resource_grants(
				root_tenant_id, organization_id, resource_type, resource_id,
				subject_type, subject_organization_id, permissions
			) VALUES (
				59100, 59101, 'device', 'SN-CROSS-TENANT',
				'organization', 59101, ARRAY['view']::text[]
			)
		`)
		require.Error(t, err, "a same-tenant subject must not grant a resource registered in another tenant")
		_, err = pool.Exec(ctx, `
			INSERT INTO resource_grants(
				root_tenant_id, organization_id, resource_type, resource_id,
				subject_type, subject_organization_id, subject_user_id,
				subject_membership_id, permissions
			) VALUES (
				59100, 59101, 'device', 'SN-USER-GRANT',
				'user', 59101, 59001, 59300, ARRAY['view']::text[]
			)
		`)
		require.NoError(t, err, "a user resource grant must be backed by a same-tenant membership")
		_, err = pool.Exec(ctx, `
			INSERT INTO resource_grants(
				root_tenant_id, organization_id, resource_type, resource_id,
				subject_type, subject_organization_id, subject_user_id,
				subject_membership_id, permissions
			) VALUES (
				59100, 59101, 'device', 'SN-WRONG-USER-GRANT',
				'user', 59101, 59002, 59300, ARRAY['view']::text[]
			)
		`)
		require.Error(t, err, "a user grant must not borrow another user's membership")

		_, err = pool.Exec(ctx, `DELETE FROM organizations WHERE id=59101`)
		require.Error(t, err, "channel authorization references must use ON DELETE RESTRICT")

		contractSQL, readErr := os.ReadFile(filepath.Join(filepath.Dir(migrationsDir), "tests", "064_channel_authorization_test.sql"))
		require.NoError(t, readErr, "read migration 064 SQL contract test")
		_, err = pool.Exec(ctx, string(contractSQL))
		require.NoError(t, err, "execute migration 064 SQL contract test")

		for _, functionName := range []string{
			"validate_organization_hierarchy",
			"maintain_organization_insert_relations",
			"validate_organization_quota_usage",
			"consume_organization_quota",
		} {
			var definition string
			var config []string
			require.NoError(t, pool.QueryRow(ctx, `
				SELECT pg_get_functiondef(p.oid), COALESCE(p.proconfig, ARRAY[]::TEXT[])
				FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
				WHERE n.nspname='public' AND p.proname=$1
				ORDER BY p.oid LIMIT 1
			`, functionName).Scan(&definition, &config))
			assert.Contains(t, strings.ToLower(strings.Join(config, ",")), "search_path=pg_catalog, public, pg_temp",
				"security-sensitive function %s must pin a trusted search_path", functionName)
			assert.Contains(t, definition, "public.", "security-sensitive function %s must schema-qualify business relations", functionName)
		}

		for _, indexName := range []string{
			"idx_role_assignments_membership_fk",
			"idx_resource_grants_resource_owner_fk",
			"idx_resource_grants_subject_membership_fk",
			"idx_organization_quotas_inherited_fk",
			"idx_invitations_organization_fk",
		} {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, indexName).Scan(&exists))
			assert.True(t, exists, "migration 064 must create child-side FK index %s", indexName)
		}
	})
}

func TestMigration065AuditOutboxContracts(t *testing.T) {
	withDisposableChannelMigrationDatabase(t, func(ctx context.Context, pool *pgxpool.Pool, migrationsDir string) {
		migration064 := readMigrationFile(t, migrationsDir, "064_create_channel_authorization.up.sql")
		migration065 := readMigrationFile(t, migrationsDir, "065_extend_audit_outbox.up.sql")
		migration065Down := readMigrationFile(t, migrationsDir, "065_extend_audit_outbox.down.sql")
		_, err := pool.Exec(ctx, migration064)
		require.NoError(t, err)
		for attempt := 1; attempt <= 2; attempt++ {
			_, err = pool.Exec(ctx, migration065)
			require.NoError(t, err, "migration 065 execution %d must be idempotent", attempt)
		}

		var resourceIDType string
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT data_type FROM information_schema.columns
			WHERE table_schema='public' AND table_name='audit_logs' AND column_name='resource_id'
		`).Scan(&resourceIDType))
		assert.Equal(t, "text", resourceIDType)

		requiredAuditColumns := []string{
			"root_tenant_id", "active_organization_id", "request_id", "result",
			"failure_reason", "before_data", "after_data", "event_schema_version",
		}
		for _, column := range requiredAuditColumns {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `
				SELECT EXISTS (
					SELECT 1 FROM information_schema.columns
					WHERE table_schema='public' AND table_name='audit_logs' AND column_name=$1
				)
			`, column).Scan(&exists))
			assert.True(t, exists, "audit_logs must contain %s", column)
		}

		_, err = pool.Exec(ctx, `
			INSERT INTO users(id, phone, password_hash, role)
			VALUES (60001, 'migration065-actor', 'hash', 1);
			INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, name, status) VALUES
				(60100, 60100, NULL, 'manufacturer', 'Audit Manufacturer', 'active'),
				(60101, 60100, 60100, 'agent', 'Audit Agent', 'active'),
				(60200, 60200, NULL, 'manufacturer', 'Other Manufacturer', 'active')
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO audit_logs(
				operator_id, action, resource_type, resource_id,
				root_tenant_id, active_organization_id, request_id, result
			) VALUES (60001, 'view', 'device', 'SN-CROSS', 60100, 60200, 'request-cross', 'denied')
		`)
		require.Error(t, err, "audit active organization must belong to the declared root tenant")
		_, err = pool.Exec(ctx, `
			INSERT INTO audit_logs(
				operator_id, action, resource_type, resource_id,
				root_tenant_id, active_organization_id, request_id, result
			) VALUES (60001, 'view', 'device', 'SN-NULL-ROOT', NULL, 60101, 'request-null-root', 'denied')
		`)
		require.Error(t, err, "an audit active organization requires a verifiable root tenant")
		_, err = pool.Exec(ctx, `
			INSERT INTO audit_logs(
				operator_id, action, resource_type, resource_id,
				root_tenant_id, active_organization_id, request_id, result,
				before_data, after_data, event_schema_version
			) VALUES (
				60001, 'claim', 'device', 'SN-TEXT-RESOURCE',
				60100, 60100, 'request-060', 'success',
				NULL, '{"status":"claimed"}'::jsonb, 1
			)
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `UPDATE audit_logs SET result='failed' WHERE request_id='request-060'`)
		require.Error(t, err, "audit records must reject UPDATE")
		_, err = pool.Exec(ctx, `DELETE FROM audit_logs WHERE request_id='request-060'`)
		require.Error(t, err, "audit records must reject DELETE")
		var publicAuditMutationGrants int
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM information_schema.table_privileges
			WHERE table_schema='public' AND table_name='audit_logs'
			  AND grantee='PUBLIC' AND privilege_type IN ('UPDATE','DELETE')
		`).Scan(&publicAuditMutationGrants))
		assert.Zero(t, publicAuditMutationGrants, "PUBLIC must never receive audit mutation privileges")

		_, err = pool.Exec(ctx, `
			INSERT INTO idempotency_responses(
				root_tenant_id, actor_id, endpoint, idempotency_key,
				request_fingerprint, response_status, response_body
			) VALUES (
				60101, 60001, 'POST /devices/claims', 'idem-child-root',
				decode(repeat('55',32),'hex'), 200, '{"code":0}'::jsonb
			)
		`)
		require.Error(t, err, "a child organization cannot masquerade as root_tenant_id")
		_, err = pool.Exec(ctx, `
			INSERT INTO idempotency_responses(
				root_tenant_id, actor_id, endpoint, idempotency_key,
				request_fingerprint, response_status, response_body
			) VALUES (
				60100, 60001, 'POST /devices/claims', 'idem-060-0001',
				decode(repeat('11',32),'hex'), 200, '{"code":0}'::jsonb
			)
		`)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO idempotency_responses(
				root_tenant_id, actor_id, endpoint, idempotency_key,
				request_fingerprint, response_status, response_body
			) VALUES (
				60100, 60001, 'POST /devices/claims', 'idem-060-failed',
				decode(repeat('33',32),'hex'), 409, '{"code":"conflict"}'::jsonb
			)
		`)
		require.Error(t, err, "failed responses must not be stored in the success idempotency table")
		_, err = pool.Exec(ctx, `
			INSERT INTO idempotency_responses(
				root_tenant_id, actor_id, endpoint, idempotency_key,
				request_fingerprint, response_status, response_body
			) VALUES (
				60100, 60001, 'POST /devices/claims', 'idem-060-failed',
				decode(repeat('44',32),'hex'), 201, '{"code":0}'::jsonb
			)
		`)
		require.NoError(t, err, "a rejected response must not consume the idempotency key")
		_, err = pool.Exec(ctx, `
			INSERT INTO idempotency_responses(
				root_tenant_id, actor_id, endpoint, idempotency_key,
				request_fingerprint, response_status, response_body
			) VALUES (
				60100, 60001, 'POST /devices/claims', 'idem-060-0001',
				decode(repeat('22',32),'hex'), 201, '{"code":0}'::jsonb
			)
		`)
		require.Error(t, err, "idempotency response identity must be unique within actor and endpoint")

		eventID := "00000000-0000-4000-8000-000000000060"
		_, err = pool.Exec(ctx, `
			INSERT INTO transactional_outbox(
				event_id, root_tenant_id, aggregate_type, aggregate_id,
				event_type, event_schema_version, envelope, status,
				attempt_count, max_attempts, next_attempt_at
			) VALUES (
				$1, 60100, 'device', 'SN-TEXT-RESOURCE',
				'asset-transfer', '1.0', '{"schema_version":"1.0"}'::jsonb, 'pending',
				0, 10, NOW()
			)
		`, eventID)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO transactional_outbox(
				event_id, root_tenant_id, aggregate_type, aggregate_id,
				event_type, event_schema_version, envelope
			) VALUES ($1, 60100, 'device', 'another', 'asset-transfer', '1.0', '{}'::jsonb)
		`, eventID)
		require.Error(t, err, "transactional outbox event_id must be globally unique")

		requiredOutboxColumns := []string{
			"event_id", "event_schema_version", "envelope", "status", "attempt_count",
			"max_attempts", "next_attempt_at", "locked_at", "locked_by", "last_error", "published_at",
		}
		for _, column := range requiredOutboxColumns {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `
				SELECT EXISTS (
					SELECT 1 FROM information_schema.columns
					WHERE table_schema='public' AND table_name='transactional_outbox' AND column_name=$1
				)
			`, column).Scan(&exists))
			assert.True(t, exists, "transactional_outbox must contain %s", column)
		}
		for _, indexName := range []string{"idx_audit_logs_active_org_fk", "idx_audit_logs_operator_fk", "idx_idempotency_responses_actor_fk"} {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, indexName).Scan(&exists))
			assert.True(t, exists, "migration 065 must create child-side FK index %s", indexName)
		}

		_, err = pool.Exec(ctx, migration065Down)
		require.Error(t, err, "down migration must block lossy TEXT-to-BIGINT conversion")
		var preservedResourceID string
		require.NoError(t, pool.QueryRow(ctx, `SELECT resource_id FROM audit_logs WHERE request_id='request-060'`).Scan(&preservedResourceID))
		assert.Equal(t, "SN-TEXT-RESOURCE", preservedResourceID, "failed down migration must preserve audit data")
	})

	withDisposableChannelMigrationDatabase(t, func(ctx context.Context, pool *pgxpool.Pool, migrationsDir string) {
		migration064 := readMigrationFile(t, migrationsDir, "064_create_channel_authorization.up.sql")
		migration064Down := readMigrationFile(t, migrationsDir, "064_create_channel_authorization.down.sql")
		migration065 := readMigrationFile(t, migrationsDir, "065_extend_audit_outbox.up.sql")
		migration065Down := readMigrationFile(t, migrationsDir, "065_extend_audit_outbox.down.sql")
		_, err := pool.Exec(ctx, migration064)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, migration065)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, migration065Down)
		require.NoError(t, err, "down migration must succeed when every audit resource_id is numeric or null")

		var resourceIDType string
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT data_type FROM information_schema.columns
			WHERE table_schema='public' AND table_name='audit_logs' AND column_name='resource_id'
		`).Scan(&resourceIDType))
		assert.Equal(t, "bigint", resourceIDType)
		for _, table := range []string{"idempotency_responses", "transactional_outbox"} {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, table).Scan(&exists))
			assert.False(t, exists, "down migration must remove %s", table)
		}

		_, err = pool.Exec(ctx, migration064Down)
		require.NoError(t, err, "migration 064 down must succeed after migration 065 down")
		_, err = pool.Exec(ctx, migration064Down)
		require.NoError(t, err, "migration 064 down must be idempotent after a partial rollback")
		var organizationsExist bool
		require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.organizations') IS NOT NULL`).Scan(&organizationsExist))
		assert.False(t, organizationsExist)
		_, err = pool.Exec(ctx, migration064)
		require.NoError(t, err, "migration 064 must be re-applicable after down")
		_, err = pool.Exec(ctx, migration065)
		require.NoError(t, err, "migration 065 must be re-applicable after a safe down")
	})
}

func TestMigration066ChannelBackfillControlContracts(t *testing.T) {
	withDisposableChannelMigrationDatabase(t, func(ctx context.Context, pool *pgxpool.Pool, migrationsDir string) {
		migration064 := readMigrationFile(t, migrationsDir, "064_create_channel_authorization.up.sql")
		migration066 := readMigrationFile(t, migrationsDir, "066_create_channel_backfill_control.up.sql")
		migration066Down := readMigrationFile(t, migrationsDir, "066_create_channel_backfill_control.down.sql")
		_, err := pool.Exec(ctx, migration064)
		require.NoError(t, err)
		for attempt := 1; attempt <= 2; attempt++ {
			_, err = pool.Exec(ctx, migration066)
			require.NoError(t, err, "migration 066 execution %d must be idempotent", attempt)
		}

		for _, table := range []string{
			"channel_migration_runs", "channel_migration_checkpoints", "channel_migration_items",
			"channel_migration_entity_map", "channel_migration_shadow_diffs",
		} {
			var exists bool
			require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, table).Scan(&exists))
			assert.True(t, exists, "migration 066 must create %s", table)
		}

		runID := "00000000-0000-4000-8000-000000000061"
		digest := strings.Repeat("a", 64)
		_, err = pool.Exec(ctx, `
			INSERT INTO channel_migration_runs(id,job_name,mapping_digest,source_digest,source_watermark)
			VALUES($1,'backfill-organizations-v1',$2,$2,10)
		`, runID, digest)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO channel_migration_checkpoints(run_id,job_name,mapping_digest,next_ordinal)
			VALUES($1,'backfill-organizations-v1',$2,0)
		`, runID, digest)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO channel_migration_items(
				run_id,source_table,source_key,source_user_id,ordinal,source_fingerprint,expected
			) VALUES($1,'users','1',1,0,$2,'{}'::jsonb)
		`, runID, digest)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, `
			INSERT INTO channel_migration_items(
				run_id,source_table,source_key,source_user_id,ordinal,source_fingerprint,expected
			) VALUES($1,'users','2',2,0,$2,'{}'::jsonb)
		`, runID, digest)
		require.Error(t, err, "a run must not contain duplicate work ordinals")
		_, err = pool.Exec(ctx, `UPDATE channel_migration_items SET status='processing' WHERE run_id=$1 AND source_key='1'`, runID)
		require.Error(t, err, "processing items must always carry a lease owner and expiry")

		_, err = pool.Exec(ctx, migration066Down)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, migration066Down)
		require.NoError(t, err, "migration 066 down must be idempotent")
		var runsExist bool
		require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.channel_migration_runs') IS NOT NULL`).Scan(&runsExist))
		assert.False(t, runsExist)
	})
}

// TestMigration011ModelFieldCompatibility covers both historical table names.
// The singular table receives its two legacy columns; the canonical plural
// table already has normalized equivalents and must not be polluted with them.
func TestMigration011ModelFieldCompatibility(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	upSQL, err := os.ReadFile(filepath.Join(migrationsDir, "011_add_group_name_and_control_params.up.sql"))
	require.NoError(t, err)

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, `SET LOCAL search_path TO pg_temp`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `CREATE TEMP TABLE device_model_field (id BIGINT PRIMARY KEY)`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, string(upSQL))
	require.NoError(t, err)
	_, err = tx.Exec(ctx, string(upSQL))
	require.NoError(t, err, "migration 011 must be idempotent for the legacy table")

	var legacyColumns int
	err = tx.QueryRow(ctx, `
		SELECT count(*)
		FROM pg_attribute
		WHERE attrelid = to_regclass('device_model_field')
		  AND attname IN ('group_name', 'control_params')
		  AND NOT attisdropped
	`).Scan(&legacyColumns)
	require.NoError(t, err)
	assert.Equal(t, 2, legacyColumns)

	_, err = tx.Exec(ctx, `DROP TABLE device_model_field`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE device_model_fields (
			id BIGINT PRIMARY KEY,
			group_code VARCHAR(32) NOT NULL,
			parameter_schema JSONB NOT NULL DEFAULT '{}'::jsonb
		)
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, string(upSQL))
	require.NoError(t, err)

	var unexpectedColumns int
	err = tx.QueryRow(ctx, `
		SELECT count(*)
		FROM pg_attribute
		WHERE attrelid = to_regclass('device_model_fields')
		  AND attname IN ('group_name', 'control_params')
		  AND NOT attisdropped
	`).Scan(&unexpectedColumns)
	require.NoError(t, err)
	assert.Zero(t, unexpectedColumns, "migration 011 must preserve the canonical plural contract")

	_, err = tx.Exec(ctx, `DROP TABLE device_model_fields`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, string(upSQL))
	require.NoError(t, err, "migration 011 must safely skip when neither table exists")
}

// TestMigration016TimestampCompatibility verifies the old upgrade path with
// dependent view rules, then reruns the migration against the resulting
// canonical TIMESTAMPTZ shape to prove that it performs no redundant ALTER or
// view replacement.
func TestMigration016TimestampCompatibility(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	upSQL, err := os.ReadFile(filepath.Join(migrationsDir, "016_fix_timestamp_timezone.up.sql"))
	require.NoError(t, err)

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, `
		SET LOCAL search_path TO pg_temp;
		CREATE TEMP TABLE devices (
			deleted_at TIMESTAMP,
			created_at TIMESTAMP,
			updated_at TIMESTAMP,
			last_online_at TIMESTAMP
		);
		CREATE TEMP TABLE device_telemetry (
			time TIMESTAMP,
			created_at TIMESTAMP
		);
		CREATE TEMP VIEW v_user_device_access AS
			SELECT deleted_at FROM devices WHERE deleted_at IS NULL;
		CREATE TEMP VIEW v_device_latest AS
			SELECT time, created_at FROM device_telemetry;
		COMMENT ON VIEW v_device_latest IS 'migration-016-view-comment';
		INSERT INTO devices(deleted_at, created_at, updated_at, last_online_at)
		VALUES (NULL, TIMESTAMP '2026-01-02 03:04:05', TIMESTAMP '2026-01-02 03:04:05', NULL);
		INSERT INTO device_telemetry(time, created_at)
		VALUES (TIMESTAMP '2026-01-02 03:04:05', TIMESTAMP '2026-01-02 03:04:06');
	`)
	require.NoError(t, err)

	_, err = tx.Exec(ctx, string(upSQL))
	require.NoError(t, err, "migration 016 must recreate dependent views around real conversions")

	for _, target := range []struct {
		table  string
		column string
	}{
		{"devices", "deleted_at"},
		{"devices", "created_at"},
		{"device_telemetry", "time"},
		{"device_telemetry", "created_at"},
	} {
		var dataType string
		err = tx.QueryRow(ctx, `
			SELECT format_type(atttypid, atttypmod)
			FROM pg_attribute
			WHERE attrelid = to_regclass($1) AND attname = $2 AND NOT attisdropped
		`, target.table, target.column).Scan(&dataType)
		require.NoError(t, err)
		assert.Equal(t, "timestamp with time zone", dataType, "%s.%s", target.table, target.column)
	}

	var dataTime time.Time
	err = tx.QueryRow(ctx, `SELECT time FROM v_device_latest`).Scan(&dataTime)
	require.NoError(t, err)
	assert.True(t, dataTime.Equal(time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)))

	var viewComment string
	err = tx.QueryRow(ctx, `SELECT obj_description(to_regclass('v_device_latest'), 'pg_class')`).Scan(&viewComment)
	require.NoError(t, err)
	assert.Equal(t, "migration-016-view-comment", viewComment)

	var latestOID, accessOID uint32
	err = tx.QueryRow(ctx, `SELECT to_regclass('v_device_latest')::oid, to_regclass('v_user_device_access')::oid`).Scan(&latestOID, &accessOID)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, string(upSQL))
	require.NoError(t, err, "migration 016 must be idempotent on canonical TIMESTAMPTZ columns")

	var latestOIDAfter, accessOIDAfter uint32
	err = tx.QueryRow(ctx, `SELECT to_regclass('v_device_latest')::oid, to_regclass('v_user_device_access')::oid`).Scan(&latestOIDAfter, &accessOIDAfter)
	require.NoError(t, err)
	assert.Equal(t, latestOID, latestOIDAfter, "already-normalized latest view must not be replaced")
	assert.Equal(t, accessOID, accessOIDAfter, "already-normalized access view must not be replaced")
}

// TestBaselineCommandAndInstallerRepair exercises migration 043 against the
// exact reduced table shapes produced by the old baseline. It also verifies
// idempotency and that down preserves objects which predated migration 043.
func TestBaselineCommandAndInstallerRepair(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	readSQL := func(name string) string {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		return string(data)
	}
	upSQL := readSQL("043_repair_baseline_device_command_and_installer.up.sql")
	downSQL := readSQL("043_repair_baseline_device_command_and_installer.down.sql")

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	createOldBaseline := `
		CREATE TEMP TABLE device_cmd_logs (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			cmd VARCHAR(50) NOT NULL,
			result VARCHAR(20),
			message TEXT,
			sent_at TIMESTAMPTZ DEFAULT NOW()
		);
		CREATE TEMP TABLE devices (
			id BIGSERIAL PRIMARY KEY,
			sn VARCHAR(50) NOT NULL UNIQUE,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		SET LOCAL search_path TO pg_temp;
	`
	_, err = tx.Exec(ctx, createOldBaseline)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err, "migration 043 up must be idempotent")

	columnExists := func(table, column string) bool {
		t.Helper()
		var exists bool
		require.NoError(t, tx.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM pg_attribute
				WHERE attrelid=to_regclass($1) AND attname=$2 AND NOT attisdropped
			)
		`, table, column).Scan(&exists))
		return exists
	}
	indexExists := func(name string) bool {
		t.Helper()
		var exists bool
		require.NoError(t, tx.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, name).Scan(&exists))
		return exists
	}

	for _, column := range []string{"task_id", "params", "status", "data"} {
		assert.True(t, columnExists("device_cmd_logs", column), "043 should add device_cmd_logs.%s", column)
	}
	assert.True(t, columnExists("devices", "installer_id"), "043 should add devices.installer_id")
	for _, index := range []string{
		"idx_cmd_logs_task_id",
		"idx_cmd_logs_status",
		"idx_cmd_logs_sn_created",
		"idx_devices_installer",
	} {
		assert.True(t, indexExists(index), "043 should add index %s", index)
	}

	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)
	for _, column := range []string{"task_id", "params", "status", "data"} {
		assert.False(t, columnExists("device_cmd_logs", column), "down should remove 043-owned device_cmd_logs.%s", column)
	}
	assert.False(t, columnExists("devices", "installer_id"), "down should remove 043-owned devices.installer_id")

	// Recreate the historical-migration shape. Since these objects predate 043
	// and carry no ownership marker, both up and down must leave them intact.
	_, err = tx.Exec(ctx, `
		DROP TABLE device_cmd_logs, devices;
		CREATE TEMP TABLE device_cmd_logs (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			task_id VARCHAR(64),
			cmd VARCHAR(50) NOT NULL,
			params JSONB DEFAULT '{}'::jsonb,
			status VARCHAR(20) DEFAULT 'pending',
			result VARCHAR(20),
			message TEXT,
			data JSONB DEFAULT '{}'::jsonb,
			sent_at TIMESTAMPTZ DEFAULT NOW()
		);
		CREATE INDEX idx_cmd_logs_task_id ON device_cmd_logs(task_id);
		CREATE INDEX idx_cmd_logs_status ON device_cmd_logs(status);
		CREATE INDEX idx_cmd_logs_sn_created ON device_cmd_logs(device_sn, sent_at DESC);
		CREATE TEMP TABLE devices (
			id BIGSERIAL PRIMARY KEY,
			sn VARCHAR(50) NOT NULL UNIQUE,
			installer_id BIGINT,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE INDEX idx_devices_installer ON devices(installer_id);
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)

	for _, column := range []string{"task_id", "params", "status", "data"} {
		assert.True(t, columnExists("device_cmd_logs", column), "down must preserve preexisting device_cmd_logs.%s", column)
	}
	assert.True(t, columnExists("devices", "installer_id"), "down must preserve preexisting devices.installer_id")
	for _, index := range []string{
		"idx_cmd_logs_task_id",
		"idx_cmd_logs_status",
		"idx_cmd_logs_sn_created",
		"idx_devices_installer",
	} {
		assert.True(t, indexExists(index), "down must preserve preexisting index %s", index)
	}
}

// TestBaselinePerformanceIndexRepair exercises migration 044 against the
// reduced table shapes that old baseline_version=22 databases exposed. It
// verifies the useful index definitions, idempotency, reversible ownership,
// and preservation of indexes which predated migration 044.
func TestBaselinePerformanceIndexRepair(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	readSQL := func(name string) string {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		return string(data)
	}
	upSQL := readSQL("044_repair_baseline_performance_indexes.up.sql")
	downSQL := readSQL("044_repair_baseline_performance_indexes.down.sql")

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE devices (
			user_id BIGINT NOT NULL,
			station_id BIGINT,
			deleted_at TIMESTAMPTZ,
			status SMALLINT NOT NULL DEFAULT 0,
			last_online_at TIMESTAMPTZ
		);
		CREATE TEMP TABLE alarms (
			device_sn VARCHAR(50) NOT NULL,
			status SMALLINT NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE TEMP TABLE stations (
			user_id BIGINT NOT NULL,
			deleted_at TIMESTAMPTZ
		);
		CREATE TEMP TABLE device_alarms (
			device_sn VARCHAR(50) NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		SET LOCAL search_path TO pg_temp;
	`)
	require.NoError(t, err)

	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err, "migration 044 up must be idempotent")

	indexExists := func(name string) bool {
		t.Helper()
		var exists bool
		require.NoError(t, tx.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, name).Scan(&exists))
		return exists
	}
	indexDefinition := func(name string) string {
		t.Helper()
		var definition string
		require.NoError(t, tx.QueryRow(ctx, `SELECT pg_get_indexdef(to_regclass($1))`, name).Scan(&definition))
		return definition
	}

	expectedDefinitions := map[string][]string{
		"idx_devices_user_station_deleted": {"(user_id, station_id, deleted_at)", "deleted_at IS NULL"},
		"idx_devices_status_online":        {"(status, last_online_at DESC)", "status = 1"},
		"idx_alarms_device_time":           {"(device_sn, created_at DESC)"},
		"idx_alarms_pending":               {"(status, created_at DESC)", "status = 0"},
		"idx_stations_user_deleted":        {"(user_id, deleted_at)", "deleted_at IS NULL"},
		"idx_device_alarms_sn_time":        {"(device_sn, created_at DESC)"},
	}
	for index, fragments := range expectedDefinitions {
		assert.True(t, indexExists(index), "044 should add index %s", index)
		definition := indexDefinition(index)
		for _, fragment := range fragments {
			assert.Contains(t, definition, fragment, "%s definition", index)
		}

		var marker string
		require.NoError(t, tx.QueryRow(ctx, `
			SELECT obj_description(to_regclass($1), 'pg_class')
		`, index).Scan(&marker))
		assert.Equal(t, "migration 044 baseline index repair", marker)
	}

	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)
	for index := range expectedDefinitions {
		assert.False(t, indexExists(index), "down should remove 044-owned index %s", index)
	}

	// Recreate the historical migration-002 shape. These indexes carry no 044
	// marker, so an up/down cycle must leave them intact.
	_, err = tx.Exec(ctx, `
		CREATE INDEX idx_devices_user_station_deleted
			ON devices(user_id, station_id, deleted_at) WHERE deleted_at IS NULL;
		CREATE INDEX idx_devices_status_online
			ON devices(status, last_online_at DESC) WHERE status = 1;
		CREATE INDEX idx_alarms_device_time
			ON alarms(device_sn, created_at DESC);
		CREATE INDEX idx_alarms_pending
			ON alarms(status, created_at DESC) WHERE status = 0;
		CREATE INDEX idx_stations_user_deleted
			ON stations(user_id, deleted_at) WHERE deleted_at IS NULL;
		CREATE INDEX idx_device_alarms_sn_time
			ON device_alarms(device_sn, created_at DESC);
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)

	for index := range expectedDefinitions {
		assert.True(t, indexExists(index), "down must preserve preexisting index %s", index)
	}

	// Migration 036 can leave migration-002 index names attached to its
	// alarms_old backup table. Migration 044 must move those names aside,
	// build indexes on the live alarms table, and reverse only its own rename.
	_, err = tx.Exec(ctx, `
		DROP INDEX idx_alarms_device_time;
		DROP INDEX idx_alarms_pending;
		CREATE TEMP TABLE alarms_old (
			device_sn VARCHAR(50) NOT NULL,
			status SMALLINT NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE INDEX idx_alarms_device_time
			ON alarms_old(device_sn, created_at DESC);
		CREATE INDEX idx_alarms_pending
			ON alarms_old(status, created_at DESC) WHERE status = 0;
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)

	var ownerTable string
	for _, index := range []string{"idx_alarms_device_time", "idx_alarms_pending"} {
		require.NoError(t, tx.QueryRow(ctx, `
			SELECT tbl.relname
			FROM pg_index pi
			JOIN pg_class tbl ON tbl.oid=pi.indrelid
			WHERE pi.indexrelid=to_regclass($1)
		`, index).Scan(&ownerTable))
		assert.Equal(t, "alarms", ownerTable, "%s must index the live alarms table", index)
	}
	assert.True(t, indexExists("idx_alarms_old_device_time"))
	assert.True(t, indexExists("idx_alarms_old_pending"))

	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)
	assert.False(t, indexExists("idx_alarms_old_device_time"))
	assert.False(t, indexExists("idx_alarms_old_pending"))
	for _, index := range []string{"idx_alarms_device_time", "idx_alarms_pending"} {
		require.NoError(t, tx.QueryRow(ctx, `
			SELECT tbl.relname
			FROM pg_index pi
			JOIN pg_class tbl ON tbl.oid=pi.indrelid
			WHERE pi.indexrelid=to_regclass($1)
		`, index).Scan(&ownerTable))
		assert.Equal(t, "alarms_old", ownerTable, "down must restore legacy %s", index)
	}
}

// TestRBACDefaultSeedRepair verifies both baseline and upgrade paths against the
// original defaults from migrations 012 and 020. All work is isolated in a
// temporary table and rolled back.
func TestRBACDefaultSeedRepair(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	readSQL := func(name string) string {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		return string(data)
	}
	extractSeed := func(sql string) string {
		t.Helper()
		const startMarker = "INSERT INTO role_permissions (role, resource, action, is_allowed)"
		const endMarker = "ON CONFLICT (role, resource, action) DO NOTHING;"
		start := strings.Index(sql, startMarker)
		require.NotEqual(t, -1, start, "RBAC seed INSERT is missing")
		end := strings.Index(sql[start:], endMarker)
		require.NotEqual(t, -1, end, "RBAC seed must use ON CONFLICT DO NOTHING")
		return sql[start : start+end+len(endMarker)]
	}

	baselineSQL, err := os.ReadFile(filepath.Join(filepath.Dir(migrationsDir), "schema.sql"))
	require.NoError(t, err)
	baselineSeed := extractSeed(string(baselineSQL))
	repairSeed := extractSeed(readSQL("042_repair_default_role_permissions.up.sql"))

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE role_permissions (
			id BIGSERIAL PRIMARY KEY,
			role SMALLINT NOT NULL,
			resource VARCHAR(50) NOT NULL,
			action VARCHAR(20) NOT NULL,
			is_allowed BOOLEAN NOT NULL DEFAULT false,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE(role, resource, action)
		) ON COMMIT DROP
	`)
	require.NoError(t, err)

	// Build the canonical expected set directly from the historical migrations.
	_, err = tx.Exec(ctx, readSQL("012_create_role_permissions.up.sql"))
	require.NoError(t, err)
	_, err = tx.Exec(ctx, readSQL("020_backfill_rbac_new_resources.up.sql"))
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE expected_role_permissions ON COMMIT DROP AS
		SELECT role, resource, action, is_allowed FROM role_permissions
	`)
	require.NoError(t, err)

	var expectedCount int
	require.NoError(t, tx.QueryRow(ctx, `SELECT COUNT(*) FROM expected_role_permissions`).Scan(&expectedCount))
	assert.Equal(t, 110, expectedCount, "migrations 012 and 020 should define 110 defaults")

	// A fresh baseline_version=22 database must contain exactly the same defaults.
	_, err = tx.Exec(ctx, `TRUNCATE role_permissions`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, baselineSeed)
	require.NoError(t, err)

	var missing, unexpected int
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM (
			SELECT role, resource, action, is_allowed FROM expected_role_permissions
			EXCEPT
			SELECT role, resource, action, is_allowed FROM role_permissions
		) diff
	`).Scan(&missing))
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM (
			SELECT role, resource, action, is_allowed FROM role_permissions
			EXCEPT
			SELECT role, resource, action, is_allowed FROM expected_role_permissions
		) diff
	`).Scan(&unexpected))
	assert.Zero(t, missing, "baseline schema is missing historical RBAC defaults")
	assert.Zero(t, unexpected, "baseline schema contains unexpected RBAC defaults")

	// Upgrade repair restores missing rows without overwriting administrator choices.
	_, err = tx.Exec(ctx, `
		UPDATE role_permissions
		SET is_allowed=false, updated_at='2000-01-01 00:00:00+00'
		WHERE role=1 AND resource='stations' AND action='view';
		DELETE FROM role_permissions
		WHERE role=5 AND resource='dashboard' AND action='view'
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, repairSeed)
	require.NoError(t, err)

	var allowed bool
	var updatedAt time.Time
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT is_allowed, updated_at FROM role_permissions
		WHERE role=1 AND resource='stations' AND action='view'
	`).Scan(&allowed, &updatedAt))
	assert.False(t, allowed, "repair must preserve an administrator denial")
	assert.Equal(t, time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC), updatedAt.UTC(),
		"repair must not touch an existing permission timestamp")

	require.NoError(t, tx.QueryRow(ctx, `
		SELECT is_allowed FROM role_permissions
		WHERE role=5 AND resource='dashboard' AND action='view'
	`).Scan(&allowed))
	assert.True(t, allowed, "repair should restore a missing default permission")
}

// TestRBACCurrentBaselineTerminalModelRead keeps the 110-row historical seed
// contract separate while verifying the current product's additive baseline
// permission for terminal model/field lookups.
func TestRBACCurrentBaselineTerminalModelRead(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	baselineSQL, err := os.ReadFile(filepath.Join(filepath.Dir(migrationsDir), "schema.sql"))
	require.NoError(t, err)

	const startMarker = "-- 当前产品额外权限（不属于 migrations 012/020 的 110 条历史默认权限）"
	const insertMarker = "INSERT INTO role_permissions (role, resource, action, is_allowed)"
	const endMarker = "ON CONFLICT (role, resource, action) DO NOTHING;"
	start := strings.Index(string(baselineSQL), startMarker)
	require.NotEqual(t, -1, start, "current baseline RBAC marker is missing")
	currentBlock := string(baselineSQL)[start:]
	insertStart := strings.Index(currentBlock, insertMarker)
	require.NotEqual(t, -1, insertStart, "current baseline RBAC INSERT is missing")
	end := strings.Index(currentBlock[insertStart:], endMarker)
	require.NotEqual(t, -1, end, "current baseline RBAC seed must use ON CONFLICT DO NOTHING")
	currentSeed := currentBlock[insertStart : insertStart+end+len(endMarker)]

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE role_permissions (
			id BIGSERIAL PRIMARY KEY,
			role SMALLINT NOT NULL,
			resource VARCHAR(50) NOT NULL,
			action VARCHAR(20) NOT NULL,
			is_allowed BOOLEAN NOT NULL DEFAULT false,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE(role, resource, action)
		) ON COMMIT DROP
	`)
	require.NoError(t, err)

	// Populate the historical defaults first; their exact 110-row contract is
	// independently asserted by TestRBACDefaultSeedRepair above.
	for _, name := range []string{
		"012_create_role_permissions.up.sql",
		"020_backfill_rbac_new_resources.up.sql",
	} {
		data, readErr := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, readErr)
		_, err = tx.Exec(ctx, string(data))
		require.NoError(t, err)
	}
	_, err = tx.Exec(ctx, currentSeed)
	require.NoError(t, err)
	var count int
	require.NoError(t, tx.QueryRow(ctx, `SELECT COUNT(*) FROM role_permissions`).Scan(&count))
	assert.Equal(t, 111, count, "current baseline should add exactly one product permission to the 110 historical defaults")

	var allowed bool
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT is_allowed FROM role_permissions
		WHERE role=5 AND resource='models' AND action='view'
	`).Scan(&allowed))
	assert.True(t, allowed, "fresh current baseline should grant terminal model read access")

	_, err = tx.Exec(ctx, `
		UPDATE role_permissions
		SET is_allowed=false, updated_at='2000-01-01 00:00:00+00'
		WHERE role=5 AND resource='models' AND action='view'
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, currentSeed)
	require.NoError(t, err)

	var updatedAt time.Time
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT is_allowed, updated_at FROM role_permissions
		WHERE role=5 AND resource='models' AND action='view'
	`).Scan(&allowed, &updatedAt))
	assert.False(t, allowed, "baseline seed must preserve an administrator denial")
	assert.Equal(t, time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC), updatedAt.UTC(),
		"baseline seed must not touch an existing permission timestamp")
}

// TestTerminalModelReadPermissionMigration verifies migration 045's additive,
// idempotent behavior and its configuration-preserving rollback contract.
func TestTerminalModelReadPermissionMigration(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	readSQL := func(name string) string {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		return string(data)
	}
	upSQL := readSQL("045_grant_terminal_model_read.up.sql")
	downSQL := readSQL("045_grant_terminal_model_read.down.sql")

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, `
		CREATE TEMP TABLE role_permissions (
			id BIGSERIAL PRIMARY KEY,
			role SMALLINT NOT NULL,
			resource VARCHAR(50) NOT NULL,
			action VARCHAR(20) NOT NULL,
			is_allowed BOOLEAN NOT NULL DEFAULT false,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE(role, resource, action)
		) ON COMMIT DROP
	`)
	require.NoError(t, err)

	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err, "migration 045 up must be idempotent")

	var count int
	var allowed bool
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT COUNT(*), bool_and(is_allowed) FROM role_permissions
		WHERE role=5 AND resource='models' AND action='view'
	`).Scan(&count, &allowed))
	assert.Equal(t, 1, count)
	assert.True(t, allowed)

	_, err = tx.Exec(ctx, `
		UPDATE role_permissions
		SET is_allowed=false, updated_at='2000-01-01 00:00:00+00'
		WHERE role=5 AND resource='models' AND action='view'
	`)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)

	var updatedAt time.Time
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT is_allowed, updated_at FROM role_permissions
		WHERE role=5 AND resource='models' AND action='view'
	`).Scan(&allowed, &updatedAt))
	assert.False(t, allowed, "migration must preserve an administrator denial")
	assert.Equal(t, time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC), updatedAt.UTC(),
		"migration and down must preserve administrator configuration")
}

// TestTelemetryAdvisoryLockNamespaceMigration verifies migration 047 keeps
// same-stream ordering while separating telemetry and cell lock domains.
func TestTelemetryAdvisoryLockNamespaceMigration(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	readSQL := func(name string) string {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		return string(data)
	}
	upSQL := readSQL("047_namespace_telemetry_advisory_locks.up.sql")
	downSQL := readSQL("047_namespace_telemetry_advisory_locks.down.sql")

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err, "migration 047 up must be idempotent")

	var telemetryDef, cellsDef string
	require.NoError(t, tx.QueryRow(ctx,
		`SELECT pg_get_functiondef('maintain_telemetry_v2_derived()'::regprocedure)`).Scan(&telemetryDef))
	require.NoError(t, tx.QueryRow(ctx,
		`SELECT pg_get_functiondef('maintain_latest_cells()'::regprocedure)`).Scan(&cellsDef))
	assert.Contains(t, telemetryDef, "telemetry:v1:")
	assert.Contains(t, cellsDef, "cells:v1:")
	assert.Contains(t, telemetryDef, "quality_flags & 8")
	assert.Contains(t, cellsDef, "quality_flags & 8")
	assert.NotContains(t, telemetryDef, "quality_flags & 64")
	assert.NotContains(t, cellsDef, "quality_flags & 64")
	assert.NotContains(t, telemetryDef, "cells:v1:")
	assert.NotContains(t, cellsDef, "telemetry:v1:")

	var distinct bool
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT hashtextextended('telemetry:v1:TEST-SN',0)
		    <> hashtextextended('cells:v1:TEST-SN',0)
	`).Scan(&distinct))
	assert.True(t, distinct)

	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)
	require.NoError(t, tx.QueryRow(ctx,
		`SELECT pg_get_functiondef('maintain_telemetry_v2_derived()'::regprocedure)`).Scan(&telemetryDef))
	assert.NotContains(t, telemetryDef, "telemetry:v1:")
}

// TestLegacyTelemetryRetirementMigration verifies migration 046 removes both
// pre-V1 stores without CASCADE and that its schema-only rollback is idempotent.
func TestLegacyTelemetryRetirementMigration(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	readSQL := func(name string) string {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		return string(data)
	}

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	upSQL := readSQL("046_drop_legacy_telemetry_tables.up.sql")
	downSQL := readSQL("046_drop_legacy_telemetry_tables.down.sql")
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, upSQL)
	require.NoError(t, err, "migration 046 up must be idempotent")

	var legacyTelemetry, legacyDayData, legacyStationDayData *string
	require.NoError(t, tx.QueryRow(ctx, `SELECT to_regclass('public.device_telemetry')::text,
		to_regclass('public.device_day_data')::text,to_regclass('public.station_day_data')::text`).
		Scan(&legacyTelemetry, &legacyDayData, &legacyStationDayData))
	assert.Nil(t, legacyTelemetry)
	assert.Nil(t, legacyDayData)
	assert.Nil(t, legacyStationDayData)

	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, downSQL)
	require.NoError(t, err, "migration 046 down must be idempotent")
	require.NoError(t, tx.QueryRow(ctx, `SELECT to_regclass('public.device_telemetry')::text,
		to_regclass('public.device_day_data')::text,to_regclass('public.station_day_data')::text`).
		Scan(&legacyTelemetry, &legacyDayData, &legacyStationDayData))
	assert.NotNil(t, legacyTelemetry)
	assert.NotNil(t, legacyDayData)
	assert.NotNil(t, legacyStationDayData)
}

// TestCriticalTablesExist verifies that key tables are present after migrations.
func TestCriticalTablesExist(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	expectedTables := []string{
		"users",
		"devices",
		"stations",
		"alarms",
		"device_models",
		"device_model_fields",
		"device_protocol_versions",
		"device_alarms",
		"device_cmd_logs",
		"firmware_versions",
		"device_upgrades",
		"device_telemetry_3min",
		"device_latest_state",
		"user_device_rel",
		"system_configs",
		"notifications",
		"alarm_notifications",
		"user_operation_logs",
		"verification_codes",
		"regions",
		"device_alarm_events",
		"device_alarm_snapshots",
		"device_parallel_state",
		"device_parallel_events",
		"device_three_phase_3min",
	}

	ctx := context.Background()
	rows, err := pool.Query(ctx, `
		SELECT table_name
		FROM information_schema.tables
		WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
	`)
	require.NoError(t, err)
	defer rows.Close()

	existing := make(map[string]bool)
	for rows.Next() {
		var name string
		require.NoError(t, rows.Scan(&name))
		existing[name] = true
	}

	for _, table := range expectedTables {
		t.Run(table, func(t *testing.T) {
			assert.True(t, existing[table], "table %q should exist", table)
		})
	}
}

// TestCriticalIndexesExist verifies that key indexes were created.
func TestCriticalIndexesExist(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	expectedIndexes := []string{
		"idx_users_phone",
		"idx_users_role",
		"idx_devices_sn",
		"idx_devices_user",
		"idx_devices_status",
		"idx_devices_user_station_deleted",
		"idx_devices_status_online",
		"idx_stations_user",
		"idx_stations_user_deleted",
		"idx_alarms_device",
		"idx_alarms_time",
		"idx_alarms_device_time",
		"idx_alarms_pending",
		"idx_device_alarms_sn",
		"idx_device_alarms_sn_time",
		"idx_cmd_logs_sn",
		"idx_alarm_events_device_time",
		"idx_alarm_snapshots_device_time",
		"uq_device_alarm_events_lifecycle",
		"uq_alarm_snapshot_event_type",
		"idx_parallel_state_updated",
		"idx_parallel_events_station_time",
		"uq_device_parallel_events_message",
		"idx_three_phase_device_time",
		"uq_three_phase_message",
		"idx_alarms_old_device",
	}

	ctx := context.Background()
	rows, err := pool.Query(ctx, `
		SELECT indexname
		FROM pg_indexes
		WHERE schemaname = 'public'
	`)
	require.NoError(t, err)
	defer rows.Close()

	existing := make(map[string]bool)
	for rows.Next() {
		var name string
		require.NoError(t, rows.Scan(&name))
		existing[name] = true
	}

	for _, idx := range expectedIndexes {
		t.Run(idx, func(t *testing.T) {
			assert.True(t, existing[idx], "index %q should exist", idx)
		})
	}
}

// TestTimescaleDBHypertable verifies the canonical 3-minute hypertable.
func TestTimescaleDBHypertable(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	// Check that timescaledb extension is enabled
	var extName string
	err := pool.QueryRow(ctx, `SELECT extname FROM pg_extension WHERE extname = 'timescaledb'`).Scan(&extName)
	require.NoError(t, err, "TimescaleDB extension should be installed")
	assert.Equal(t, "timescaledb", extName)

	// Check that device_telemetry_3min is a hypertable.
	var hypertableCount int
	err = pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM _timescaledb_catalog.hypertable
		WHERE table_name = 'device_telemetry_3min'
	`).Scan(&hypertableCount)
	require.NoError(t, err)
	assert.Equal(t, 1, hypertableCount, "device_telemetry_3min should be a hypertable")

	// Check compression policy exists
	var compressionPolicyCount int
	err = pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM timescaledb_information.jobs
		WHERE proc_name = 'policy_compression'
		  AND hypertable_name = 'device_telemetry_3min'
	`).Scan(&compressionPolicyCount)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, compressionPolicyCount, 1, "compression policy should exist for device_telemetry_3min")
}

// TestTimescaleDBContinuousAggregates verifies continuous aggregates are created.
func TestTimescaleDBContinuousAggregates(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	aggregates := []string{"device_telemetry_hour"}

	for _, agg := range aggregates {
		t.Run(agg, func(t *testing.T) {
			var count int
			err := pool.QueryRow(ctx, `
				SELECT COUNT(*) FROM timescaledb_information.continuous_aggregates
				WHERE view_name = $1
			`, agg).Scan(&count)
			require.NoError(t, err)
			assert.Equal(t, 1, count, "continuous aggregate %q should exist", agg)
		})
	}
}

// TestTelemetryInsertAndQuery verifies we can insert and query telemetry data.
func TestTelemetryInsertAndQuery(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()
	testSN := fmt.Sprintf("INTEGRATION-TEST-%d", time.Now().UnixNano())

	// Insert test telemetry data
	for i := 0; i < 10; i++ {
		_, err := pool.Exec(ctx, `
			INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,received_at,
				topic,data_hash,raw_envelope,ac_active_power,daily_pv_energy,work_state,inverter_temperature)
			VALUES($1::varchar,1,$2::bigint,$3::timestamptz,NOW(),'heartbeat',encode(digest($1::text || ':' || $2::text,'sha256'),'hex'),
				jsonb_build_object('t',(extract(epoch FROM $3::timestamptz)*1000)::bigint,'v',1,'data',jsonb_build_object()),$4,$5,1,$6)
		`, testSN, i+1, time.Now().Add(-time.Duration(10-i)*time.Minute),
			2250.0+float64(i)*10, float64(i)*0.5, 35.5+float64(i)*0.1)
		require.NoError(t, err)
	}

	// Query back
	var count int
	err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM device_telemetry_3min WHERE device_sn = $1`, testSN).Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 10, count)

	// Query latest view
	var latestSN string
	var latestPower float64
	err = pool.QueryRow(ctx, `
		SELECT device_sn, total_active_power FROM v_device_latest WHERE device_sn = $1
	`, testSN).Scan(&latestSN, &latestPower)
	require.NoError(t, err)
	assert.Equal(t, testSN, latestSN)
	assert.Greater(t, latestPower, 0.0)

	// Cleanup
	_, _ = pool.Exec(ctx, `DELETE FROM device_telemetry_3min WHERE device_sn = $1`, testSN)
}

// TestProtocol039SchemaContract verifies the final relational/Timescale split
// introduced by migration 039. Alarm events must remain an ordinary table,
// while three-phase samples must be a hypertable.
func TestProtocol039SchemaContract(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	var alarmEventsHypertable, threePhaseHypertable bool
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM timescaledb_information.hypertables
			WHERE hypertable_schema='public' AND hypertable_name='device_alarm_events'
		), EXISTS (
			SELECT 1 FROM timescaledb_information.hypertables
			WHERE hypertable_schema='public' AND hypertable_name='device_three_phase_3min'
		)
	`).Scan(&alarmEventsHypertable, &threePhaseHypertable))
	assert.False(t, alarmEventsHypertable, "device_alarm_events must be an ordinary PostgreSQL table")
	assert.True(t, threePhaseHypertable, "device_three_phase_3min must be a TimescaleDB hypertable")

	expectedColumns := map[string][]string{
		"alarms": {
			"type", "level", "message", "updated_at",
		},
		"device_alarm_events": {
			"id", "device_sn", "source", "code", "level", "state", "topic",
			"event_time", "t", "raw_envelope", "data_hash", "received_at", "created_at",
		},
		"device_parallel_state": {
			"station_id", "master_sn", "enabled", "machines", "event_time", "t",
			"raw_envelope", "data_hash", "reported_at", "updated_at",
		},
		"device_parallel_events": {
			"station_id", "event_type", "old_state", "new_state", "event_time", "t",
			"raw_envelope", "data_hash", "occurred_at",
		},
		"device_three_phase_3min": {
			"device_sn", "topic", "event_time", "t", "data_hash", "raw_envelope",
		},
	}

	for table, columns := range expectedColumns {
		for _, column := range columns {
			t.Run(table+"."+column, func(t *testing.T) {
				var exists bool
				require.NoError(t, pool.QueryRow(ctx, `
					SELECT EXISTS (
						SELECT 1 FROM information_schema.columns
						WHERE table_schema='public' AND table_name=$1 AND column_name=$2
					)
				`, table, column).Scan(&exists))
				assert.True(t, exists, "%s.%s should exist", table, column)
			})
		}
	}

	var snapshotDeleteRule string
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT rc.delete_rule
		FROM information_schema.referential_constraints rc
		JOIN information_schema.table_constraints tc
		  ON tc.constraint_schema=rc.constraint_schema
		 AND tc.constraint_name=rc.constraint_name
		WHERE tc.table_schema='public'
		  AND tc.table_name='device_alarm_snapshots'
		LIMIT 1
	`).Scan(&snapshotDeleteRule))
	assert.Equal(t, "CASCADE", snapshotDeleteRule)

	for _, policy := range []string{"policy_compression", "policy_retention"} {
		var count int
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT COUNT(*) FROM timescaledb_information.jobs
			WHERE hypertable_schema='public'
			  AND hypertable_name='device_three_phase_3min'
			  AND proc_name=$1
		`, policy).Scan(&count))
		assert.Equal(t, 1, count, "%s should exist exactly once", policy)
	}

	for _, indexName := range []string{
		"idx_alarms_device", "idx_alarms_station", "idx_alarms_user",
		"idx_alarms_status", "idx_alarms_time", "idx_alarms_v1_active",
	} {
		var owner string
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT tablename FROM pg_indexes
			WHERE schemaname='public' AND indexname=$1
		`, indexName).Scan(&owner))
		assert.Equal(t, "alarms", owner, "%s must belong to the live alarms hypertable", indexName)
	}

	var activeAlarmIndex string
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT indexdef FROM pg_indexes
		WHERE schemaname='public' AND indexname='idx_alarms_v1_active'
	`).Scan(&activeAlarmIndex))
	assert.Contains(t, activeAlarmIndex, "event_state")
	assert.NotContains(t, activeAlarmIndex, "status = 0")
}

// TestProtocol039LegacyWrites exercises the SQL shapes used by the current API
// handlers. The transaction is always rolled back, so no fixture data remains.
func TestProtocol039LegacyWrites(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer func() { _ = tx.Rollback(ctx) }()

	suffix := time.Now().UnixNano()
	phone := fmt.Sprintf("139%08d", suffix%100000000)
	sn := fmt.Sprintf("PROTO-039-%d", suffix)

	var userID, stationID int64
	require.NoError(t, tx.QueryRow(ctx, `
		INSERT INTO users(phone,password_hash,nickname,role,status)
		VALUES($1,'integration-hash','protocol-039',5,1)
		RETURNING id
	`, phone).Scan(&userID))
	require.NoError(t, tx.QueryRow(ctx, `
		INSERT INTO stations(user_id,name,province,city,address,capacity,status)
		VALUES($1,'protocol-039','test','test','test',6.2,1)
		RETURNING id
	`, userID).Scan(&stationID))
	_, err = tx.Exec(ctx, `
		INSERT INTO devices(sn,station_id,user_id,status) VALUES($1,$2,$3,1)
	`, sn, stationID, userID)
	require.NoError(t, err)

	_, err = tx.Exec(ctx, `
		INSERT INTO alarms(
			device_sn,type,level,alarm_level,alarm_source,event_state,station_id,user_id,
			fault_code,fault_message,fault_detail,message,status,occurred_at,created_at
		) VALUES($1,'device_fault',2,2,0,'active',$2,$3,'8','PV input abnormal','{}','PV input abnormal',0,NOW(),NOW())
	`, sn, stationID, userID)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `UPDATE alarms SET status=1 WHERE device_sn=$1`, sn)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `
		UPDATE alarms SET event_state='recovered',recovered_at=NOW() WHERE device_sn=$1
	`, sn)
	require.NoError(t, err)
	var handlingStatus int
	var lifecycleState string
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT status,event_state FROM alarms WHERE device_sn=$1
	`, sn).Scan(&handlingStatus, &lifecycleState))
	assert.Equal(t, 1, handlingStatus, "recovery must not overwrite the manual handling status")
	assert.Equal(t, "recovered", lifecycleState)

	eventTime := time.Now().UTC().Truncate(time.Microsecond)
	var eventID int64
	var canonicalTime time.Time
	var eventHash string
	require.NoError(t, tx.QueryRow(ctx, `
		INSERT INTO device_alarm_events(
			device_sn,station_id,source,code,level,state,active_at,recovered_at,raw_data
		) VALUES($1,$2,0,'8',2,'active',$3,NULL,'{"code":8}'::jsonb)
		RETURNING id,event_time,data_hash
	`, sn, stationID, eventTime).Scan(&eventID, &canonicalTime, &eventHash))
	assert.True(t, eventTime.Equal(canonicalTime), "canonical event_time should preserve the same instant")
	assert.Len(t, eventHash, 64, "derived data_hash should be a SHA-256 hex string")

	_, err = tx.Exec(ctx, `
		INSERT INTO device_alarm_snapshots(
			device_sn,alarm_event_id,snapshot_type,raw_snapshot
		) VALUES($1,$2,'before','{}'::jsonb)
	`, sn, eventID)
	require.NoError(t, err)

	_, err = tx.Exec(ctx, `
		INSERT INTO device_parallel_state(
			station_id,master_sn,mode,count,total_rated_power,total_active_power,
			sync_state,machines,reported_at,updated_at
		) VALUES($1,$2,'three_phase',3,18600,15200,'synced','[]'::jsonb,$3,NOW())
		ON CONFLICT(station_id) DO UPDATE SET
			master_sn=EXCLUDED.master_sn,machines=EXCLUDED.machines,
			reported_at=EXCLUDED.reported_at,updated_at=NOW()
	`, stationID, sn, eventTime)
	require.NoError(t, err)

	_, err = tx.Exec(ctx, `
		INSERT INTO device_parallel_events(
			station_id,master_sn,event_type,old_state,new_state,occurred_at
		) VALUES($1,$2,'parallel_created','null'::jsonb,'[]'::jsonb,$3)
	`, stationID, sn, eventTime)
	require.NoError(t, err)

	threePhaseSQL := `
		INSERT INTO device_three_phase_3min(
			device_sn,event_time,voltage_l1,voltage_l2,voltage_l3,
			current_l1,current_l2,current_l3,active_power_l1,active_power_l2,active_power_l3,
			total_active_power,line_voltage_l1l2,line_voltage_l2l3,line_voltage_l3l1,
			frequency,voltage_unbalance,current_unbalance,raw_envelope
		) VALUES($1,$2,220.5,220.3,220.1,23.2,22.9,23.1,5100,5050,5050,
			15200,381.5,381.4,381.3,50.0,0.8,1.2,NULL::jsonb)
		ON CONFLICT(device_sn,event_time,data_hash) DO NOTHING
	`
	_, err = tx.Exec(ctx, threePhaseSQL, sn, eventTime)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, threePhaseSQL, sn, eventTime)
	require.NoError(t, err)

	var threePhaseCount int
	require.NoError(t, tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM device_three_phase_3min
		WHERE device_sn=$1 AND event_time=$2
	`, sn, eventTime).Scan(&threePhaseCount))
	assert.Equal(t, 1, threePhaseCount, "duplicate three-phase messages should be idempotent")

	require.NoError(t, tx.Rollback(ctx))
}

// TestTriggersAndFunctions verifies update_updated_at_column trigger function works.
func TestTriggersAndFunctions(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	// Insert a test user
	testPhone := fmt.Sprintf("138%08d", time.Now().UnixNano()%100000000)
	_, err := pool.Exec(ctx, `
		INSERT INTO users (phone, password_hash, nickname, role, status)
		VALUES ($1, '$2a$10$dummyhash', 'trigger-test', 5, 1)
	`, testPhone)
	require.NoError(t, err)

	// Get initial updated_at
	var initialUpdatedAt time.Time
	err = pool.QueryRow(ctx, `SELECT updated_at FROM users WHERE phone = $1`, testPhone).Scan(&initialUpdatedAt)
	require.NoError(t, err)

	// Wait and update
	time.Sleep(1100 * time.Millisecond)
	_, err = pool.Exec(ctx, `UPDATE users SET nickname = 'trigger-updated' WHERE phone = $1`, testPhone)
	require.NoError(t, err)

	// Check updated_at changed
	var newUpdatedAt time.Time
	err = pool.QueryRow(ctx, `SELECT updated_at FROM users WHERE phone = $1`, testPhone).Scan(&newUpdatedAt)
	require.NoError(t, err)
	assert.True(t, newUpdatedAt.After(initialUpdatedAt), "updated_at should be auto-updated by trigger")

	// Cleanup
	_, _ = pool.Exec(ctx, `DELETE FROM users WHERE phone = $1`, testPhone)
}

// ---------- helpers ----------

func withDisposableChannelMigrationDatabase(
	t *testing.T,
	run func(context.Context, *pgxpool.Pool, string),
) {
	t.Helper()
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")

	adminCfg := cfg
	adminCfg.DBName = "postgres"
	adminPool := ConnectDB(t, adminCfg)
	defer adminPool.Close()

	ctx := context.Background()
	dbName := fmt.Sprintf("inv_channel_migration_test_%d", time.Now().UnixNano())
	_, err := adminPool.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err, "create disposable channel migration database")

	migrationCfg := cfg
	migrationCfg.DBName = dbName
	pool := ConnectDB(t, migrationCfg)
	defer func() {
		pool.Close()
		_, _ = adminPool.Exec(ctx, `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1`, dbName)
		_, dropErr := adminPool.Exec(ctx, "DROP DATABASE IF EXISTS "+dbName)
		assert.NoError(t, dropErr, "drop disposable channel migration database")
	}()

	migrationsDir := findMigrationsDir(t)
	baselineSQL, err := os.ReadFile(filepath.Join(filepath.Dir(migrationsDir), "schema.sql"))
	require.NoError(t, err, "read baseline schema")
	const channelSchemaMarker = "-- 15. Channel authorization model"
	legacySchema := string(baselineSQL)
	require.NotContains(t, legacySchema, channelSchemaMarker,
		"immutable v22 baseline must not embed the channel authorization model")
	_, err = pool.Exec(ctx, legacySchema)
	require.NoError(t, err, "execute baseline schema")

	for _, table := range []string{"organizations", "tenant_roots", "authorization_resources", "idempotency_responses", "transactional_outbox"} {
		var exists bool
		require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, table).Scan(&exists))
		require.False(t, exists, "legacy schema must not already contain %s", table)
	}
	var legacyResourceIDType string
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT data_type FROM information_schema.columns
		WHERE table_schema='public' AND table_name='audit_logs' AND column_name='resource_id'
	`).Scan(&legacyResourceIDType))
	require.Equal(t, "bigint", legacyResourceIDType, "migration fixture must start from the legacy audit contract")

	run(ctx, pool, migrationsDir)
}

func readMigrationFile(t *testing.T, migrationsDir, name string) string {
	t.Helper()
	contents, err := os.ReadFile(filepath.Join(migrationsDir, name))
	require.NoError(t, err, "read migration %s", name)
	return string(contents)
}

type migrationFile struct {
	Name   string
	Number int
}

func findMigrationsDir(t *testing.T) string {
	t.Helper()
	// Try common paths
	candidates := []string{
		"../../database/migrations",
		"../../../database/migrations",
		filepath.Join(os.Getenv("PROJECT_ROOT"), "database/migrations"),
	}
	for _, p := range candidates {
		abs, _ := filepath.Abs(p)
		if info, err := os.Stat(abs); err == nil && info.IsDir() {
			return abs
		}
	}
	t.Skip("migrations directory not found; set PROJECT_ROOT env var")
	return ""
}

func collectUpMigrations(t *testing.T, dir string) []migrationFile {
	t.Helper()
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)

	var files []migrationFile
	for _, e := range entries {
		name := e.Name()
		if strings.HasSuffix(name, ".up.sql") || (strings.HasSuffix(name, ".sql") && !strings.Contains(name, ".down.")) {
			num := 0
			fmt.Sscanf(name, "%d", &num)
			files = append(files, migrationFile{Name: name, Number: num})
		}
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].Number < files[j].Number
	})
	return files
}
