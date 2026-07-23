//go:build integration

package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// channelTestContext holds shared state for channel platform test suites.
type channelTestContext struct {
	BaseURL string
	Client  *http.Client
	Token   string // admin-level user token
	UserID  int64

	// Secondary user (different tenant / role)
	Token2  string
	UserID2 int64
}

// setupChannelTest creates two registered+logged-in users and returns a context.
// After registration the users' role is promoted from end-user (5) to
// super-admin (0) so that they can create organizations in tests.
func setupChannelTest(t *testing.T) *channelTestContext {
	t.Helper()
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 15 * time.Second}
	pw := "ChTest@2026"

	// User A — primary admin
	phoneA := fmt.Sprintf("150%08d", time.Now().UnixNano()%100000000)
	registerUser(t, cfg.APIBaseURL, phoneA, pw)
	// User B — secondary user (for cross-tenant / isolation tests)
	phoneB := fmt.Sprintf("151%08d", time.Now().UnixNano()%100000000)
	registerUser(t, cfg.APIBaseURL, phoneB, pw)

	// Promote both users from end-user (role=5) to super-admin (role=0)
	// so that OrganizationHandler.Create does not reject them with 403.
	pool := ConnectDB(t, cfg)
	defer pool.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	for _, phone := range []string{phoneA, phoneB} {
		_, err := pool.Exec(ctx, "UPDATE users SET role = 0 WHERE phone = $1", phone)
		require.NoError(t, err, "promote user role for phone %s", phone)
	}

	tokenA := loginUser(t, cfg.APIBaseURL, phoneA, pw)
	tokenB := loginUser(t, cfg.APIBaseURL, phoneB, pw)

	return &channelTestContext{
		BaseURL: cfg.APIBaseURL,
		Client:  client,
		Token:   tokenA,
		Token2:  tokenB,
	}
}

// createOrg creates an organization and returns its ID.
func (c *channelTestContext) createOrg(t *testing.T, name, orgType string, parentID *int64) int64 {
	t.Helper()
	body := map[string]interface{}{
		"name": name,
		"type": orgType,
	}
	if parentID != nil {
		body["parent_id"] = *parentID
	}
	resp, status := doJSON(t, c.Client, "POST", c.BaseURL+"/api/v1/organizations", body, c.Token)
	require.Equal(t, http.StatusOK, status, "create org HTTP status: %s", resp.Message)
	require.Equal(t, 0, resp.Code, "create org business code: %s", resp.Message)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	id, ok := data["id"].(float64)
	require.True(t, ok, "org id should be numeric")
	return int64(id)
}

// createInvitation creates an invitation and returns the response data.
func (c *channelTestContext) createInvitation(t *testing.T, email string, roleID int, orgID *int64, expiresHours int) map[string]interface{} {
	t.Helper()
	body := map[string]interface{}{
		"email":         email,
		"role_id":       roleID,
		"expires_hours": expiresHours,
	}
	if orgID != nil {
		body["organization_id"] = *orgID
	}
	resp, status := doJSON(t, c.Client, "POST", c.BaseURL+"/api/v1/invitations/create", body, c.Token)
	require.Equal(t, http.StatusOK, status, "create invitation HTTP: %s", resp.Message)
	require.Equal(t, 0, resp.Code, "create invitation biz: %s", resp.Message)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	return data
}

// generateClaimCode generates a device claim code and returns the response data.
func (c *channelTestContext) generateClaimCode(t *testing.T, sn string, expiresHours int) map[string]interface{} {
	t.Helper()
	body := map[string]interface{}{
		"sn":            sn,
		"expires_hours": expiresHours,
	}
	resp, status := doJSON(t, c.Client, "POST", c.BaseURL+"/api/v1/devices/claim-code/generate", body, c.Token)
	require.Equal(t, http.StatusOK, status, "generate claim code HTTP: %s", resp.Message)
	require.Equal(t, 0, resp.Code, "generate claim code biz: %s", resp.Message)

	var data map[string]interface{}
	require.NoError(t, json.Unmarshal(resp.Data, &data))
	return data
}

// addMember adds a user to an organization and returns the membership data.
func (c *channelTestContext) addMember(t *testing.T, userID, orgID int64, roleIDs []int) map[string]interface{} {
	t.Helper()
	body := map[string]interface{}{
		"user_id":         userID,
		"organization_id": orgID,
	}
	if roleIDs != nil {
		body["role_ids"] = roleIDs
	}
	resp, status := doJSON(t, c.Client, "POST", c.BaseURL+"/api/v1/members/add", body, c.Token)
	require.Equal(t, http.StatusOK, status, "add member HTTP: %s", resp.Message)

	var data map[string]interface{}
	if resp.Data != nil {
		_ = json.Unmarshal(resp.Data, &data)
	}
	return data
}

// uniqueSN generates a unique device serial number for testing.
func uniqueSN(prefix string) string {
	return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
}

// uniqueEmail generates a unique email address for testing.
func uniqueEmail(prefix string) string {
	return fmt.Sprintf("%s_%d@test.com", prefix, time.Now().UnixNano())
}
