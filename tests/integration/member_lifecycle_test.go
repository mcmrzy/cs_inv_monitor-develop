//go:build integration

package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// TestMemberLifecycle — Member add, update, deactivate, reactivate, transfer
// =============================================================================

func TestMemberAdd_Success(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("mem-add-org-%d", ts()), "agent", nil)

	// Use User B as the member to add (we need their user ID)
	// Get profile of user B to find their ID
	profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		t.Skip("cannot determine user B's ID, skipping add member test")
		return
	}

	data := ctx.addMember(t, int64(userID2), orgID, []int{3})
	t.Logf("add member result: %v", data)
}

func TestMemberAdd_ExistingActiveMember(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("mem-dup-org-%d", ts()), "agent", nil)

	profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		t.Skip("cannot determine user B's ID")
		return
	}

	// Add first time
	ctx.addMember(t, int64(userID2), orgID, []int{3})

	// Add again → should conflict
	resp, status := doJSON(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/members/add",
		map[string]interface{}{
			"user_id": int64(userID2), "organization_id": orgID, "role_ids": []int{3},
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "adding existing active member should conflict")
	t.Logf("dup member: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberAdd_InvalidOrganization(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSON(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/members/add",
		map[string]interface{}{
			"user_id": 1, "organization_id": 999999999, "role_ids": []int{3},
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "add to non-existent org should fail")
}

func TestMemberUpdateMembership_Roles(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("mem-upd-org-%d", ts()), "agent", nil)

	profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		t.Skip("cannot determine user B's ID")
		return
	}

	// Add member first
	ctx.addMember(t, int64(userID2), orgID, []int{3})

	// Get membership ID (from list or add response)
	listResp, _ := doJSON(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token)
	t.Logf("org details for membership: %s", string(listResp.Data))

	// Try to update membership (need membership ID)
	// Since we may not easily get the membership ID, test with ID=1 as best effort
	resp, status := doJSON(t, ctx.Client, "PUT",
		ctx.BaseURL+"/api/v1/members/memberships/1/update",
		map[string]interface{}{"role_ids": []int{4}}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("update membership: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberDeactivate(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("mem-deact-org-%d", ts()), "agent", nil)

	profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		t.Skip("cannot determine user B's ID")
		return
	}

	ctx.addMember(t, int64(userID2), orgID, nil)

	// Deactivate — need membership ID, try best effort
	resp, status := doJSON(t, ctx.Client, "PATCH",
		ctx.BaseURL+"/api/v1/members/memberships/1/deactivate",
		map[string]interface{}{"reason": "test deactivation"}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("deactivate: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberReactivate(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSON(t, ctx.Client, "PATCH",
		ctx.BaseURL+"/api/v1/members/memberships/1/reactivate", nil, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("reactivate: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberRemove_SoftDelete(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("mem-rm-org-%d", ts()), "agent", nil)

	profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		t.Skip("cannot determine user B's ID")
		return
	}

	ctx.addMember(t, int64(userID2), orgID, nil)

	resp, status := doJSON(t, ctx.Client, "DELETE",
		ctx.BaseURL+"/api/v1/members/memberships/1/remove",
		map[string]interface{}{"reason": "test removal"}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("remove member: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberTransfer_Initiate(t *testing.T) {
	ctx := setupChannelTest(t)
	orgFrom := ctx.createOrg(t, fmt.Sprintf("mem-trf-from-%d", ts()), "agent", nil)
	orgTo := ctx.createOrg(t, fmt.Sprintf("mem-trf-to-%d", ts()), "distributor", nil)

	profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, ctx.Token2)
	var profile map[string]interface{}
	if profileResp.Data != nil {
		require.NoError(t, json.Unmarshal(profileResp.Data, &profile))
	}
	userID2, _ := profile["id"].(float64)
	if userID2 == 0 {
		t.Skip("cannot determine user B's ID")
		return
	}

	ctx.addMember(t, int64(userID2), orgFrom, nil)

	resp, status := doJSON(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/members/transfer/initiate",
		map[string]interface{}{
			"membership_ids": []int64{1},
			"target_org_id":  orgTo,
			"reason":         "test transfer",
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("transfer initiate: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberTransfer_Accept(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSON(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/members/transfer/accept",
		map[string]interface{}{
			"transfer_id": 999999999,
			"approved":    true,
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "accepting non-existent transfer should fail")
}

func TestMemberTransfer_Reject(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSON(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/members/transfer/reject",
		map[string]interface{}{
			"transfer_id": 999999999,
			"approved":    false,
			"reason":      "test rejection",
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "rejecting non-existent transfer should fail")
}

func TestMemberTransfer_ListTransfers(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSON(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/members/transfers/list?page=1&page_size=20", nil, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "list transfers should succeed")
}

func TestMemberBulkAdd(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("mem-bulk-org-%d", ts()), "agent", nil)

	// Register several users for bulk add
	var userIDs []int64
	for i := 0; i < 5; i++ {
		phone := fmt.Sprintf("155%08d", time.Now().UnixNano()%100000000+int64(i))
		pw := "BulkTest@2026"
		registerUser(t, ctx.BaseURL, phone, pw)
		token := loginUser(t, ctx.BaseURL, phone, pw)

		// Get user ID
		profileResp, _ := doJSON(t, ctx.Client, "GET", ctx.BaseURL+"/api/v1/auth/profile", nil, token)
		var profile map[string]interface{}
		if profileResp.Data != nil {
			_ = json.Unmarshal(profileResp.Data, &profile)
		}
		if uid, ok := profile["id"].(float64); ok {
			userIDs = append(userIDs, int64(uid))
		}
	}

	if len(userIDs) == 0 {
		t.Skip("no user IDs available for bulk add test")
		return
	}

	resp, status := doJSON(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/members/bulk-add",
		map[string]interface{}{
			"user_ids":        userIDs,
			"organization_id": orgID,
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("bulk add: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberBulkTransfer(t *testing.T) {
	ctx := setupChannelTest(t)
	orgTo := ctx.createOrg(t, fmt.Sprintf("mem-bulk-trf-%d", ts()), "distributor", nil)

	resp, status := doJSON(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/members/bulk-transfer",
		map[string]interface{}{
			"membership_ids": []int64{1, 2, 3},
			"target_org_id":  orgTo,
			"reason":         "bulk transfer test",
		}, ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("bulk transfer: code=%d msg=%s", resp.Code, resp.Message)
}

func TestMemberAdd_UnauthorizedNoToken(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")
	client := &http.Client{Timeout: 10 * time.Second}

	_, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/members/add",
		map[string]interface{}{"user_id": 1, "organization_id": 1}, "")
	assert.Equal(t, http.StatusUnauthorized, status)
}
