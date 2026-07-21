package service

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

type fakeAuthorizationRepository struct {
	active bool
	grants []model.PermissionGrant
	err    error
}

func (r *fakeAuthorizationRepository) ValidateContext(context.Context, model.ActorContext) (bool, error) {
	return r.active, r.err
}

func (r *fakeAuthorizationRepository) LoadPermissionGrants(context.Context, model.ActorContext, string) ([]model.PermissionGrant, error) {
	return append([]model.PermissionGrant(nil), r.grants...), r.err
}

type fakeObjectResolver struct {
	resourceType string
	coveredGrant map[int64]bool
	err          error
}

func (r *fakeObjectResolver) ResourceType() string { return r.resourceType }

func (r *fakeObjectResolver) Covers(_ context.Context, _ model.ActorContext, grant model.PermissionGrant, _ model.ObjectRef) (bool, error) {
	return r.coveredGrant[grant.ID], r.err
}

func activeActor() model.ActorContext {
	return model.ActorContext{UserID: 7, RootTenantID: 100, OrganizationID: 101, MembershipID: 1001, MembershipVersion: 1}
}

func TestAuthorizationServiceDeniesUnlessOneCoupledGrantCoversObject(t *testing.T) {
	tests := []struct {
		name     string
		repo     *fakeAuthorizationRepository
		resolver ObjectResolver
		request  model.AuthorizationRequest
		allowed  bool
		reason   model.DenyReason
	}{
		{
			name:    "inactive context",
			repo:    &fakeAuthorizationRepository{active: false},
			request: model.AuthorizationRequest{PermissionCode: "device:unbind", Object: &model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"}},
			reason:  model.DenyContextInactive,
		},
		{
			name:    "permission missing",
			repo:    &fakeAuthorizationRepository{active: true},
			request: model.AuthorizationRequest{PermissionCode: "device:unbind", Object: &model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"}},
			reason:  model.DenyPermissionNotGranted,
		},
		{
			name:     "unknown scope",
			repo:     &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{{ID: 1, PermissionCode: "device:unbind", Scope: "future_scope"}}},
			resolver: &fakeObjectResolver{resourceType: "device", coveredGrant: map[int64]bool{1: true}},
			request:  model.AuthorizationRequest{PermissionCode: "device:unbind", Object: &model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"}},
			reason:   model.DenyUnsupportedScope,
		},
		{
			name:    "resolver unavailable",
			repo:    &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{{ID: 1, PermissionCode: "device:unbind", Scope: model.ScopeOrganization}}},
			request: model.AuthorizationRequest{PermissionCode: "device:unbind", Object: &model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"}},
			reason:  model.DenyResolverUnavailable,
		},
		{
			name: "multi role cannot splice permission and wide scope",
			repo: &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{
				{ID: 1, RoleAssignmentID: 11, PermissionCode: "device:unbind", Scope: model.ScopeSelf},
				{ID: 2, RoleAssignmentID: 12, PermissionCode: "device:view", Scope: model.ScopeOrganizationAndDescendants},
			}},
			resolver: &fakeObjectResolver{resourceType: "device", coveredGrant: map[int64]bool{1: false, 2: true}},
			request:  model.AuthorizationRequest{PermissionCode: "device:unbind", Object: &model.ObjectRef{ResourceType: "device", ResourceID: "SN-DESC"}},
			reason:   model.DenyObjectOutOfScope,
		},
		{
			name:     "one complete grant allows",
			repo:     &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{{ID: 3, RoleAssignmentID: 13, PermissionCode: "organization:view", Scope: model.ScopeOrganizationAndDescendants}}},
			resolver: &fakeObjectResolver{resourceType: "organization", coveredGrant: map[int64]bool{3: true}},
			request:  model.AuthorizationRequest{PermissionCode: "organization:view", Object: &model.ObjectRef{ResourceType: "organization", ResourceID: "103"}},
			allowed:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			service := NewAuthorizationService(tc.repo, tc.resolver)
			decision, err := service.Authorize(context.Background(), activeActor(), tc.request)
			require.NoError(t, err)
			assert.Equal(t, tc.allowed, decision.Allowed)
			assert.Equal(t, tc.reason, decision.Reason)
		})
	}
}

func TestAuthorizationServiceFailsClosedOnRepositoryAndResolverErrors(t *testing.T) {
	wantErr := errors.New("database unavailable")
	service := NewAuthorizationService(&fakeAuthorizationRepository{active: true, err: wantErr})
	decision, err := service.Authorize(context.Background(), activeActor(), model.AuthorizationRequest{PermissionCode: "organization:view", Object: &model.ObjectRef{ResourceType: "organization", ResourceID: "101"}})
	assert.False(t, decision.Allowed)
	assert.ErrorIs(t, err, wantErr)

	service = NewAuthorizationService(
		&fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{{ID: 1, PermissionCode: "organization:view", Scope: model.ScopeOrganization}}},
		&fakeObjectResolver{resourceType: "organization", err: wantErr},
	)
	decision, err = service.Authorize(context.Background(), activeActor(), model.AuthorizationRequest{PermissionCode: "organization:view", Object: &model.ObjectRef{ResourceType: "organization", ResourceID: "101"}})
	assert.False(t, decision.Allowed)
	assert.ErrorIs(t, err, wantErr)
}

func TestAuthorizationServiceBuildScopePreservesGrantPairing(t *testing.T) {
	repo := &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{
		{ID: 1, RoleAssignmentID: 11, PermissionCode: "organization:view", Scope: model.ScopeOrganization},
		{ID: 2, RoleAssignmentID: 12, PermissionCode: "member:manage", Scope: model.ScopeOrganizationAndDescendants},
	}}
	service := NewAuthorizationService(repo)
	plan, err := service.BuildScope(context.Background(), activeActor(), "organization:view", "organization")
	require.NoError(t, err)
	require.Len(t, plan.Grants, 1)
	assert.Equal(t, int64(1), plan.Grants[0].ID)
	assert.Equal(t, model.ScopeOrganization, plan.Grants[0].Scope)
}

func TestAuthorizationServiceUnknownPermissionAndResourceMismatchFailClosed(t *testing.T) {
	repo := &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{
		{ID: 9, PermissionCode: "device:super_control", Scope: model.ScopeOrganizationAndDescendants},
	}}
	resolver := &fakeObjectResolver{resourceType: "device", coveredGrant: map[int64]bool{9: true}}
	service := NewAuthorizationService(repo, resolver)
	decision, err := service.Authorize(context.Background(), activeActor(), model.AuthorizationRequest{
		PermissionCode: "device:super_control",
		Object:         &model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"},
	})
	require.NoError(t, err)
	assert.False(t, decision.Allowed)
	assert.Equal(t, model.DenyUnknownPermission, decision.Reason)

	decision, err = service.Authorize(context.Background(), activeActor(), model.AuthorizationRequest{
		PermissionCode: "organization:view",
		Object:         &model.ObjectRef{ResourceType: "device", ResourceID: "SN-1"},
	})
	require.NoError(t, err)
	assert.False(t, decision.Allowed)
	assert.Equal(t, model.DenyInvalidRequest, decision.Reason)

	decision, err = service.Authorize(context.Background(), activeActor(), model.AuthorizationRequest{PermissionCode: "device:unbind"})
	require.NoError(t, err)
	assert.False(t, decision.Allowed)
	assert.Equal(t, model.DenyInvalidRequest, decision.Reason)
}
