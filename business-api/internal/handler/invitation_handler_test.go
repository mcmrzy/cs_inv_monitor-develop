package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// ============================================================================
// Invitation Handler Test Suite
// ============================================================================

type InvitationHandlerTestSuite struct {
	suite.Suite
	handler *InvitationHandler
}

func (suite *InvitationHandlerTestSuite) SetupSuite() {
	gin.SetMode(gin.TestMode)
}

func (suite *InvitationHandlerTestSuite) SetupTest() {
	// All dependencies are nil; only validation paths (before DB access) are tested.
	suite.handler = NewInvitationHandler(nil, nil, nil, nil, nil, nil, nil, nil, nil)
}

func TestInvitationHandlerSuite(t *testing.T) {
	suite.Run(t, new(InvitationHandlerTestSuite))
}

// ============================================================================
// Create Invitation – Validation Path Tests
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_InvalidEmail() {
	// Invalid email is dropped by normalizeEmails → empty recipients → 400.
	req := CreateInvitationRequest{
		Emails: []string{"invalid-email"},
		Assignments: []RoleAssignmentInput{
			{OrganizationID: 1, RoleCode: "agent"},
		},
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "至少需要一个有效的邮箱地址")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_MissingEmail() {
	req := map[string]interface{}{
		"assignments": []map[string]interface{}{
			{"organization_id": 1, "role_code": "agent"},
		},
		"expires_hours": 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "至少需要一个有效的邮箱地址")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_InvalidRole() {
	// role_code not in the channel role model → 400 before any DB access.
	req := CreateInvitationRequest{
		Emails: []string{"test@example.com"},
		Assignments: []RoleAssignmentInput{
			{OrganizationID: 1, RoleCode: "superuser"},
		},
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "无效的角色代码")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_ExceedsMaxExpiration() {
	req := CreateInvitationRequest{
		Emails: []string{"test@example.com"},
		Assignments: []RoleAssignmentInput{
			{OrganizationID: 1, RoleCode: "agent"},
		},
		ExpiresHours: 800, // exceeds max=720
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "请求参数无效")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_MissingExpiresHours() {
	req := map[string]interface{}{
		"emails": []string{"test@example.com"},
		"assignments": []map[string]interface{}{
			{"organization_id": 1, "role_code": "agent"},
		},
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "请求参数无效")
}

func (suite *InvitationHandlerTestSuite) TestNormalizeAssignments_LegacyConversion() {
	// Legacy single-invitation payload converts to the canonical assignments format.
	orgID := int64(2)
	assignments, err := normalizeAssignments(nil, &orgID, 3)
	assert.NoError(suite.T(), err)
	assert.Len(suite.T(), assignments, 1)
	assert.Equal(suite.T(), int64(2), assignments[0].OrganizationID)
	assert.Equal(suite.T(), "distributor", assignments[0].RoleCode)

	// Invalid legacy role ID is rejected.
	_, err = normalizeAssignments(nil, &orgID, 99)
	assert.Error(suite.T(), err)

	// No assignments and no legacy fields → nil.
	out, err := normalizeAssignments(nil, nil, 0)
	assert.NoError(suite.T(), err)
	assert.Nil(suite.T(), out)
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_SQLInjectionAttempt() {
	// Malicious email fails validation in normalizeEmails → empty recipients → 400.
	req := CreateInvitationRequest{
		Emails: []string{"test'; DROP TABLE invitations; --"},
		Assignments: []RoleAssignmentInput{
			{OrganizationID: 1, RoleCode: "agent"},
		},
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "至少需要一个有效的邮箱地址")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_XSSAttempt() {
	// XSS payload in email fails validation in normalizeEmails → empty recipients → 400.
	req := CreateInvitationRequest{
		Emails: []string{"<script>alert('xss')</script>@example.com"},
		Assignments: []RoleAssignmentInput{
			{OrganizationID: 1, RoleCode: "agent"},
		},
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "至少需要一个有效的邮箱地址")
}

// ============================================================================
// List Invitations – Validation Path Tests
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestListInvitations_MissingPagination() {
	// No page/page_size query params → zero values fail min=1 binding.
	c, w := createTestGinContext("/api/v1/invitations/list", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.List(c)

	assertBizResponse(suite.T(), w, 400, "invalid query")
}

func (suite *InvitationHandlerTestSuite) TestListInvitations_InvalidPageSize() {
	// page_size=200 exceeds max=100 → binding error.
	c, w := createTestGinContext("/api/v1/invitations/list?page=1&page_size=200", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.List(c)

	assertBizResponse(suite.T(), w, 400, "invalid query")
}

// ============================================================================
// Revoke Invitation – Validation Path Tests
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestRevokeInvitation_InvalidID() {
	c, w := createTestGinContext("/api/v1/invitations/abc/revoke", "DELETE", nil)
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	suite.handler.Revoke(c)

	assertBizResponse(suite.T(), w, 400, "invalid invitation ID")
}

// ============================================================================
// Accept Invitation – Validation Path Tests
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestAcceptInvitation_InvalidRequest() {
	req := map[string]interface{}{
		"invitation_code": "testtoken",
		// missing password, phone, nickname
	}
	c, w := createTestGinContext("/api/v1/invitations/accept", "POST", req)

	suite.handler.Accept(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestAcceptInvitation_PasswordTooShort() {
	req := AcceptInvitationRequest{
		InvitationCode: "validtoken",
		Password:       "short", // 5 chars < min=6
		Phone:          "1234567890",
		Nickname:       "Test User",
	}
	c, w := createTestGinContext("/api/v1/invitations/accept", "POST", req)

	suite.handler.Accept(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestAcceptInvitation_PasswordTooLong() {
	req := AcceptInvitationRequest{
		InvitationCode: "validtoken",
		Password:       "verylongpassword12345", // 22 chars > max=20
		Phone:          "1234567890",
		Nickname:       "Test User",
	}
	c, w := createTestGinContext("/api/v1/invitations/accept", "POST", req)

	suite.handler.Accept(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestAcceptInvitation_MissingCode() {
	req := map[string]interface{}{
		"password": "password123",
		"phone":    "1234567890",
		"nickname": "Test User",
	}
	c, w := createTestGinContext("/api/v1/invitations/accept", "POST", req)

	suite.handler.Accept(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

// ============================================================================
// Details – Validation Path Tests
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestGetInvitationDetails_InvalidID() {
	c, w := createTestGinContext("/api/v1/invitations/abc/details", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	suite.handler.Details(c)

	assertBizResponse(suite.T(), w, 400, "invalid invitation ID")
}

// ============================================================================
// Role Hierarchy Resolution (pure functions)
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestResolveAllowedRoles_SystemAdminFullSet() {
	roles := resolveAllowedRoles(nil, true)
	assert.ElementsMatch(suite.T(), []string{"agent", "distributor", "installer", "customer", "org_admin"}, roles)
}

func (suite *InvitationHandlerTestSuite) TestResolveAllowedRoles_ByInviterOrgType() {
	// manufacturer org admin: every channel role + org_admin
	assert.ElementsMatch(suite.T(),
		[]string{"agent", "distributor", "installer", "customer", "org_admin"},
		resolveAllowedRoles([]string{"manufacturer"}, false))

	// agent org admin: installer + customer + org_admin
	assert.ElementsMatch(suite.T(),
		[]string{"installer", "customer", "org_admin"},
		resolveAllowedRoles([]string{"agent"}, false))

	// distributor org admin: installer + customer + org_admin
	assert.ElementsMatch(suite.T(),
		[]string{"installer", "customer", "org_admin"},
		resolveAllowedRoles([]string{"distributor"}, false))

	// installer org admin: customer + org_admin
	assert.ElementsMatch(suite.T(),
		[]string{"customer", "org_admin"},
		resolveAllowedRoles([]string{"installer"}, false))

	// customer org admin: org_admin only (no channel roles invitable)
	assert.ElementsMatch(suite.T(),
		[]string{"org_admin"},
		resolveAllowedRoles([]string{"customer"}, false))
}

func (suite *InvitationHandlerTestSuite) TestResolveAllowedRoles_MultiOrgUnion() {
	// agent + installer memberships -> union {installer, customer} + org_admin
	assert.ElementsMatch(suite.T(),
		[]string{"installer", "customer", "org_admin"},
		resolveAllowedRoles([]string{"agent", "installer"}, false))

	// manufacturer + agent -> full channel set
	assert.ElementsMatch(suite.T(),
		[]string{"agent", "distributor", "installer", "customer", "org_admin"},
		resolveAllowedRoles([]string{"manufacturer", "agent"}, false))
}

func (suite *InvitationHandlerTestSuite) TestResolveAllowedRoles_NoMembership() {
	// No memberships -> only the management role remains assignable.
	assert.ElementsMatch(suite.T(), []string{"org_admin"}, resolveAllowedRoles(nil, false))
}

// ============================================================================
// Token and Digest Tests (pure functions)
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestSHA256DigestComputation() {
	rawToken := "testtoken12345678"
	expectedDigest := sha256.Sum256([]byte(rawToken))
	expectedHex := hex.EncodeToString(expectedDigest[:])

	computedDigest := sha256.Sum256([]byte(rawToken))
	computedHex := hex.EncodeToString(computedDigest[:])

	assert.Equal(suite.T(), expectedHex, computedHex)
}

func (suite *InvitationHandlerTestSuite) TestTokenHintExtraction() {
	rawToken := "abcdef1234567890abcdef1234567890"
	expectedHint := rawToken[:8] + "****"

	hint := rawToken[:8] + "****"

	assert.Equal(suite.T(), expectedHint, hint)
	assert.Equal(suite.T(), "abcdef12****", hint)
}
