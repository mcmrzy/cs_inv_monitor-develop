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
// TestInvitationFlow — Invitation lifecycle tests
// =============================================================================

func TestInvitationCreate_ValidEmail(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-create")
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-org-%d", ts()), "agent", nil)

	data := ctx.createInvitation(t, email, 3, &orgID, 48)
	assert.NotEmpty(t, data["token_hint"], "should return token hint")
	assert.Equal(t, email, data["email"])
	assert.Equal(t, "pending", data["status"])
}

func TestInvitationCreate_DuplicateEmail(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-dup")
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-dup-org-%d", ts()), "agent", nil)

	ctx.createInvitation(t, email, 3, &orgID, 48)

	// Second invitation with same email → should conflict
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/invitations/create",
		map[string]interface{}{
			"email": email, "role_id": 3, "organization_id": orgID, "expires_hours": 48,
		}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("dup invitation: code=%d msg=%s", resp.Code, resp.Message)
	// May return 409/conflict or a business error code
	assert.NotEqual(t, 0, resp.Code, "duplicate email should be rejected")
}

func TestInvitationCreate_InvalidEmail(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/invitations/create",
		map[string]interface{}{
			"email": "not-an-email", "role_id": 3, "expires_hours": 48,
		}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "invalid email should be rejected")
}

func TestInvitationCreate_InvalidRoleID(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-badrole")
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/invitations/create",
		map[string]interface{}{
			"email": email, "role_id": 99, "expires_hours": 48,
		}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "invalid role_id should be rejected")
}

func TestInvitationAccept_ValidCode(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-accept")
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-acc-org-%d", ts()), "agent", nil)

	invData := ctx.createInvitation(t, email, 3, &orgID, 48)
	tokenHint, _ := invData["token_hint"].(string)
	require.NotEmpty(t, tokenHint, "need token hint to accept")

	// For the accept flow we need the full invitation code, not just the hint.
	// The create response may contain a "token" or "invitation_code" field.
	// If the API only returns token_hint (first 8 chars), we need to use the full code.
	// Check if full token is available in the response.
	fullCode, _ := invData["invitation_code"].(string)
	if fullCode == "" {
		fullCode, _ = invData["token"].(string)
	}
	if fullCode == "" {
		t.Skip("invitation API does not return full code in response — cannot test accept flow")
		return
	}

	acceptPayload := map[string]interface{}{
		"invitation_code": fullCode,
		"password":        "Accept@2026",
		"phone":           fmt.Sprintf("152%08d", ts()%100000000),
		"nickname":        fmt.Sprintf("invited_%d", ts()),
	}
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/invite/accept", acceptPayload, "", 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "accept should succeed: %s", resp.Message)

	var acceptData map[string]interface{}
	if resp.Data != nil {
		require.NoError(t, json.Unmarshal(resp.Data, &acceptData))
		assert.NotEmpty(t, acceptData["access_token"], "should auto-login after acceptance")
	}
}

func TestInvitationAccept_WrongCode(t *testing.T) {
	ctx := setupChannelTest(t)

	acceptPayload := map[string]interface{}{
		"invitation_code": "INVALID-CODE-12345",
		"password":        "Accept@2026",
		"phone":           fmt.Sprintf("153%08d", ts()%100000000),
		"nickname":        "wrong_code_user",
	}
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/invite/accept", acceptPayload, "", 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "wrong code should be rejected")
	t.Logf("wrong code: code=%d msg=%s", resp.Code, resp.Message)
}

func TestInvitationList_WithStatusFilter(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-list-org-%d", ts()), "agent", nil)

	// Create several invitations
	for i := 0; i < 3; i++ {
		ctx.createInvitation(t, uniqueEmail("inv-list"), 3, &orgID, 48)
	}

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/invitations/list?status=pending&page=1&page_size=20", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	total, _ := data["total"].(float64)
	assert.GreaterOrEqual(t, int(total), 3, "should list at least 3 pending invitations")
}

func TestInvitationRevoke_Pending(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-revoke")
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-rev-org-%d", ts()), "agent", nil)

	invData := ctx.createInvitation(t, email, 3, &orgID, 48)
	invID, _ := invData["id"].(float64)
	require.NotZero(t, invID, "invitation ID should be present")

	resp, status := doJSONWithRetry(t, ctx.Client, "DELETE",
		fmt.Sprintf("%s/api/v1/invitations/%d/revoke", ctx.BaseURL, int64(invID)), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "revoke pending invitation should succeed: %s", resp.Message)

	// Verify status changed
	detailsResp, _ := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/invitations/%d/details", ctx.BaseURL, int64(invID)), nil, ctx.Token, 5)
	var detData map[string]interface{}
	if detailsResp.Data != nil {
		require.NoError(t, json.Unmarshal(detailsResp.Data, &detData))
		assert.Equal(t, "revoked", detData["status"])
	}
}

func TestInvitationRevoke_AlreadyRevoked(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-rev2")
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-rev2-org-%d", ts()), "agent", nil)

	invData := ctx.createInvitation(t, email, 3, &orgID, 48)
	invID, _ := invData["id"].(float64)

	// Revoke first time
	doJSONWithRetry(t, ctx.Client, "DELETE",
		fmt.Sprintf("%s/api/v1/invitations/%d/revoke", ctx.BaseURL, int64(invID)), nil, ctx.Token, 5)

	// Revoke again → should conflict or error
	resp, status := doJSONWithRetry(t, ctx.Client, "DELETE",
		fmt.Sprintf("%s/api/v1/invitations/%d/revoke", ctx.BaseURL, int64(invID)), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "re-revoking should fail")
	t.Logf("re-revoke: code=%d msg=%s", resp.Code, resp.Message)
}

func TestInvitationDetails_Found(t *testing.T) {
	ctx := setupChannelTest(t)
	email := uniqueEmail("inv-detail")
	orgID := ctx.createOrg(t, fmt.Sprintf("inv-det-org-%d", ts()), "agent", nil)

	invData := ctx.createInvitation(t, email, 3, &orgID, 48)
	invID, _ := invData["id"].(float64)

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/invitations/%d/details", ctx.BaseURL, int64(invID)), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	assert.Equal(t, email, data["email"])
}

func TestInvitationDetails_NotFound(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/invitations/999999999/details", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code)
}

func TestInvitationCreate_UnauthorizedNoToken(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")
	client := &http.Client{Timeout: 10 * time.Second}

	resp, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/invitations/create",
		map[string]interface{}{
			"email": "noauth@test.com", "role_id": 3, "expires_hours": 48,
		}, "")
	assert.Equal(t, http.StatusUnauthorized, status, "should require auth")
	_ = resp
}
