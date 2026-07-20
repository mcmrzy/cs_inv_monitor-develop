//go:build integration

package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
)

func TestAuthorizationPostgresDescendantAllowSiblingAndCrossTenantDeny(t *testing.T) {
	ctx := context.Background()
	host, port := authEnv("TEST_DB_HOST", "localhost"), authEnv("TEST_DB_PORT", "15432")
	user, password := authEnv("TEST_DB_USER", "testuser"), authEnv("TEST_DB_PASSWORD", "testpass")
	admin, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable", user, password, host, port))
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))
	defer admin.Close()

	dbName := fmt.Sprintf("authorization_%d", time.Now().UnixNano())
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
		filepath.Join(repoRoot, "database", "migrations", "059_create_channel_authorization.up.sql"),
		filepath.Join(repoRoot, "database", "migrations", "060_extend_audit_outbox.up.sql"),
	} {
		contents, readErr := os.ReadFile(path)
		require.NoError(t, readErr)
		_, execErr := pool.Exec(ctx, string(contents))
		require.NoError(t, execErr, filepath.Base(path))
	}
	_, err = pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,role,status) VALUES
			(700,'authz-actor','hash',1,1),(701,'authz-member-102','hash',5,1),(702,'authz-member-103','hash',5,1);
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status) VALUES
			(100,100,NULL,'manufacturer','M-A','Manufacturer A','active'),
			(101,100,100,'agent','A-1','Agent 1','active'),
			(102,100,101,'distributor','D-1','Distributor 1','active'),
			(103,100,102,'customer','C-1','Customer 1','active'),
			(104,100,100,'agent','A-SIBLING','Sibling Agent','active'),
			(200,200,NULL,'manufacturer','M-B','Manufacturer B','active'),
			(201,200,200,'agent','B-1','Agent B','active');
		INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status,version)
		VALUES(1001,100,101,700,'active',1),(1002,100,102,701,'active',1),(1003,100,103,702,'active',1);
		INSERT INTO membership_role_assignments(id,root_tenant_id,organization_id,membership_id,role_code,status)
		VALUES(1101,100,101,1001,'channel_manager','active');
		INSERT INTO role_permission_grants(root_tenant_id,organization_id,role_assignment_id,permission_code,data_scope,scope_definition)
		VALUES
			(100,101,1101,'organization:view','organization_and_descendants','{}'::jsonb),
			(100,101,1101,'member:view','organization_and_descendants','{"organization_ids":["102"]}'::jsonb),
			(100,101,1101,'organization:future','organization_and_descendants','{}'::jsonb)
	`)
	require.NoError(t, err)

	authorizationRepo := repository.NewAuthorizationRepository(pool)
	service := NewAuthorizationService(authorizationRepo, NewOrganizationObjectResolver(authorizationRepo))
	actor := model.ActorContext{UserID: 700, RootTenantID: 100, OrganizationID: 101, MembershipID: 1001, MembershipVersion: 1}
	for _, tc := range []struct {
		name    string
		target  string
		allowed bool
	}{
		{name: "active organization", target: "101", allowed: true},
		{name: "descendant", target: "103", allowed: true},
		{name: "sibling", target: "104", allowed: false},
		{name: "cross tenant", target: "201", allowed: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			decision, err := service.Authorize(ctx, actor, model.AuthorizationRequest{
				PermissionCode: "organization:view",
				Object:         &model.ObjectRef{ResourceType: "organization", ResourceID: tc.target},
			})
			require.NoError(t, err)
			assert.Equal(t, tc.allowed, decision.Allowed)
		})
	}

	plan, err := service.BuildScope(ctx, actor, "organization:view", "organization")
	require.NoError(t, err)
	organizationRepository := repository.NewOrganizationRepository(pool)
	visible, err := organizationRepository.ListVisible(ctx, plan, 100, 0)
	require.NoError(t, err)
	ids := make([]int64, 0, len(visible))
	for _, organization := range visible {
		ids = append(ids, organization.ID)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	assert.Equal(t, []int64{101, 102, 103}, ids)
	visibleCount, err := organizationRepository.CountVisible(ctx, plan)
	require.NoError(t, err)
	assert.Equal(t, int64(3), visibleCount)
	visible103, err := organizationRepository.ExistsVisible(ctx, plan, 103)
	require.NoError(t, err)
	assert.True(t, visible103)
	visible104, err := organizationRepository.ExistsVisible(ctx, plan, 104)
	require.NoError(t, err)
	assert.False(t, visible104)

	memberPlan, err := service.BuildScope(ctx, actor, "member:view", "member")
	require.NoError(t, err)
	members102, err := organizationRepository.ListVisibleMemberships(ctx, memberPlan, 102, 100, 0)
	require.NoError(t, err)
	require.Len(t, members102, 1)
	assert.Equal(t, int64(701), members102[0].UserID)
	members103, err := organizationRepository.ListVisibleMemberships(ctx, memberPlan, 103, 100, 0)
	require.NoError(t, err)
	assert.Empty(t, members103, "scope_definition must narrow descendant member visibility")

	unknownPlan, err := service.BuildScope(ctx, actor, "organization:future", "organization")
	require.NoError(t, err)
	assert.Equal(t, model.DenyUnknownPermission, unknownPlan.DenyReason)
	unknownVisible, err := organizationRepository.ListVisible(ctx, unknownPlan, 100, 0)
	require.NoError(t, err)
	assert.Empty(t, unknownVisible, "repository must honor a deny-all scope plan even if DB contains the unknown permission")

	_, err = pool.Exec(ctx, `UPDATE users SET status=0 WHERE id=700`)
	require.NoError(t, err)
	revokedVisible, err := organizationRepository.ListVisible(ctx, plan, 100, 0)
	require.NoError(t, err)
	assert.Empty(t, revokedVisible, "a user disabled after BuildScope must immediately lose collection access")
	covered, err := authorizationRepo.OrganizationCoveredByGrant(ctx, actor, plan.Grants[0], 101)
	require.NoError(t, err)
	assert.False(t, covered, "final object resolver query must recheck user status")
	_, err = pool.Exec(ctx, `UPDATE users SET status=1 WHERE id=700`)
	require.NoError(t, err)

	outbox := repository.NewOutboxRepository()
	event := repository.OutboxEvent{
		EventID: uuid.New(), RootTenantID: 100, AggregateType: "organization", AggregateID: "101",
		EventType: "organization-updated", EventSchemaVersion: "1.0", Envelope: []byte(`{"schema_version":"1.0"}`),
	}
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	require.NoError(t, outbox.Enqueue(ctx, tx, event))
	require.NoError(t, tx.Rollback(ctx))
	var outboxCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM transactional_outbox WHERE event_id=$1`, event.EventID).Scan(&outboxCount))
	assert.Zero(t, outboxCount, "outbox event must roll back with its business transaction")
	tx, err = pool.Begin(ctx)
	require.NoError(t, err)
	require.NoError(t, outbox.Enqueue(ctx, tx, event))
	require.NoError(t, tx.Commit(ctx))
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM transactional_outbox WHERE event_id=$1`, event.EventID).Scan(&outboxCount))
	assert.Equal(t, 1, outboxCount)

	_, err = pool.Exec(ctx, `UPDATE organizations SET status='disabled' WHERE id=100`)
	require.NoError(t, err)
	decision, err := service.Authorize(ctx, actor, model.AuthorizationRequest{
		PermissionCode: "organization:view",
		Object:         &model.ObjectRef{ResourceType: "organization", ResourceID: "101"},
	})
	require.NoError(t, err)
	assert.False(t, decision.Allowed, "disabled ancestor must invalidate the active context")
	assert.Equal(t, model.DenyContextInactive, decision.Reason)
}

func authEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
