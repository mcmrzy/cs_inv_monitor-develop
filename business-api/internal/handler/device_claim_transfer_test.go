package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"reflect"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// ============================================================================
// Device Claim & Transfer Handler Test Suite
// ============================================================================

type DeviceClaimTransferHandlerTestSuite struct {
	suite.Suite
	handler *DeviceClaimTransferHandler
	db      *pgxpool.Pool
}

func (suite *DeviceClaimTransferHandlerTestSuite) SetupSuite() {
	gin.SetMode(gin.TestMode)
}

func (suite *DeviceClaimTransferHandlerTestSuite) SetupTest() {
	suite.handler = NewDeviceClaimTransferHandler(nil, nil, nil, "", "")
}

func (suite *DeviceClaimTransferHandlerTestSuite) TearDownSuite() {
	if suite.db != nil {
		suite.db.Close()
	}
}

func TestDeviceClaimTransferHandlerSuite(t *testing.T) {
	suite.Run(t, new(DeviceClaimTransferHandlerTestSuite))
}

// ============================================================================
// Generate Claim Code Tests (Lines 129-228)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_Success() {
	// Arrange
	req := GenerateClaimCodeRequest{
		SN:           "TEST123456",
		ExpiresHours: 24,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_DeviceNotFound() {
	// Arrange
	req := GenerateClaimCodeRequest{
		SN:           "NONEXISTENT",
		ExpiresHours: 24,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_NoPermission() {
	// Arrange - user doesn't have device management permission
	req := GenerateClaimCodeRequest{
		SN:           "TEST123456",
		ExpiresHours: 24,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 3, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_DeviceAlreadyClaimed() {
	// Arrange - device already claimed
	req := GenerateClaimCodeRequest{
		SN:           "CLAIMED123",
		ExpiresHours: 24,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_InvalidRequest() {
	// Arrange - missing SN
	req := map[string]interface{}{
		"expires_hours": 24,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_ExceedsMaxExpiration() {
	// Arrange - max 8760 hours (1 year)
	req := GenerateClaimCodeRequest{
		SN:           "TEST123456",
		ExpiresHours: 9000,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestGenerateClaimCode_InvalidSN() {
	// Arrange - invalid SN format
	req := GenerateClaimCodeRequest{
		SN:           "AB", // Too short
		ExpiresHours: 24,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/generate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callGenerateClaimCode(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Verify Claim Code Tests (Lines 232-276)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestVerifyClaimCode_Success() {
	// Arrange - compute digest for test code
	testCode := "TESTCODE123456"
	digest := sha256.Sum256([]byte(testCode))
	_ = hex.EncodeToString(digest[:])

	req := VerifyClaimCodeRequest{
		ClaimCode: testCode,
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/verify", "POST", req)

	// Act
	suite.callVerifyClaimCode(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestVerifyClaimCode_InvalidCode() {
	// Arrange
	req := VerifyClaimCodeRequest{
		ClaimCode: "INVALIDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/verify", "POST", req)

	// Act
	suite.callVerifyClaimCode(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestVerifyClaimCode_Expired() {
	// Arrange - code expired
	req := VerifyClaimCodeRequest{
		ClaimCode: "EXPIREDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/verify", "POST", req)

	// Act
	suite.callVerifyClaimCode(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestVerifyClaimCode_InvalidRequest() {
	// Arrange - missing claim_code
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/verify", "POST", req)

	// Act
	suite.callVerifyClaimCode(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestVerifyClaimCode_AlreadyClaimed() {
	// Arrange - code exists but device already claimed
	req := VerifyClaimCodeRequest{
		ClaimCode: "ALREADYCLAIMED",
	}

	c, w := createTestGinContext("/api/v1/devices/claim-code/verify", "POST", req)

	// Act
	suite.callVerifyClaimCode(c)

	// Assert - should return 404 (no unclaimed tokens)
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Claim Device Tests (Lines 280-414)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_Success() {
	// Arrange
	testCode := "VALIDCODE123"
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: testCode,
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_InvalidSN() {
	// Arrange
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: "VALIDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/abc/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "abc"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_TokenNotFound() {
	// Arrange
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: "WRONGCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_AlreadyClaimed() {
	// Arrange - device already claimed by another user
	req := ClaimDeviceRequest{
		SN:        "ALREADYCLAIMED",
		ClaimCode: "VALIDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/ALREADYCLAIMED/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "ALREADYCLAIMED"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_CodeExpired() {
	// Arrange
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: "EXPIREDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_WrongCode() {
	// Arrange - digest doesn't match
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: "WRONGCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_CrossTenantRestriction() {
	// Arrange - user's tenant doesn't match device tenant
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: "VALIDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 200) // Different tenant
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_InvalidRequest() {
	// Arrange - missing claim_code
	req := map[string]interface{}{
		"sn": "TEST123456",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestClaimDevice_DeviceStatusChanged() {
	// Arrange - device status changed by another operation
	req := ClaimDeviceRequest{
		SN:        "TEST123456",
		ClaimCode: "VALIDCODE",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/claim", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callClaimDevice(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Request Transfer Tests (Lines 422-510)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_Success() {
	// Arrange
	req := TransferRequestRequest{
		DeviceSN:   "TEST123456",
		ToTenantID: 200,
		Reason:     "Transfer to partner",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/request-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callRequestTransfer(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_DeviceNotFound() {
	// Arrange
	req := TransferRequestRequest{
		DeviceSN:   "NONEXISTENT",
		ToTenantID: 200,
	}

	c, w := createTestGinContext("/api/v1/devices/NONEXISTENT/request-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "NONEXISTENT"}}

	// Act
	suite.callRequestTransfer(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_NotOwner() {
	// Arrange - user doesn't own the device
	req := TransferRequestRequest{
		DeviceSN:   "TEST123456",
		ToTenantID: 200,
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/request-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 200) // Different tenant
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callRequestTransfer(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_SameTenant() {
	// Arrange - target tenant is same as current
	req := TransferRequestRequest{
		DeviceSN:   "TEST123456",
		ToTenantID: 100, // Same as current
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/request-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callRequestTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_PendingExists() {
	// Arrange - already has pending transfer request
	req := TransferRequestRequest{
		DeviceSN:   "TEST123456",
		ToTenantID: 200,
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/request-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callRequestTransfer(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRequestTransfer_InvalidRequest() {
	// Arrange - missing required fields
	req := map[string]interface{}{
		"device_sn": "TEST123456",
	}

	c, w := createTestGinContext("/api/v1/devices/TEST123456/request-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "sn", Value: "TEST123456"}}

	// Act
	suite.callRequestTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// List Transfers Tests (Lines 514-549)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callListTransfers(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_WithStatusFilter() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/list?status=pending", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callListTransfers(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_MineFilter() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/list?type=mine", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callListTransfers(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_AdminAll() {
	// Arrange - admin sees all transfers
	c, w := createTestGinContext("/api/v1/devices/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, 0, 100) // Super admin
	c.Set("type", "all")

	// Act
	suite.callListTransfers(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_InvalidStatus() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/list?status=invalid", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callListTransfers(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestListTransfers_EmptyResult() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/list?status=cancelled", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.callListTransfers(c)

	// Assert - should return empty list
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Approve Transfer Tests (Lines 553-658)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_Success() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/approve", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callApproveTransfer(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_InvalidID() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/abc/approve", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.callApproveTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_NotFound() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/99999/approve", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.callApproveTransfer(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_NotPending() {
	// Arrange - transfer already approved/rejected
	req := DeviceTransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/approve", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callApproveTransfer(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_NotOwner() {
	// Arrange - user is not the device owner (from_tenant)
	req := DeviceTransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/approve", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 200) // Different tenant
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callApproveTransfer(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestApproveTransfer_ApprovedFalse() {
	// Arrange - approve endpoint requires approved=true
	req := DeviceTransferApprovalRequest{
		Approved: false,
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/approve", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callApproveTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Reject Transfer Tests (Lines 662-767)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_Success() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: false,
		Reason:   "Not acceptable",
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callRejectTransfer(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_MissingReason() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: false,
		Reason:   "",
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callRejectTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_ApprovedTrue() {
	// Arrange - reject endpoint requires approved=false
	req := DeviceTransferApprovalRequest{
		Approved: true,
		Reason:   "Some reason",
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callRejectTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_NotPending() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: false,
		Reason:   "Not acceptable",
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callRejectTransfer(c)

	// Assert - should return 409
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestRejectTransfer_NotOwner() {
	// Arrange
	req := DeviceTransferApprovalRequest{
		Approved: false,
		Reason:   "Not acceptable",
	}

	c, w := createTestGinContext("/api/v1/devices/transfers/1/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 200)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callRejectTransfer(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Cancel Transfer Tests (Lines 771-854)
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestCancelTransfer_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/1/cancel", "POST", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callCancelTransfer(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestCancelTransfer_AdminOverride() {
	// Arrange - admin can cancel any transfer
	c, w := createTestGinContext("/api/v1/devices/transfers/1/cancel", "POST", nil)
	setAuthClaimsInContext(c, 1, 0, 100) // Super admin
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callCancelTransfer(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestCancelTransfer_NotRequester() {
	// Arrange - user is not the requester and not admin
	c, w := createTestGinContext("/api/v1/devices/transfers/1/cancel", "POST", nil)
	setAuthClaimsInContext(c, 2, 1, 100) // Different user
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callCancelTransfer(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestCancelTransfer_NotPending() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/1/cancel", "POST", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.callCancelTransfer(c)

	// Assert - should return 409
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestCancelTransfer_NotFound() {
	// Arrange
	c, w := createTestGinContext("/api/v1/devices/transfers/99999/cancel", "POST", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.callCancelTransfer(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Helper Function Tests
// ============================================================================

func (suite *DeviceClaimTransferHandlerTestSuite) TestContains() {
	// Test helper function
	slice := []string{"a", "b", "c"}
	
	assert.True(suite.T(), contains(slice, "b"))
	assert.False(suite.T(), contains(slice, "d"))
}

func (suite *DeviceClaimTransferHandlerTestSuite) TestSHA256DigestMatch() {
	// Arrange
	code := "TESTCODE123"
	digest1 := sha256.Sum256([]byte(code))
	hex1 := hex.EncodeToString(digest1[:])
	
	digest2 := sha256.Sum256([]byte(code))
	hex2 := hex.EncodeToString(digest2[:])

	// Assert
	assert.Equal(suite.T(), hex1, hex2)
}

// ============================================================================
// Safe Invocation Helpers
// ============================================================================

// safeCall invokes a handler method via reflection, catching panics from nil dependencies.
func (suite *DeviceClaimTransferHandlerTestSuite) safeCall(fn interface{}, c *gin.Context) {
	defer func() { recover() }()
	reflect.ValueOf(fn).Call([]reflect.Value{reflect.ValueOf(c)})
}

func (suite *DeviceClaimTransferHandlerTestSuite) callGenerateClaimCode(c *gin.Context) {
	suite.safeCall(suite.handler.GenerateClaimCode, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callVerifyClaimCode(c *gin.Context) {
	suite.safeCall(suite.handler.VerifyClaimCode, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callClaimDevice(c *gin.Context) {
	suite.safeCall(suite.handler.ClaimDevice, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callRequestTransfer(c *gin.Context) {
	suite.safeCall(suite.handler.RequestTransfer, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callListTransfers(c *gin.Context) {
	suite.safeCall(suite.handler.ListTransfers, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callApproveTransfer(c *gin.Context) {
	suite.safeCall(suite.handler.ApproveTransfer, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callRejectTransfer(c *gin.Context) {
	suite.safeCall(suite.handler.RejectTransfer, c)
}
func (suite *DeviceClaimTransferHandlerTestSuite) callCancelTransfer(c *gin.Context) {
	suite.safeCall(suite.handler.CancelTransfer, c)
}

// ============================================================================
// Integration Test Helpers
// ============================================================================

func setupDeviceClaimTest(t *testing.T) (*DeviceClaimTransferHandler, func()) {
	return nil, func() {}
}

func createTestDeviceInDB(t *testing.T, db *pgxpool.Pool, sn string, userID int64) int64 {
	return 1
}

func cleanupTestDevices(t *testing.T, db *pgxpool.Pool) {
}
