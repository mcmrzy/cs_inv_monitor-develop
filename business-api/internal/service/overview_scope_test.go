package service

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
)

func TestOverviewBuildScopeUsesExactStoredPermission(t *testing.T) {
	for _, resource := range []string{"device", "station"} {
		t.Run(resource, func(t *testing.T) {
			permission := resource + "s:view"
			repo := &fakeAuthorizationRepository{active: true, grants: []model.PermissionGrant{
				{ID: 1, PermissionCode: permission, Scope: model.ScopeOrganizationAndDescendants},
				{ID: 2, PermissionCode: resource + ":view", Scope: model.ScopeOrganizationAndDescendants},
			}}
			plan, err := NewAuthorizationService(repo).BuildScope(context.Background(), activeActor(), permission, resource)
			require.NoError(t, err)
			require.Empty(t, plan.DenyReason)
			require.Len(t, plan.Grants, 1)
			require.Equal(t, int64(1), plan.Grants[0].ID)
			repo.active = false
			plan, err = NewAuthorizationService(repo).BuildScope(context.Background(), activeActor(), permission, resource)
			require.NoError(t, err)
			require.Equal(t, model.DenyContextInactive, plan.DenyReason)
		})
	}
}
