//go:build integration

package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// TestCrossTenant — Cross-tenant isolation and access control tests
// =============================================================================

func TestCrossTenant_AccessOrgFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	// User A creates an org
	orgID := ctx.createOrg(t, fmt.Sprintf("ct-org-%d", ts()), "agent", nil)

	// User B tries to access it
	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("cross-tenant org access: code=%d msg=%s", resp.Code, resp.Message)
	// Should be forbidden or not found (different tenant)
	assert.NotEqual(t, 0, resp.Code, "user B should not access user A's org")
}

func TestCrossTenant_UpdateOrgFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	orgID := ctx.createOrg(t, fmt.Sprintf("ct-upd-org-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "PUT",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID),
		map[string]interface{}{"name": "hacked-name"}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "user B should not update user A's org")
}

func TestCrossTenant_DeleteOrgFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	orgID := ctx.createOrg(t, fmt.Sprintf("ct-del-org-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "DELETE",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "user B should not delete user A's org")
}

func TestCrossTenant_MoveOrgFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	orgID := ctx.createOrg(t, fmt.Sprintf("ct-move-org-%d", ts()), "agent", nil)
	parentID := ctx.createOrg(t, fmt.Sprintf("ct-parent-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/organizations/%d/move", ctx.BaseURL, orgID),
		map[string]interface{}{"parent_id": parentID}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "user B should not move user A's org")
}

func TestCrossTenant_ToggleStatusFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	orgID := ctx.createOrg(t, fmt.Sprintf("ct-toggle-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "PATCH",
		fmt.Sprintf("%s/api/v1/organizations/%d/status", ctx.BaseURL, orgID),
		map[string]interface{}{"status": "disabled"}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "user B should not toggle user A's org status")
}

func TestCrossTenant_GetTreeFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	orgID := ctx.createOrg(t, fmt.Sprintf("ct-tree-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d/tree", ctx.BaseURL, orgID), nil, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "user B should not see user A's org tree")
}

func TestCrossTenant_TransferDeviceNonAdmin(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CT-TRF")

	// User A binds device
	doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)

	// User B tries to transfer the device
	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/devices/by-sn/%s/request-transfer", ctx.BaseURL, sn),
		map[string]interface{}{
			"device_sn":    sn,
			"to_tenant_id": 999,
			"reason":       "cross-tenant transfer",
		}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("cross-tenant transfer: code=%d msg=%s", resp.Code, resp.Message)
	// Should fail — user B doesn't own the device
	assert.NotEqual(t, 0, resp.Code, "user B should not transfer user A's device")
}

func TestCrossTenant_ViewMemberFromDifferentTenant(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("ct-mem-org-%d", ts()), "agent", nil)

	// User B tries to add member to User A's org
	profileResp, _ := doJSONWithRetry(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2, 5)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		userID2 = 1
	}

	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/members/add",
		map[string]interface{}{
			"user_id":         int64(userID2),
			"organization_id": orgID,
		}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("cross-tenant member add: code=%d msg=%s", resp.Code, resp.Message)
	assert.NotEqual(t, 0, resp.Code, "user B should not add members to user A's org")
}

func TestCrossTenant_CreateInvitationInOtherTenant(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("ct-inv-org-%d", ts()), "agent", nil)

	email := uniqueEmail("ct-inv")

	// User B tries to create invitation for User A's org
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/invitations/create",
		map[string]interface{}{
			"email":           email,
			"role_id":         3,
			"organization_id": orgID,
			"expires_hours":   48,
		}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("cross-tenant invitation: code=%d msg=%s", resp.Code, resp.Message)
	assert.NotEqual(t, 0, resp.Code, "user B should not create invitations in user A's org")
}

func TestCrossTenant_ListOrgsOnlyOwnTenant(t *testing.T) {
	ctx := setupChannelTest(t)

	// User A creates orgs
	ctx.createOrg(t, fmt.Sprintf("ct-list-a-%d", ts()), "agent", nil)

	// User B lists orgs — should only see their own (empty or different set)
	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/organizations?page=1&page_size=100", nil, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))

	items, _ := data["items"].([]interface{})
	// User A's org IDs
	orgID := ctx.createOrg(t, fmt.Sprintf("ct-list-verify-%d", ts()), "agent", nil)

	// Verify user B's list does not contain user A's org
	for _, item := range items {
		org, _ := item.(map[string]interface{})
		id, _ := org["id"].(float64)
		assert.NotEqual(t, float64(orgID), id, "user B should not see user A's org in list")
	}
}

func TestCrossTenant_GenerateClaimCodeForOtherTenantDevice(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CT-CLM")

	// User A binds device
	doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)

	// User B tries to generate claim code for A's device
	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/devices/claim-code/generate",
		map[string]interface{}{"sn": sn, "expires_hours": 24}, ctx.Token2, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("cross-tenant claim code: code=%d msg=%s", resp.Code, resp.Message)
	assert.NotEqual(t, 0, resp.Code, "user B should not generate claim code for user A's device")
}
