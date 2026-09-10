//go:build integration

package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestCheckDeviceOwnershipUsesManagementScope protects the App OTA contract:
// "visible in the organization subtree" means the actor may manage that device.
func TestCheckDeviceOwnershipUsesManagementScope(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	const (
		systemAdminID = int64(9201)
		installerID   = int64(9202)
		ownerID       = int64(9203)
		sharedUserID  = int64(9204)
		unrelatedID   = int64(9205)
		distributorID = int64(9206)
		agentID       = int64(9207)
		deviceSN      = "OTA-SCOPE-SN-001"
	)

	_, err := pool.Exec(ctx, `
		INSERT INTO users(id, phone, password_hash, is_system_admin, status) VALUES
			(9201, 'ota-admin-9201', 'hash', true, 1),
			(9202, 'ota-installer-9202', 'hash', false, 1),
			(9203, 'ota-owner-9203', 'hash', false, 1),
			(9204, 'ota-shared-9204', 'hash', false, 1),
			(9205, 'ota-unrelated-9205', 'hash', false, 1),
			(9206, 'ota-distributor-9206', 'hash', false, 1),
			(9207, 'ota-agent-9207', 'hash', false, 1);

		INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, code, name, status) VALUES
			(9210, 9210, NULL, 'manufacturer', 'OTA-SCOPE-ROOT', 'OTA Scope Root', 'active'),
			(9211, 9210, 9210, 'agent', 'OTA-SCOPE-AGENT', 'OTA Scope Agent', 'active'),
			(9212, 9210, 9211, 'distributor', 'OTA-SCOPE-DISTRIBUTOR', 'OTA Scope Distributor', 'active'),
			(9213, 9210, 9212, 'installer', 'OTA-SCOPE-INSTALLER', 'OTA Scope Installer', 'active'),
			(9214, 9210, 9213, 'customer', 'OTA-SCOPE-CUSTOMER', 'OTA Scope Customer', 'active');

		INSERT INTO organization_memberships(id, root_tenant_id, organization_id, user_id, status, version) VALUES
			(9221, 9210, 9211, 9207, 'active', 1),
			(9222, 9210, 9212, 9206, 'active', 1),
			(9223, 9210, 9213, 9202, 'active', 1),
			(9224, 9210, 9214, 9203, 'active', 1);

		INSERT INTO devices(sn, model, user_id) VALUES ($1, 'CS-INV-TEST', 9203);
	`, deviceSN)
	require.NoError(t, err)

	repo := NewOTARepository(pool)

	allowed, err := repo.CheckDeviceOwnership(ctx, deviceSN, systemAdminID)
	require.NoError(t, err)
	assert.True(t, allowed, "system administrator must manage every active device")

	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, ownerID)
	require.NoError(t, err)
	assert.True(t, allowed, "direct owner must manage the device")

	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, installerID)
	require.NoError(t, err)
	assert.True(t, allowed, "upstream organization member must manage descendant user devices")

	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, distributorID)
	require.NoError(t, err)
	assert.True(t, allowed, "distributor must manage installer descendant user devices")

	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, agentID)
	require.NoError(t, err)
	assert.True(t, allowed, "agent must manage distributor, installer, and customer descendant devices")

	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, unrelatedID)
	require.NoError(t, err)
	assert.False(t, allowed, "unrelated users must be denied")

	_, err = pool.Exec(ctx,
		`INSERT INTO user_device_rel(user_id, device_sn) VALUES ($1, $2)`,
		sharedUserID, deviceSN)
	require.NoError(t, err)
	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, sharedUserID)
	require.NoError(t, err)
	assert.True(t, allowed, "explicitly shared users must retain access")

	_, err = pool.Exec(ctx, `UPDATE devices SET deleted_at=NOW() WHERE sn=$1`, deviceSN)
	require.NoError(t, err)
	allowed, err = repo.CheckDeviceOwnership(ctx, deviceSN, systemAdminID)
	require.NoError(t, err)
	assert.False(t, allowed, "deleted devices must be denied even to system administrators")
}
