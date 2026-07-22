package repository

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

type recordingAuthorizationDB struct {
	query string
	args  []any
	err   error
}

func (d *recordingAuthorizationDB) Query(_ context.Context, query string, args ...any) (pgx.Rows, error) {
	d.query = query
	d.args = append([]any(nil), args...)
	return nil, d.err
}

func (d *recordingAuthorizationDB) QueryRow(_ context.Context, query string, args ...any) pgx.Row {
	d.query = query
	d.args = append([]any(nil), args...)
	return errorRow{err: d.err}
}

func (d *recordingAuthorizationDB) Exec(_ context.Context, query string, args ...any) (pgconn.CommandTag, error) {
	d.query = query
	d.args = append([]any(nil), args...)
	return pgconn.NewCommandTag(""), d.err
}

type errorRow struct{ err error }

func (r errorRow) Scan(...any) error { return r.err }

func repositoryActor() model.ActorContext {
	return model.ActorContext{UserID: 7, RootTenantID: 100, OrganizationID: 101, MembershipID: 1001, MembershipVersion: 3}
}

func normalizedSQL(query string) string {
	return strings.ToLower(strings.Join(strings.Fields(query), " "))
}

func TestAuthorizationRepositoryGrantQueryKeepsPermissionAndScopeCoupled(t *testing.T) {
	wantErr := errors.New("stop after recording")
	db := &recordingAuthorizationDB{err: wantErr}
	repo := newAuthorizationRepository(db)
	_, err := repo.LoadPermissionGrants(context.Background(), repositoryActor(), "organization:view")
	require.ErrorIs(t, err, wantErr)

	query := normalizedSQL(db.query)
	for _, fragment := range []string{
		"from organization_memberships m",
		"join organizations o",
		"join membership_role_assignments ra",
		"join role_permission_grants pg",
		"pg.permission_code=$6",
		"pg.data_scope",
		"m.status='active'",
		"m.expires_at is null or m.expires_at > now()",
		"ra.status='active'",
		"o.status='active'",
		"o.deleted_at is null",
		"m.version=$5",
		"m.root_tenant_id=$1",
		"m.organization_id=$3",
	} {
		assert.Contains(t, query, fragment)
	}
	assert.Equal(t, []any{int64(100), int64(7), int64(101), int64(1001), int64(3), "organization:view"}, db.args)
}

func TestResolveAuthorizationSessionContextChecksEveryRevocationBoundary(t *testing.T) {
	wantErr := errors.New("stop after recording")
	db := &recordingAuthorizationDB{err: wantErr}
	repo := newAuthorizationRepository(db)
	_, err := repo.ResolveAuthorizationSessionContext(context.Background(), 7, 101)
	require.ErrorIs(t, err, wantErr)

	query := normalizedSQL(db.query)
	for _, fragment := range []string{
		"m.authorization_version", "u.session_version", "m.user_id=$1",
		"m.organization_id=$2", "m.status='active'", "o.status='active'",
		"u.status=1", "organization_closure c", "ancestor.status<>'active'",
	} {
		assert.Contains(t, query, fragment)
	}
	assert.Equal(t, []any{int64(7), int64(101)}, db.args)
}

func TestResourceCoverageKeepsActorGrantAndOrganizationScopeCoupled(t *testing.T) {
	wantErr := errors.New("stop after recording")
	db := &recordingAuthorizationDB{err: wantErr}
	repo := newAuthorizationRepository(db)
	actor := repositoryActor()
	grant := model.PermissionGrant{ID: 55, RoleAssignmentID: 44, PermissionCode: "device:view", Scope: model.ScopeOrganizationAndDescendants}
	_, err := repo.ResourceCoveredByGrant(context.Background(), actor, grant, model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"})
	require.ErrorIs(t, err, wantErr)

	query := normalizedSQL(db.query)
	for _, fragment := range []string{
		"from authorization_resources target", "target.root_tenant_id=$1",
		"target.resource_type=$6", "target.resource_id=$7", "ra.id=$8",
		"pg.id=$9", "pg.permission_code=$10", "organization_closure c",
		"resource_grants rg", "subject_membership_id=m.id", "scope_definition",
	} {
		assert.Contains(t, query, fragment)
	}
	assert.Equal(t, []any{int64(100), int64(7), int64(101), int64(1001), int64(3), "device", "SN-1", int64(44), int64(55), "device:view"}, db.args)
}

func TestOrganizationRepositoryUsesDatabaseSetPredicatesWithoutExpandedIDs(t *testing.T) {
	wantErr := errors.New("stop after recording")
	db := &recordingAuthorizationDB{err: wantErr}
	repo := newOrganizationRepository(db)
	plan := model.ScopePlan{Actor: repositoryActor(), PermissionCode: "organization:view", ResourceType: "organization", Grants: []model.PermissionGrant{{ID: 1, PermissionCode: "organization:view", Scope: model.ScopeOrganization}}}
	_, err := repo.ListVisible(context.Background(), plan, 50, 0)
	require.ErrorIs(t, err, wantErr)

	query := normalizedSQL(db.query)
	for _, fragment := range []string{
		"with active_context as",
		"exists ( select 1 from active_context ac join membership_role_assignments ra",
		"join role_permission_grants pg",
		"organization_closure c",
		"c.root_tenant_id=ac.root_tenant_id",
		"resource_grants rg",
		"rg.root_tenant_id=ac.root_tenant_id",
		"authorization_resources ar",
		"jsonb_array_elements_text",
		"pg.permission_code=$6",
	} {
		assert.Contains(t, query, fragment)
	}
	assert.False(t, regexp.MustCompile(`(?i)\bin\s*\(\s*\$`).MatchString(db.query), "query must not expand organization IDs into IN parameters")
	for _, arg := range db.args {
		switch arg.(type) {
		case []int64, []string:
			t.Fatalf("collection query must use fixed scalar args, got %#v", arg)
		}
	}
	assert.Len(t, db.args, 8)
}

func TestOrganizationRepositoryMemberQueryReusesTrustedScope(t *testing.T) {
	wantErr := errors.New("stop after recording")
	db := &recordingAuthorizationDB{err: wantErr}
	repo := newOrganizationRepository(db)
	plan := model.ScopePlan{Actor: repositoryActor(), PermissionCode: "member:view", ResourceType: "member", Grants: []model.PermissionGrant{{ID: 1, PermissionCode: "member:view", Scope: model.ScopeOrganization}}}
	_, err := repo.ListVisibleMemberships(context.Background(), plan, 102, 25, 0)
	require.ErrorIs(t, err, wantErr)
	query := normalizedSQL(db.query)
	assert.Contains(t, query, "from organization_memberships candidate")
	assert.Contains(t, query, "candidate.root_tenant_id=ac.root_tenant_id")
	assert.Contains(t, query, "organization_closure c")
	assert.Contains(t, query, "candidate.user_id=ac.user_id")
	assert.NotContains(t, query, " union ")
}
