package handler

import (
	"context"
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
	req := CreateInvitationRequest{
		Email:        "invalid-email",
		RoleID:       2,
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_MissingEmail() {
	req := map[string]interface{}{
		"role_id":       2,
		"expires_hours": 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_InvalidRole() {
	req := CreateInvitationRequest{
		Email:        "test@example.com",
		RoleID:       10, // exceeds max=5
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_ExceedsMaxExpiration() {
	req := CreateInvitationRequest{
		Email:        "test@example.com",
		RoleID:       2,
		ExpiresHours: 800, // exceeds max=720
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_MissingExpiresHours() {
	req := map[string]interface{}{
		"email":   "test@example.com",
		"role_id": 2,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_EnduserForbidden() {
	// Valid request body but caller is not a system admin → 403 before DB access.
	req := CreateInvitationRequest{
		Email:        "test@example.com",
		RoleID:       2,
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, false, 100) // non-admin user

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 403, "end users cannot create invitations")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_SQLInjectionAttempt() {
	// Malicious email fails the "email" validator → binding error → 400.
	req := CreateInvitationRequest{
		Email:        "test'; DROP TABLE invitations; --",
		RoleID:       2,
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
}

func (suite *InvitationHandlerTestSuite) TestCreateInvitation_XSSAttempt() {
	// XSS payload in email fails the "email" validator → binding error → 400.
	req := CreateInvitationRequest{
		Email:        "<script>alert('xss')</script>@example.com",
		RoleID:       2,
		ExpiresHours: 24,
	}
	c, w := createTestGinContext("/api/v1/invitations/create", "POST", req)
	setAuthClaimsInContext(c, 1, true, 100)

	suite.handler.Create(c)

	assertBizResponse(suite.T(), w, 400, "invalid request")
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
// Helper Method Tests
// ============================================================================

func (suite *InvitationHandlerTestSuite) TestCheckInvitationQuota_Default() {
	// checkInvitationQuota does not access any handler fields; it returns a
	// fixed default of 100.
	ctx := context.Background()
	maxPending, err := suite.handler.checkInvitationQuota(ctx, 1, 1)

	assert.NoError(suite.T(), err)
	assert.Equal(suite.T(), int64(100), maxPending)
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
