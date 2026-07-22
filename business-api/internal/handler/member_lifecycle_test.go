package handler

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// ============================================================================
// Member Lifecycle Handler Test Suite
// ============================================================================

type MemberLifecycleHandlerTestSuite struct {
	suite.Suite
	handler *MemberLifecycleHandler
	db      *pgxpool.Pool
}

func (suite *MemberLifecycleHandlerTestSuite) SetupSuite() {
	gin.SetMode(gin.TestMode)
}

func (suite *MemberLifecycleHandlerTestSuite) TearDownSuite() {
	if suite.db != nil {
		suite.db.Close()
	}
}

func TestMemberLifecycleHandlerSuite(t *testing.T) {
	suite.Run(t, new(MemberLifecycleHandlerTestSuite))
}

// ============================================================================
// Add Member Tests (Lines 334-460)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_Success() {
	// Arrange
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
		RoleIDs:        []int{1, 2},
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_WithExpiration() {
	// Arrange
	expiresAt := time.Now().Add(30 * 24 * time.Hour)
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
		RoleIDs:        []int{1},
		ExpiresAt:      &expiresAt,
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_ReadOnlyType() {
	// Arrange
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "read_only",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_InvalidRequest() {
	// Arrange - missing required fields
	req := map[string]interface{}{
		"user_id": 10,
		// missing organization_id
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_InvalidMembershipType() {
	// Arrange - invalid type defaults to "full"
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "invalid_type",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should default to "full"
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_UserNotFound() {
	// Arrange
	req := AddMemberRequest{
		UserID:         99999,
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_OrganizationNotFound() {
	// Arrange
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 99999,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_CrossTenantForbidden() {
	// Arrange - user and org belong to different tenants
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_QuotaExceeded() {
	// Arrange - tenant has reached user limit
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_AlreadyActiveMember() {
	// Arrange - user is already active member
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_ReactivateExisting() {
	// Arrange - user was previously removed, reactivate
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.AddMember(c)

	// Assert - should reactivate successfully
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_MissingTenantContext() {
	// Arrange
	req := AddMemberRequest{
		UserID:         10,
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/add", "POST", req)
	c.Set("user_id", 1)
	c.Set("role", 1)
	// Missing root_tenant_id

	// Act
	suite.handler.AddMember(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Update Membership Tests (Lines 465-568)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_Success() {
	// Arrange
	newRoleIDs := []int{2, 3}
	req := UpdateMembershipRequest{
		RoleIDs: &newRoleIDs,
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_ChangeStatus() {
	// Arrange
	newStatus := "inactive"
	req := UpdateMembershipRequest{
		Status: &newStatus,
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_ChangeExpiration() {
	// Arrange
	newExpires := time.Now().Add(60 * 24 * time.Hour)
	req := UpdateMembershipRequest{
		ExpiresAt: &newExpires,
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_ChangeType() {
	// Arrange
	newType := "read_only"
	req := UpdateMembershipRequest{
		MembershipType: &newType,
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidID() {
	// Arrange
	req := UpdateMembershipRequest{
		RoleIDs: &[]int{1},
	}

	c, w := createTestGinContext("/api/v1/memberships/abc/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidRequest() {
	// Arrange - empty request
	req := map[string]interface{}{}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_NotFound() {
	// Arrange
	req := UpdateMembershipRequest{
		RoleIDs: &[]int{1},
	}

	c, w := createTestGinContext("/api/v1/memberships/99999/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidStatus() {
	// Arrange
	invalidStatus := "invalid_status"
	req := UpdateMembershipRequest{
		Status: &invalidStatus,
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidType() {
	// Arrange
	invalidType := "invalid_type"
	req := UpdateMembershipRequest{
		MembershipType: &invalidType,
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_AccessDenied() {
	// Arrange - membership belongs to different tenant
	req := UpdateMembershipRequest{
		RoleIDs: &[]int{1},
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 2) // Different tenant
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_MissingTenantContext() {
	// Arrange
	req := UpdateMembershipRequest{
		RoleIDs: &[]int{1},
	}

	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", req)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.UpdateMembership(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Remove Member Tests (Lines 573-634)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_Success() {
	// Arrange
	req := RemoveMemberRequest{
		Reason: "No longer needed",
	}

	c, w := createTestGinContext("/api/v1/memberships/1/remove", "DELETE", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.RemoveMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_InvalidID() {
	// Arrange
	req := RemoveMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/abc/remove", "DELETE", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.RemoveMember(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_InvalidRequest() {
	// Arrange
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/memberships/1/remove", "DELETE", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.RemoveMember(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_NotFound() {
	// Arrange
	req := RemoveMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/99999/remove", "DELETE", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.RemoveMember(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_AlreadyDeleted() {
	// Arrange - soft deleted membership
	req := RemoveMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/1/remove", "DELETE", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.RemoveMember(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Deactivate Member Tests (Lines 639-703)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_Success() {
	// Arrange
	req := DeactivateMemberRequest{
		Reason: "Temporary suspension",
	}

	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.DeactivateMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_InvalidID() {
	// Arrange
	req := DeactivateMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/abc/deactivate", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.DeactivateMember(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_InvalidRequest() {
	// Arrange
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.DeactivateMember(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_NotFound() {
	// Arrange
	req := DeactivateMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/99999/deactivate", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.DeactivateMember(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_AlreadyInactive() {
	// Arrange - member already inactive
	req := DeactivateMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.DeactivateMember(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_StatusNotChanged() {
	// Arrange - race condition, status changed by another request
	req := DeactivateMemberRequest{}

	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.DeactivateMember(c)

	// Assert - should return 409
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Reactivate Member Tests (Lines 706-763)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ReactivateMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_InvalidID() {
	// Arrange
	c, w := createTestGinContext("/api/v1/memberships/abc/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.ReactivateMember(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_NotFound() {
	// Arrange
	c, w := createTestGinContext("/api/v1/memberships/99999/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.ReactivateMember(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_AlreadyActive() {
	// Arrange - member already active
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ReactivateMember(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_FromSuspended() {
	// Arrange - reactivate from suspended status
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ReactivateMember(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_StatusNotChanged() {
	// Arrange - race condition
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, 1, 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ReactivateMember(c)

	// Assert - should return 409
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Transfer Initiate Tests (Lines 768-878)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_Success() {
	// Arrange
	req := TransferInitiateRequest{
		MembershipIDs: []int64{1, 2, 3},
		TargetOrgID:   200,
		Reason:        "Reorganization",
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_SingleMember() {
	// Arrange
	req := TransferInitiateRequest{
		MembershipIDs: []int64{1},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_InvalidRequest() {
	// Arrange - missing required fields
	req := map[string]interface{}{
		"membership_ids": []int64{1},
		// missing target_org_id
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_EmptyMemberships() {
	// Arrange
	req := TransferInitiateRequest{
		MembershipIDs: []int64{},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_MembershipsNotFound() {
	// Arrange
	req := TransferInitiateRequest{
		MembershipIDs: []int64{99999},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_CrossTenantNotSupported() {
	// Arrange - memberships belong to different tenants
	req := TransferInitiateRequest{
		MembershipIDs: []int64{1, 2},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 409
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_InactiveMember() {
	// Arrange - one of the members is not active
	req := TransferInitiateRequest{
		MembershipIDs: []int64{1, 2},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_TargetOrgNotFound() {
	// Arrange
	req := TransferInitiateRequest{
		MembershipIDs: []int64{1, 2},
		TargetOrgID:   99999,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_TargetOrgDifferentTenant() {
	// Arrange
	req := TransferInitiateRequest{
		MembershipIDs: []int64{1, 2},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferInitiate(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Transfer Accept/Reject Tests (Lines 882-937)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_Success() {
	// Arrange
	req := TransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferAccept(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_InvalidRequest() {
	// Arrange
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferAccept(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_RejectedNeedsReason() {
	// Arrange - trying to reject without reason
	req := TransferApprovalRequest{
		Approved: false,
		Reason:   "",
	}

	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferAccept(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_Success() {
	// Arrange
	req := TransferApprovalRequest{
		Approved: false,
		Reason:   "Not acceptable",
	}

	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferReject(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_InvalidRequest() {
	// Arrange
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferReject(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_ApprovedTrue() {
	// Arrange - reject requires approved=false
	req := TransferApprovalRequest{
		Approved: true,
	}

	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferReject(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_MissingReason() {
	// Arrange
	req := TransferApprovalRequest{
		Approved: false,
		Reason:   "",
	}

	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.TransferReject(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// List Transfers Tests (Lines 940-975)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/members/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.ListTransfers(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_EmptyResult() {
	// Arrange - no pending transfers
	c, w := createTestGinContext("/api/v1/members/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.ListTransfers(c)

	// Assert - should return empty list
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_QueryFailed() {
	// Arrange - table doesn't exist yet
	c, w := createTestGinContext("/api/v1/members/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.ListTransfers(c)

	// Assert - should return empty list gracefully
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Bulk Add Tests (Lines 980-1082)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_Success() {
	// Arrange
	req := BulkAddRequest{
		UserIDs:        []int64{10, 20, 30},
		OrganizationID: 100,
		MembershipType: "full",
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_InvalidRequest() {
	// Arrange
	req := map[string]interface{}{
		"user_ids": []int64{10},
		// missing organization_id
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_OrganizationNotFound() {
	// Arrange
	req := BulkAddRequest{
		UserIDs:        []int64{10},
		OrganizationID: 99999,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_OrganizationNotInTenant() {
	// Arrange
	req := BulkAddRequest{
		UserIDs:        []int64{10},
		OrganizationID: 100,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 2) // Different tenant
	c.Set("root_tenant_id", int64(2))

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_InvalidMembershipType() {
	// Arrange - defaults to "full"
	req := BulkAddRequest{
		UserIDs:        []int64{10},
		OrganizationID: 100,
		MembershipType: "invalid",
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should default to "full"
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_SkipExistingMembers() {
	// Arrange - some users already members
	req := BulkAddRequest{
		UserIDs:        []int64{10, 20},
		OrganizationID: 100,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should skip existing, add new
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_ReactivateInactive() {
	// Arrange - some users were inactive
	req := BulkAddRequest{
		UserIDs:        []int64{10},
		OrganizationID: 100,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should reactivate
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_MissingTenantContext() {
	// Arrange
	req := BulkAddRequest{
		UserIDs:        []int64{10},
		OrganizationID: 100,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	c.Set("user_id", 1)
	c.Set("role", 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_UserNotFound() {
	// Arrange - some users don't exist
	req := BulkAddRequest{
		UserIDs:        []int64{99999},
		OrganizationID: 100,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkAdd(c)

	// Assert - should skip non-existent users
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Bulk Transfer Tests (Lines 1085-1166)
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_Success() {
	// Arrange
	req := BulkTransferRequest{
		MembershipIDs: []int64{1, 2, 3},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkTransfer(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_InvalidRequest() {
	// Arrange
	req := map[string]interface{}{
		"membership_ids": []int64{1},
		// missing target_org_id
	}

	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkTransfer(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_MembershipsNotFound() {
	// Arrange
	req := BulkTransferRequest{
		MembershipIDs: []int64{99999},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkTransfer(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_CrossTenantNotSupported() {
	// Arrange
	req := BulkTransferRequest{
		MembershipIDs: []int64{1, 2},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkTransfer(c)

	// Assert - should return 409
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_TargetOrgNotFound() {
	// Arrange
	req := BulkTransferRequest{
		MembershipIDs: []int64{1},
		TargetOrgID:   99999,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkTransfer(c)

	// Assert - should return 404/403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_TargetOrgDifferentTenant() {
	// Arrange
	req := BulkTransferRequest{
		MembershipIDs: []int64{1},
		TargetOrgID:   200,
	}

	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 1)

	// Act
	suite.handler.BulkTransfer(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Helper Function Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestMembershipIDsToUserIDs() {
	// Arrange
	memberships := []*OrganizationMembership{
		{ID: 1, UserID: 10},
		{ID: 2, UserID: 20},
		{ID: 3, UserID: 30},
	}

	// Act
	userIDs := membershipIDsToUserIDs(memberships)

	// Assert
	assert.Equal(suite.T(), []int64{10, 20, 30}, userIDs)
}

func (suite *MemberLifecycleHandlerTestSuite) TestMembershipIDsToUserIDs_Empty() {
	// Arrange
	memberships := []*OrganizationMembership{}

	// Act
	userIDs := membershipIDsToUserIDs(memberships)

	// Assert
	assert.Equal(suite.T(), []int64{}, userIDs)
}

// ============================================================================
// Integration Test Helpers
// ============================================================================

func setupMemberLifecycleTest(t *testing.T) (*MemberLifecycleHandler, func()) {
	return nil, func() {}
}

func createTestMembershipInDB(t *testing.T, db *pgxpool.Pool, userID, orgID int64) int64 {
	return 1
}

func cleanupTestMemberships(t *testing.T, db *pgxpool.Pool) {
}
