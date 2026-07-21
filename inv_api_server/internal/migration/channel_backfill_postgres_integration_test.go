//go:build integration

package migration

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPostgresOrganizationBackfillIsDurableAndIdempotent(t *testing.T) {
	ctx := context.Background()
	host := envOr("TEST_DB_HOST", "localhost")
	port := envOr("TEST_DB_PORT", "15432")
	user := envOr("TEST_DB_USER", "testuser")
	password := envOr("TEST_DB_PASSWORD", "testpass")
	admin, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable", user, password, host, port))
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))
	defer admin.Close()

	dbName := fmt.Sprintf("channel_backfill_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err)
	pool, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, password, host, port, dbName))
	require.NoError(t, err)
	defer func() {
		pool.Close()
		_, _ = admin.Exec(ctx, `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1`, dbName)
		_, dropErr := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+dbName)
		assert.NoError(t, dropErr)
	}()

	repoRoot := filepath.Clean(filepath.Join("..", "..", ".."))
	for _, path := range []string{
		filepath.Join(repoRoot, "database", "schema.sql"),
		filepath.Join(repoRoot, "database", "migrations", "064_create_channel_authorization.up.sql"),
		filepath.Join(repoRoot, "database", "migrations", "065_extend_audit_outbox.up.sql"),
		filepath.Join(repoRoot, "database", "migrations", "066_create_channel_backfill_control.up.sql"),
	} {
		contents, readErr := os.ReadFile(path)
		require.NoError(t, readErr)
		_, execErr := pool.Exec(ctx, string(contents))
		require.NoError(t, execErr, "execute %s", filepath.Base(path))
	}
	_, err = pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,role,parent_id,status) VALUES
			(9100,'channel-9100','hash',1,NULL,1),
			(9101,'channel-9101','hash',2,9100,1),
			(9102,'channel-9102','hash',3,9101,1),
			(9103,'channel-9103','hash',5,9102,1)
	`)
	require.NoError(t, err)

	mapping := ChannelMappingConfig{SchemaVersion: "1", Roles: validIntegrationMappings()}
	digest, err := mapping.Digest()
	require.NoError(t, err)
	users, ownership, err := LoadLegacyChannelSnapshot(ctx, pool)
	require.NoError(t, err)
	report := AnalyzeLegacyUsers(users, mapping.Roles, ownership)
	require.Empty(t, report.Quarantine)
	require.Len(t, report.Operations, 4)

	store := NewPostgresOrganizationBackfillStore(pool, uuid.New(), "integration-test")
	runID, err := store.Prepare(ctx, digest, report, 9103)
	require.NoError(t, err)
	result, err := ExecuteOrganizationBackfill(ctx, store, digest, report.Operations, 2)
	require.NoError(t, err)
	assert.Equal(t, 4, result.Applied)
	require.NoError(t, store.Complete(ctx, result))

	second, err := ExecuteOrganizationBackfill(ctx, store, digest, report.Operations, 2)
	require.NoError(t, err)
	assert.Zero(t, second.Applied)
	var organizations, memberships, assignments, closureDepth int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM organizations WHERE id BETWEEN 9100 AND 9103`).Scan(&organizations))
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM organization_memberships WHERE user_id BETWEEN 9100 AND 9103`).Scan(&memberships))
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM membership_role_assignments WHERE membership_id BETWEEN 9100 AND 9103`).Scan(&assignments))
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM organization_closure WHERE descendant_id=9103`).Scan(&closureDepth))
	assert.Equal(t, 4, organizations)
	assert.Equal(t, 4, memberships)
	assert.Equal(t, 4, assignments)
	assert.Equal(t, 4, closureDepth)

	shadow, err := LoadChannelShadowReport(ctx, pool, runID)
	require.NoError(t, err)
	if shadow.ShadowDiffs > 0 {
		rows, queryErr := pool.Query(ctx, `SELECT source_key,expected,actual FROM channel_migration_shadow_diffs WHERE run_id=$1 ORDER BY source_key`, runID)
		require.NoError(t, queryErr)
		for rows.Next() {
			var key, expected, actual string
			require.NoError(t, rows.Scan(&key, &expected, &actual))
			t.Logf("shadow diff %s expected=%s actual=%s", key, expected, actual)
		}
		rows.Close()
	}
	assert.Equal(t, int64(4), shadow.PlannedOrganizations)
	assert.Equal(t, int64(4), shadow.SucceededOrganizations)
	assert.Zero(t, shadow.PendingItems)
	assert.Zero(t, shadow.UnresolvedQuarantine)
	assert.Zero(t, shadow.ShadowDiffs)
	var auditCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM audit_logs WHERE resource_type='channel_migration_run' AND resource_id=$1`, runID.String()).Scan(&auditCount))
	assert.Equal(t, 3, auditCount, "two committed batches and completion must each have immutable audit evidence")
	require.NoError(t, store.Complete(ctx, result), "completion must be idempotent for CLI retries")
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM audit_logs WHERE resource_type='channel_migration_run' AND resource_id=$1`, runID.String()).Scan(&auditCount))
	assert.Equal(t, 3, auditCount, "idempotent completion must not duplicate immutable audit evidence")

	_, err = pool.Exec(ctx, `UPDATE organization_memberships SET status='disabled' WHERE id=9103`)
	require.NoError(t, err)
	tampered, err := LoadChannelShadowReport(ctx, pool, runID)
	require.NoError(t, err)
	assert.Greater(t, tampered.ShadowDiffs, int64(0), "shadow reconciliation must detect target tampering")
	_, err = pool.Exec(ctx, `UPDATE organization_memberships SET status='active' WHERE id=9103`)
	require.NoError(t, err)
	reconciled, err := LoadChannelShadowReport(ctx, pool, runID)
	require.NoError(t, err)
	assert.Zero(t, reconciled.ShadowDiffs)

	staleStore := NewPostgresOrganizationBackfillStore(pool, uuid.New(), "stale-source-test")
	staleDigest := strings.Repeat("b", 64)
	staleRunID, err := staleStore.Prepare(ctx, staleDigest, report, 9103)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `UPDATE users SET status=0 WHERE id=9103`)
	require.NoError(t, err)
	_, err = ExecuteOrganizationBackfill(ctx, staleStore, staleDigest, report.Operations, 4)
	require.ErrorContains(t, err, "changed after preflight")
	require.NoError(t, staleStore.Fail(ctx, err))
	var staleCheckpoint int
	require.NoError(t, pool.QueryRow(ctx, `SELECT next_ordinal FROM channel_migration_checkpoints WHERE run_id=$1`, staleRunID).Scan(&staleCheckpoint))
	assert.Zero(t, staleCheckpoint, "source fingerprint mismatch must not advance checkpoint")
	_, err = pool.Exec(ctx, `UPDATE users SET status=1 WHERE id=9103`)
	require.NoError(t, err)
	resumedStore := NewPostgresOrganizationBackfillStore(pool, uuid.New(), "stale-source-resume-test")
	resumedRunID, err := resumedStore.Prepare(ctx, staleDigest, report, 9103)
	require.NoError(t, err)
	assert.Equal(t, staleRunID, resumedRunID)
	resumedResult, err := ExecuteOrganizationBackfill(ctx, resumedStore, staleDigest, report.Operations, 4)
	require.NoError(t, err, "a failed run must resume from its durable checkpoint after source correction")
	require.NoError(t, resumedStore.Complete(ctx, resumedResult))

	_, err = pool.Exec(ctx, `INSERT INTO users(id,phone,password_hash,role,status) VALUES(9200,'channel-9200','hash',1,1)`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status) VALUES(9200,9100,9100,9100,'disabled')`)
	require.NoError(t, err)
	conflictUsers, conflictOwnership, err := LoadLegacyChannelSnapshot(ctx, pool)
	require.NoError(t, err)
	conflictReport := AnalyzeLegacyUsers(conflictUsers, mapping.Roles, conflictOwnership)
	conflictStore := NewPostgresOrganizationBackfillStore(pool, uuid.New(), "membership-conflict-test")
	conflictDigest := strings.Repeat("c", 64)
	conflictRunID, err := conflictStore.Prepare(ctx, conflictDigest, conflictReport, 9200)
	require.NoError(t, err)
	_, err = ExecuteOrganizationBackfill(ctx, conflictStore, conflictDigest, conflictReport.Operations, len(conflictReport.Operations))
	require.ErrorContains(t, err, "membership id 9200 belongs to a different")
	var rolledBackOrganization bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM organizations WHERE id=9200)`).Scan(&rolledBackOrganization))
	assert.False(t, rolledBackOrganization, "membership conflict must roll back the whole target batch")
	require.NoError(t, pool.QueryRow(ctx, `SELECT next_ordinal FROM channel_migration_checkpoints WHERE run_id=$1`, conflictRunID).Scan(&staleCheckpoint))
	assert.Zero(t, staleCheckpoint)

	quarantineReport := PreflightReport{Quarantine: []QuarantineEntry{{SourceTable: "users", SourceKey: "9300", ReasonCode: ReasonOrphanParent}}}
	quarantineStore := NewPostgresOrganizationBackfillStore(pool, uuid.New(), "quarantine-idempotency-test")
	quarantineDigest := strings.Repeat("d", 64)
	quarantineRunID, err := quarantineStore.Prepare(ctx, quarantineDigest, quarantineReport, 9200)
	require.NoError(t, err)
	_, err = quarantineStore.Prepare(ctx, quarantineDigest, quarantineReport, 9200)
	require.NoError(t, err)
	var occurrences int
	require.NoError(t, pool.QueryRow(ctx, `SELECT occurrence_count FROM channel_migration_quarantine WHERE source_table='users' AND source_key='9300' AND reason_code=$1 AND last_seen_run_id=$2`, ReasonOrphanParent, quarantineRunID).Scan(&occurrences))
	assert.Equal(t, 1, occurrences, "repeating Prepare for the same run must be idempotent")
	_, err = pool.Exec(ctx, `DELETE FROM organization_memberships WHERE id=9200`)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM users WHERE id=9200`)
	require.NoError(t, err)

	crossBatchUsers, crossBatchOwnership, err := LoadLegacyChannelSnapshot(ctx, pool)
	require.NoError(t, err)
	crossBatchReport := AnalyzeLegacyUsers(crossBatchUsers, mapping.Roles, crossBatchOwnership)
	crossBatchStore := NewPostgresOrganizationBackfillStore(pool, uuid.New(), "cross-batch-source-test")
	crossBatchDigest := strings.Repeat("e", 64)
	_, err = crossBatchStore.Prepare(ctx, crossBatchDigest, crossBatchReport, 9103)
	require.NoError(t, err)
	_, err = crossBatchStore.ApplyBatch(ctx, organizationBackfillJob, crossBatchDigest, 0, crossBatchReport.Operations[:1])
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `UPDATE users SET status=0 WHERE id=$1`, crossBatchReport.Operations[0].SourceUserID)
	require.NoError(t, err)
	_, err = crossBatchStore.ApplyBatch(ctx, organizationBackfillJob, crossBatchDigest, 1, crossBatchReport.Operations[1:])
	require.NoError(t, err)
	err = crossBatchStore.Complete(ctx, BackfillResult{Applied: len(crossBatchReport.Operations), Checkpoint: len(crossBatchReport.Operations)})
	require.ErrorContains(t, err, "changed before completion")
}

func validIntegrationMappings() []LegacyRoleMapping {
	return []LegacyRoleMapping{
		{LegacyRole: 1, OrganizationType: "manufacturer", RoleCodes: []string{"org_admin"}},
		{LegacyRole: 2, OrganizationType: "agent", RoleCodes: []string{"channel_manager"}},
		{LegacyRole: 3, OrganizationType: "distributor", RoleCodes: []string{"channel_manager"}},
		{LegacyRole: 5, OrganizationType: "customer", RoleCodes: []string{"viewer"}},
	}
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
