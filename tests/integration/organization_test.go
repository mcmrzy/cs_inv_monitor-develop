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
// TestOrganizationFlow 鈥?Comprehensive organization CRUD + hierarchy tests
// =============================================================================

func TestOrganizationCreate_ValidData(t *testing.T) {
	ctx := setupChannelTest(t)
	name := fmt.Sprintf("org-create-%d", ts())

	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/organizations",
		map[string]interface{}{"name": name, "type": "agent"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "msg=%s", resp.Message)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	assert.Equal(t, name, data["name"])
	assert.Equal(t, "agent", data["type"])
	assert.Equal(t, "active", data["status"])
	assert.NotZero(t, data["id"])
}

func TestOrganizationCreate_InvalidType(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/organizations",
		map[string]interface{}{"name": "bad-type", "type": "unknown_type"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "should reject invalid org type")
}

func TestOrganizationCreate_MissingName(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/organizations",
		map[string]interface{}{"type": "agent"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "should reject missing name")
}

func TestOrganizationList_Pagination(t *testing.T) {
	ctx := setupChannelTest(t)
	// Create 3 orgs
	for i := 0; i < 3; i++ {
		ctx.createOrg(t, fmt.Sprintf("org-list-%d-%d", ts(), i), "distributor", nil)
	}

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/organizations?page=1&page_size=2", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	total, _ := data["total"].(float64)
	assert.GreaterOrEqual(t, int(total), 3, "total should reflect at least 3 orgs")
}

func TestOrganizationList_FilterByType(t *testing.T) {
	ctx := setupChannelTest(t)
	ctx.createOrg(t, fmt.Sprintf("org-ft-cust-%d", ts()), "customer", nil)
	ctx.createOrg(t, fmt.Sprintf("org-ft-agent-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/organizations?type=customer", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	items, _ := data["items"].([]interface{})
	for _, item := range items {
		org, _ := item.(map[string]interface{})
		assert.Equal(t, "customer", org["type"])
	}
}

func TestOrganizationGetByID_Found(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("org-get-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	assert.Equal(t, float64(orgID), data["id"])
}

func TestOrganizationGetByID_NotFound(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/organizations/999999999", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "should return error for non-existent org")
}

func TestOrganizationUpdate_NameOnly(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("org-upd-%d", ts()), "agent", nil)
	newName := fmt.Sprintf("org-updated-%d", ts())

	resp, status := doJSONWithRetry(t, ctx.Client, "PUT",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID),
		map[string]interface{}{"name": newName}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "update should succeed: %s", resp.Message)

	// Verify the name changed
	resp2, _ := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token, 5)
	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp2.Data, &data))
	assert.Equal(t, newName, data["name"])
}

func TestOrganizationMove_ToNewParent(t *testing.T) {
	ctx := setupChannelTest(t)
	parentID := ctx.createOrg(t, fmt.Sprintf("org-parent-%d", ts()), "manufacturer", nil)
	childID := ctx.createOrg(t, fmt.Sprintf("org-child-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/organizations/%d/move", ctx.BaseURL, childID),
		map[string]interface{}{"parent_id": parentID}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("move org: code=%d msg=%s", resp.Code, resp.Message)
	assert.Equal(t, 0, resp.Code, "move should succeed")

	// Verify parent changed
	resp2, _ := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, childID), nil, ctx.Token, 5)
	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp2.Data, &data))
	assert.Equal(t, float64(parentID), data["parent_id"])
}

func TestOrganizationMove_CircularReference(t *testing.T) {
	ctx := setupChannelTest(t)
	parentID := ctx.createOrg(t, fmt.Sprintf("org-circ-p-%d", ts()), "manufacturer", nil)
	childID := ctx.createOrg(t, fmt.Sprintf("org-circ-c-%d", ts()), "agent", &parentID)

	// Try to move parent under its own child 鈫?circular
	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/organizations/%d/move", ctx.BaseURL, parentID),
		map[string]interface{}{"parent_id": childID}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "circular reference should be rejected")
	t.Logf("circular ref: code=%d msg=%s", resp.Code, resp.Message)
}

func TestOrganizationToggleStatus_ActiveDisabled(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("org-toggle-%d", ts()), "agent", nil)

	// Disable
	resp, status := doJSONWithRetry(t, ctx.Client, "PATCH",
		fmt.Sprintf("%s/api/v1/organizations/%d/status", ctx.BaseURL, orgID),
		map[string]interface{}{"status": "disabled"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "disable should succeed: %s", resp.Message)

	// Verify disabled
	resp2, _ := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token, 5)
	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp2.Data, &data))
	assert.Equal(t, "disabled", data["status"])

	// Re-enable
	resp3, status3 := doJSONWithRetry(t, ctx.Client, "PATCH",
		fmt.Sprintf("%s/api/v1/organizations/%d/status", ctx.BaseURL, orgID),
		map[string]interface{}{"status": "active"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status3)
	assert.Equal(t, 0, resp3.Code, "re-enable should succeed")
}

func TestOrganizationToggleStatus_InvalidValue(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("org-inv-status-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "PATCH",
		fmt.Sprintf("%s/api/v1/organizations/%d/status", ctx.BaseURL, orgID),
		map[string]interface{}{"status": "unknown"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "invalid status should be rejected")
}

func TestOrganizationDelete_SoftDelete(t *testing.T) {
	ctx := setupChannelTest(t)
	orgID := ctx.createOrg(t, fmt.Sprintf("org-del-%d", ts()), "agent", nil)

	resp, status := doJSONWithRetry(t, ctx.Client, "DELETE",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "delete should succeed: %s", resp.Message)

	// Should not be found anymore
	resp2, _ := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, orgID), nil, ctx.Token, 5)
	assert.NotEqual(t, 0, resp2.Code, "deleted org should not be found")
}

func TestOrganizationDelete_WithChildren_ShouldFail(t *testing.T) {
	ctx := setupChannelTest(t)
	parentID := ctx.createOrg(t, fmt.Sprintf("org-del-p-%d", ts()), "manufacturer", nil)
	ctx.createOrg(t, fmt.Sprintf("org-del-c-%d", ts()), "agent", &parentID)

	resp, status := doJSONWithRetry(t, ctx.Client, "DELETE",
		fmt.Sprintf("%s/api/v1/organizations/%d", ctx.BaseURL, parentID), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "delete org with children should fail")
	t.Logf("delete with children: code=%d msg=%s", resp.Code, resp.Message)
}

func TestOrganizationGetTree_FullHierarchy(t *testing.T) {
	ctx := setupChannelTest(t)
	rootID := ctx.createOrg(t, fmt.Sprintf("org-tree-root-%d", ts()), "manufacturer", nil)
	childID := ctx.createOrg(t, fmt.Sprintf("org-tree-child-%d", ts()), "agent", &rootID)
	ctx.createOrg(t, fmt.Sprintf("org-tree-grandchild-%d", ts()), "distributor", &childID)

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		fmt.Sprintf("%s/api/v1/organizations/%d/tree", ctx.BaseURL, rootID), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	totalNodes, _ := data["total_nodes"].(float64)
	assert.GreaterOrEqual(t, int(totalNodes), 3, "tree should have at least 3 nodes")

	subtree, _ := data["subtree"].([]interface{})
	assert.GreaterOrEqual(t, len(subtree), 3, "subtree should contain all descendants")
}

func TestOrganizationGetTree_NotFound(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/organizations/999999999/tree", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code)
}

func TestOrganizationCreate_WithParent(t *testing.T) {
	ctx := setupChannelTest(t)
	parentID := ctx.createOrg(t, fmt.Sprintf("org-wp-parent-%d", ts()), "manufacturer", nil)
	childName := fmt.Sprintf("org-wp-child-%d", ts())

	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/organizations",
		map[string]interface{}{"name": childName, "type": "agent", "parent_id": parentID},
		ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "create with parent should succeed: %s", resp.Message)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	assert.Equal(t, float64(parentID), data["parent_id"])
}

func TestOrganizationCreate_ParentNotFound(t *testing.T) {
	ctx := setupChannelTest(t)
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/organizations",
		map[string]interface{}{"name": "orphan", "type": "agent", "parent_id": 999999999},
		ctx.Token)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "create with non-existent parent should fail")
}

// ts returns a short unique timestamp suffix for test naming.
func ts() int64 {
	return time.Now().UnixNano() % 100000000
}

