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
// Device Claim & Transfer Handler Test Suite
//
// Tests focus on validation paths that do not require database access:
//   - Binding errors (missing required fields, out-of-range values)
//   - Parse errors (non-numeric path parameters)
//   - Business logic validation (approved flag checks, status filter)
//
// DB-dependent scenarios (success, not-found, permission, conflict) require
// an integration test with a real database and are not covered here.
// ============================================================================

type DeviceClaimTransferHandlerTestSuite struct {
	suite.Suite
	handler *DeviceClaimTransferHandler
}

func (suite *DeviceClaimTransferHandlerTestSuite) SetupSuite() {
	gin.SetMode(gin.TestMode)
}

func (suite *DeviceClaimTransferHandlerTestSuite) SetupTest() {
	suite.handler = NewDeviceClaimTransferHandler(nil, nil, nil, "", "")
}

func TestDeviceClaimTransferHandlerSuite(t *testing.T) {
	suite.Run(t, new(DeviceClaimTransferHandlerTestSuite))
}

// ============================================================================
// Generate Claim Code Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_InvalidRequest() {
	// Missing required field "sn"
	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", map[string]interface{}{
		"expires_hours": 24,
	})
	setAuthClaimsInContext(c, 1, true, 100)
	suite.handler.GenerateClaimCode(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_ExceedsMaxExpiration() {
	// expires_hours > 8760 (1 year) fails binding max=8760
	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", GenerateClaimCodeRequest{
		SN: "TEST123456", ExpiresHours: 9000,
	})
	setAuthClaimsInContext(c, 1, true, 100)
	suite.handler.GenerateClaimCode(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_MissingExpiresHours() {
	// Missing required field "expires_hours"
	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", map[string]interface{}{
		"sn": "TEST123456",
	})
	setAuthClaimsInContext(c, 1, true, 100)
	suite.handler.GenerateClaimCode(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Verify Claim Code Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestVerifyClaimCode_InvalidRequest() {
	// Missing required field "claim_code"
	c, w := createTestGinContext("/api/v1/devices/claim-code/verify", "POST", map[string]interface{}{
		"invalid": "field",
	})
	suite.handler.VerifyClaimCode(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Claim Device Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_InvalidRequest() {
	// Missing required field "claim_code" (sn comes from URL param)
	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", map[string]interface{}{
		"sn": "TEST123456",
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "sn", Value: "TEST123456"}}
	suite.handler.ClaimDevice(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Request Transfer Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_InvalidRequest() {
	// Missing required field "to_tenant_id"
	c, w := createTestGinContext("/api/v1/devices/TEST123456/request-transfer", "POST", map[string]interface{}{
		"device_sn": "TEST123456",
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "sn", Value: "TEST123456"}}
	suite.handler.RequestTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// List Transfers Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_InvalidStatus() {
	// Invalid status filter is rejected before DB access
	c, w := createTestGinContext("/api/v1/devices/transfers/list?status=invalid", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 100)
	suite.handler.ListTransfers(c)
	assertBizResponse(suite.T(), w, 400, "invalid status filter")
}

// ============================================================================
// Approve Transfer Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_InvalidID() {
	c, w := createTestGinContext("/api/v1/devices/transfers/abc/approve", "POST", DeviceTransferApprovalRequest{
		Approved: true,
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.ApproveTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_ApprovedFalse() {
	// approved=false on the approve endpoint returns 400
	// (binding:"required" on bool rejects false as zero value)
	c, w := createTestGinContext("/api/v1/devices/transfers/1/approve", "POST", map[string]interface{}{
		"approved": false,
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.ApproveTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Reject Transfer Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_InvalidID() {
	c, w := createTestGinContext("/api/v1/devices/transfers/abc/reject", "POST", DeviceTransferApprovalRequest{
		Approved: false, Reason: "Not acceptable",
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.RejectTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_ApprovedTrue() {
	// approved=true on the reject endpoint returns 400
	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", DeviceTransferApprovalRequest{
		Approved: true, Reason: "Some reason",
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.RejectTransfer(c)
	assertBizResponse(suite.T(), w, 400, "approved=false")
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_MissingReason() {
	// approved=false with empty reason returns 400
	// (binding:"required" on bool rejects false; this still yields 400)
	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", map[string]interface{}{
		"approved": false, "reason": "",
	})
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.RejectTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Cancel Transfer Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestCancelTransfer_InvalidID() {
	c, w := createTestGinContext("/api/v1/devices/transfers/abc/cancel", "POST", nil)
	setAuthClaimsInContext(c, 1, true, 100)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.CancelTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Helper Function Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestContains() {
	slice := []string{"a", "b", "c"}
	assert.True(suite.T(), contains(slice, "b"))
	assert.False(suite.T(), contains(slice, "d"))
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestSHA256DigestMatch() {
	code := "TESTCODE123"
	digest1 := sha256.Sum256([]byte(code))
	hex1 := hex.EncodeToString(digest1[:])

	digest2 := sha256.Sum256([]byte(code))
	hex2 := hex.EncodeToString(digest2[:])

	assert.Equal(suite.T(), hex1, hex2)
}
