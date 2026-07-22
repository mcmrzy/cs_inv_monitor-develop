package migration

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func ptr[T any](value T) *T { return &value }

func validRoleMappings() []LegacyRoleMapping {
	return []LegacyRoleMapping{
		{LegacyRole: 1, OrganizationType: "manufacturer", RoleCodes: []string{"org_admin"}},
		{LegacyRole: 2, OrganizationType: "agent", RoleCodes: []string{"channel_manager"}},
		{LegacyRole: 3, OrganizationType: "distributor", RoleCodes: []string{"channel_manager"}},
		{LegacyRole: 5, OrganizationType: "customer", RoleCodes: []string{"viewer"}},
	}
}

func TestAnalyzeLegacyUsersFailsClosedOnRoleMappings(t *testing.T) {
	users := []LegacyUser{{ID: 1, Phone: "13800000001", Role: 1}}

	t.Run("unmapped numeric role", func(t *testing.T) {
		report := AnalyzeLegacyUsers(users, nil, nil)
		require.Empty(t, report.Operations)
		assert.Contains(t, report.ReasonsFor(1), ReasonUnmappedLegacyRole)
	})

	t.Run("conflicting duplicate mapping", func(t *testing.T) {
		mappings := []LegacyRoleMapping{
			{LegacyRole: 1, OrganizationType: "manufacturer", RoleCodes: []string{"org_admin"}},
			{LegacyRole: 1, OrganizationType: "agent", RoleCodes: []string{"channel_manager"}},
		}
		report := AnalyzeLegacyUsers(users, mappings, nil)
		require.Empty(t, report.Operations)
		assert.Contains(t, report.ReasonsFor(1), ReasonConflictingRoleMapping)
	})
}

func TestAnalyzeLegacyUsersQuarantinesInvalidGraphsAndIdentifiers(t *testing.T) {
	tests := []struct {
		name   string
		users  []LegacyUser
		userID int64
		reason string
	}{
		{
			name: "parent cycle",
			users: []LegacyUser{
				{ID: 1, Phone: "1", Role: 2, ParentID: ptr[int64](2)},
				{ID: 2, Phone: "2", Role: 2, ParentID: ptr[int64](1)},
			},
			userID: 1, reason: ReasonParentCycle,
		},
		{
			name: "orphan parent",
			users: []LegacyUser{
				{ID: 3, Phone: "3", Role: 3, ParentID: ptr[int64](999)},
			},
			userID: 3, reason: ReasonOrphanParent,
		},
		{
			name: "duplicate normalized identifier",
			users: []LegacyUser{
				{ID: 4, Phone: " 13800000004 ", Email: " Alice@Example.com ", Role: 1},
				{ID: 5, Phone: "13800000005", Email: "alice@example.COM", Role: 1},
			},
			userID: 4, reason: ReasonDuplicateIdentifier,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			report := AnalyzeLegacyUsers(tc.users, validRoleMappings(), nil)
			assert.Contains(t, report.ReasonsFor(tc.userID), tc.reason)
		})
	}
}

func TestAnalyzeLegacyUsersExcludesEveryInvalidNodeAndBlockedDescendant(t *testing.T) {
	users := []LegacyUser{
		{ID: 20, Phone: "20", Role: 2, ParentID: ptr[int64](21)},
		{ID: 21, Phone: "21", Role: 2, ParentID: ptr[int64](20)},
		{ID: 22, Phone: "22", Role: 3, ParentID: ptr[int64](20)},
		{ID: 23, Phone: " duplicate ", Role: 1},
		{ID: 24, Phone: "duplicate", Role: 1},
	}
	report := AnalyzeLegacyUsers(users, validRoleMappings(), nil)
	assert.Contains(t, report.ReasonsFor(20), ReasonParentCycle)
	assert.Contains(t, report.ReasonsFor(21), ReasonParentCycle)
	assert.Contains(t, report.ReasonsFor(22), ReasonBlockedAncestor)
	assert.Contains(t, report.ReasonsFor(23), ReasonDuplicateIdentifier)
	assert.Contains(t, report.ReasonsFor(24), ReasonDuplicateIdentifier)
	assert.Empty(t, report.Operations)
}

func TestChannelMappingDigestDoesNotMutateConfig(t *testing.T) {
	config := ChannelMappingConfig{
		SchemaVersion: "1",
		Roles:         []LegacyRoleMapping{{LegacyRole: 1, OrganizationType: "manufacturer", RoleCodes: []string{"viewer", "org_admin"}}},
	}
	before := append([]string(nil), config.Roles[0].RoleCodes...)
	_, err := config.Digest()
	require.NoError(t, err)
	assert.Equal(t, before, config.Roles[0].RoleCodes)
	assert.Error(t, ValidateChannelMappingConfig(ChannelMappingConfig{SchemaVersion: "2", Roles: config.Roles}))
}

func TestAnalyzeLegacyUsersQuarantinesOwnerConflictsWithoutPlanningAssets(t *testing.T) {
	users := []LegacyUser{{ID: 10, Phone: "10", Role: 1}}
	facts := []LegacyOwnershipFact{
		{ResourceType: "device", ResourceKey: "SN-1", OwnerUserID: 10},
		{ResourceType: "device", ResourceKey: "SN-1", OwnerUserID: 11},
	}
	report := AnalyzeLegacyUsers(users, validRoleMappings(), facts)
	require.Len(t, report.OwnershipQuarantine, 1)
	assert.Equal(t, ReasonOwnerConflict, report.OwnershipQuarantine[0].ReasonCode)
	assert.NotEmpty(t, report.Operations, "asset conflicts must not block clean organization planning")
	for _, operation := range report.Operations {
		assert.NotEqual(t, "asset", operation.Kind)
	}
}

func TestAnalyzeLegacyUsersBuildsDeterministicHierarchy(t *testing.T) {
	users := []LegacyUser{
		{ID: 103, Phone: "103", Role: 5, ParentID: ptr[int64](102)},
		{ID: 100, Phone: "100", Role: 1},
		{ID: 102, Phone: "102", Role: 3, ParentID: ptr[int64](101)},
		{ID: 101, Phone: "101", Role: 2, ParentID: ptr[int64](100)},
	}
	report := AnalyzeLegacyUsers(users, validRoleMappings(), nil)
	require.Empty(t, report.Quarantine)
	require.Len(t, report.Operations, 4)
	assert.Equal(t, []int64{100, 101, 102, 103}, []int64{
		report.Operations[0].SourceUserID,
		report.Operations[1].SourceUserID,
		report.Operations[2].SourceUserID,
		report.Operations[3].SourceUserID,
	})
	assert.Equal(t, int64(100), report.Operations[3].RootTenantID)
}

type memoryChannelBackfillStore struct {
	checkpoint int
	applied    map[int64]BackfillOperation
	failOnce   bool
}

func (s *memoryChannelBackfillStore) LoadCheckpoint(context.Context, string, string) (int, error) {
	return s.checkpoint, nil
}

func (s *memoryChannelBackfillStore) ApplyBatch(_ context.Context, _ string, _ string, after int, operations []BackfillOperation) (int, error) {
	if s.failOnce {
		s.failOnce = false
		return after, errors.New("simulated transaction rollback")
	}
	if s.applied == nil {
		s.applied = make(map[int64]BackfillOperation)
	}
	for _, operation := range operations {
		s.applied[operation.SourceUserID] = operation
	}
	s.checkpoint = after + len(operations)
	return s.checkpoint, nil
}

func TestExecuteOrganizationBackfillCheckpointIsIdempotent(t *testing.T) {
	operations := AnalyzeLegacyUsers([]LegacyUser{
		{ID: 1, Phone: "1", Role: 1},
		{ID: 2, Phone: "2", Role: 2, ParentID: ptr[int64](1)},
	}, validRoleMappings(), nil).Operations
	store := &memoryChannelBackfillStore{}

	first, err := ExecuteOrganizationBackfill(context.Background(), store, "digest-a", operations, 1)
	require.NoError(t, err)
	assert.Equal(t, 2, first.Applied)
	second, err := ExecuteOrganizationBackfill(context.Background(), store, "digest-a", operations, 1)
	require.NoError(t, err)
	assert.Zero(t, second.Applied)
	assert.Len(t, store.applied, 2)

	rollbackStore := &memoryChannelBackfillStore{failOnce: true}
	_, err = ExecuteOrganizationBackfill(context.Background(), rollbackStore, "digest-a", operations, 2)
	require.Error(t, err)
	assert.Zero(t, rollbackStore.checkpoint)
	result, err := ExecuteOrganizationBackfill(context.Background(), rollbackStore, "digest-a", operations, 2)
	require.NoError(t, err)
	assert.Equal(t, 2, result.Applied)
	assert.Len(t, rollbackStore.applied, 2)
}
