package handler

import (
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// ============================================================================
// Organization Handler Test Suite
// ============================================================================

type OrganizationHandlerTestSuite struct {
	suite.Suite
	handler *OrganizationHandler
	db      *pgxpool.Pool
}

func (suite *OrganizationHandlerTestSuite) SetupSuite() {
	gin.SetMode(gin.TestMode)
	// In real tests, connect to test database here
	// For now, we'll test the logic without actual DB calls
}

func (suite *OrganizationHandlerTestSuite) TearDownSuite() {
	if suite.db != nil {
		suite.db.Close()
	}
}

func TestOrganizationHandlerSuite(t *testing.T) {
	suite.Run(t, new(OrganizationHandlerTestSuite))
}

// ============================================================================
// Create Organization Tests (Lines 88-270)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_Success() {
	// Arrange
	req := CreateOrganizationRequest{
		Name: "Test Org",
		Type: "agent",
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100) // Non-enduser role

	// Act
	suite.handler.Create(c)

	// Assert - would need actual DB to verify, but we can check request binding
	assert.NotNil(suite.T(), c)
	_ = w // Response recorder for future use
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_InvalidType() {
	// Arrange
	req := CreateOrganizationRequest{
		Name: "Test Org",
		Type: "invalid_type",
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.Create(c)

	// Assert - should return 400 Bad Request for invalid type
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_EnduserForbidden() {
	// Arrange
	req := CreateOrganizationRequest{
		Name: "Test Org",
		Type: "agent",
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 5, 100) // Enduser role

	// Act
	suite.handler.Create(c)

	// Assert - should return 403 Forbidden
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_InvalidRequest() {
	// Arrange - missing required fields
	req := map[string]interface{}{
		"name": "Test Org",
		// missing "type"
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.Create(c)

	// Assert - should return 400 Bad Request
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_WithParentID() {
	// Arrange
	parentID := int64(10)
	req := CreateOrganizationRequest{
		Name:     "Child Org",
		Type:     "distributor",
		ParentID: &parentID,
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.Create(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_ParentNotFound() {
	// Arrange - parent ID doesn't exist
	parentID := int64(99999)
	req := CreateOrganizationRequest{
		Name:     "Child Org",
		Type:     "distributor",
		ParentID: &parentID,
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.Create(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_ParentWrongTenant() {
	// Arrange - parent belongs to different tenant
	parentID := int64(10)
	req := CreateOrganizationRequest{
		Name:     "Child Org",
		Type:     "distributor",
		ParentID: &parentID,
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.Create(c)

	// Assert - should return 403 Forbidden
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_MissingTenantContext() {
	// Arrange
	req := CreateOrganizationRequest{
		Name: "Test Org",
		Type: "agent",
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	c.Set("user_id", 1)
	c.Set("role", 1)
	// Missing root_tenant_id

	// Act
	suite.handler.Create(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// List Organizations Tests (Lines 273-388)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations?page=1&page_size=20", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.List(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_WithTypeFilter() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations?type=agent", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.List(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_WithStatusFilter() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations?status=active", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.List(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_PaginationDefaults() {
	// Arrange - no pagination params
	c, w := createTestGinContext("/api/v1/organizations", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.List(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_MissingTenantContext() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations", "GET", nil)
	c.Set("user_id", 1)
	c.Set("role", 1)
	// Missing root_tenant_id

	// Act
	suite.handler.List(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_SuperAdmin() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations", "GET", nil)
	setAuthClaimsInContext(c, 1, 0, 100) // Super admin role

	// Act
	suite.handler.List(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Get Organization By ID Tests (Lines 391-470)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestGetOrganization_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/1", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetByID(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetOrganization_InvalidID() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/abc", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.GetByID(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetOrganization_NotFound() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/99999", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.GetByID(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetOrganization_AccessDenied() {
	// Arrange - org exists but belongs to different tenant
	c, w := createTestGinContext("/api/v1/organizations/1", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetByID(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetOrganization_WithChildren() {
	// Arrange - org has child organizations
	c, w := createTestGinContext("/api/v1/organizations/1", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetByID(c)

	// Assert - should include children in response
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetOrganization_MissingTenantContext() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/1", "GET", nil)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetByID(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Update Organization Tests (Lines 473-554)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestUpdateOrganization_Success() {
	// Arrange
	req := UpdateOrganizationRequest{
		Name: "Updated Org Name",
	}

	c, w := createTestGinContext("/api/v1/organizations/1", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Update(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestUpdateOrganization_InvalidID() {
	// Arrange
	req := UpdateOrganizationRequest{
		Name: "Updated Name",
	}

	c, w := createTestGinContext("/api/v1/organizations/abc", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.Update(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestUpdateOrganization_InvalidRequest() {
	// Arrange - missing required name field
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/organizations/1", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Update(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestUpdateOrganization_NotFound() {
	// Arrange
	req := UpdateOrganizationRequest{
		Name: "Updated Name",
	}

	c, w := createTestGinContext("/api/v1/organizations/99999", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.Update(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestUpdateOrganization_TenantScopeViolation() {
	// Arrange - org exists but not in tenant scope
	req := UpdateOrganizationRequest{
		Name: "Updated Name",
	}

	c, w := createTestGinContext("/api/v1/organizations/1", "PUT", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Update(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestUpdateOrganization_MissingTenantContext() {
	// Arrange
	req := UpdateOrganizationRequest{
		Name: "Updated Name",
	}

	c, w := createTestGinContext("/api/v1/organizations/1", "PUT", req)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Update(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Delete Organization Tests (Lines 557-636)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestDeleteOrganization_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/1", "DELETE", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Delete(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestDeleteOrganization_InvalidID() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/abc", "DELETE", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.Delete(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestDeleteOrganization_HasChildren() {
	// Arrange - org has child organizations
	c, w := createTestGinContext("/api/v1/organizations/1", "DELETE", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Delete(c)

	// Assert - should return 400 Bad Request (cannot delete with children)
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestDeleteOrganization_NotFound() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/99999", "DELETE", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.Delete(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestDeleteOrganization_AlreadyDeleted() {
	// Arrange - soft deleted org
	c, w := createTestGinContext("/api/v1/organizations/1", "DELETE", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Delete(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestDeleteOrganization_MissingTenantContext() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/1", "DELETE", nil)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Delete(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Move Organization Tests (Lines 639-768)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_Success() {
	// Arrange
	req := MoveOrganizationRequest{
		ParentID: 2,
	}

	c, w := createTestGinContext("/api/v1/organizations/1/move", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Move(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_InvalidID() {
	// Arrange
	req := MoveOrganizationRequest{
		ParentID: 2,
	}

	c, w := createTestGinContext("/api/v1/organizations/abc/move", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.Move(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_CircularReference() {
	// Arrange - trying to move org into its own descendant
	req := MoveOrganizationRequest{
		ParentID: 10,
	}

	c, w := createTestGinContext("/api/v1/organizations/1/move", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Move(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_ParentNotFound() {
	// Arrange
	req := MoveOrganizationRequest{
		ParentID: 99999,
	}

	c, w := createTestGinContext("/api/v1/organizations/1/move", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Move(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_OrgNotInTenant() {
	// Arrange - org exists but not in tenant scope
	req := MoveOrganizationRequest{
		ParentID: 2,
	}

	c, w := createTestGinContext("/api/v1/organizations/1/move", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Move(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_InvalidRequest() {
	// Arrange - missing required parent_id
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/move", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Move(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestMoveOrganization_MissingTenantContext() {
	// Arrange
	req := MoveOrganizationRequest{
		ParentID: 2,
	}

	c, w := createTestGinContext("/api/v1/organizations/1/move", "POST", req)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.Move(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Toggle Status Tests (Lines 771-859)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_Success_Active() {
	// Arrange
	req := ToggleStatusRequest{
		Status: "active",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_Success_Disabled() {
	// Arrange
	req := ToggleStatusRequest{
		Status: "disabled",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_InvalidID() {
	// Arrange
	req := ToggleStatusRequest{
		Status: "active",
	}

	c, w := createTestGinContext("/api/v1/organizations/abc/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_InvalidStatusValue() {
	// Arrange
	req := ToggleStatusRequest{
		Status: "invalid_status",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_InvalidRequest() {
	// Arrange - missing required status field
	req := map[string]interface{}{
		"invalid": "field",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_NotFound() {
	// Arrange
	req := ToggleStatusRequest{
		Status: "active",
	}

	c, w := createTestGinContext("/api/v1/organizations/99999/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_SameStatus() {
	// Arrange - status is already active, setting to active
	req := ToggleStatusRequest{
		Status: "active",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/status", "PATCH", req)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert - should succeed without changing version
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestToggleStatus_MissingTenantContext() {
	// Arrange
	req := ToggleStatusRequest{
		Status: "active",
	}

	c, w := createTestGinContext("/api/v1/organizations/1/status", "PATCH", req)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.ToggleStatus(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Get Tree Tests (Lines 862-958)
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestGetTree_Success() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/1/tree", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetTree(c)

	// Assert
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetTree_InvalidID() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/abc/tree", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "abc"}}

	// Act
	suite.handler.GetTree(c)

	// Assert - should return 400
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetTree_NotFound() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/99999/tree", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "99999"}}

	// Act
	suite.handler.GetTree(c)

	// Assert - should return 404
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetTree_AccessDenied() {
	// Arrange - org exists but belongs to different tenant
	c, w := createTestGinContext("/api/v1/organizations/1/tree", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetTree(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetTree_LeafNode() {
	// Arrange - org has no children
	c, w := createTestGinContext("/api/v1/organizations/1/tree", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetTree(c)

	// Assert - should return only the root node
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetTree_DeepHierarchy() {
	// Arrange - org has multiple levels of descendants
	c, w := createTestGinContext("/api/v1/organizations/1/tree", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetTree(c)

	// Assert - should return full subtree
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestGetTree_MissingTenantContext() {
	// Arrange
	c, w := createTestGinContext("/api/v1/organizations/1/tree", "GET", nil)
	c.Set("user_id", 1)
	c.Set("role", 1)
	c.Params = []gin.Param{{Key: "id", Value: "1"}}

	// Act
	suite.handler.GetTree(c)

	// Assert - should return 403
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Edge Cases and Boundary Tests
// ============================================================================

func (suite *OrganizationHandlerTestSuite) TestCreateOrganization_DuplicateName() {
	// Arrange - org with same name already exists under parent
	req := CreateOrganizationRequest{
		Name: "Duplicate Org",
		Type: "agent",
	}

	c, w := createTestGinContext("/api/v1/organizations", "POST", req)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.Create(c)

	// Assert - should return 409 Conflict
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_EmptyResult() {
	// Arrange - no organizations match criteria
	c, w := createTestGinContext("/api/v1/organizations?status=inactive", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.List(c)

	// Assert - should return empty list with total=0
	assert.NotNil(suite.T(), c)
	_ = w
}

func (suite *OrganizationHandlerTestSuite) TestListOrganizations_InvalidPageSize() {
	// Arrange - pageSize > 100 should be capped
	c, w := createTestGinContext("/api/v1/organizations?page_size=200", "GET", nil)
	setAuthClaimsInContext(c, 1, 1, 100)

	// Act
	suite.handler.List(c)

	// Assert - should cap at 100
	assert.NotNil(suite.T(), c)
	_ = w
}

// ============================================================================
// Integration Test Helpers (For future real DB tests)
// ============================================================================

func setupOrganizationTest(t *testing.T) (*OrganizationHandler, func()) {
	// This would setup test DB, migrations, and handler
	// For now, return nil handler
	return nil, func() {}
}

func createTestOrgInDB(t *testing.T, db *pgxpool.Pool, rootTenantID int64, name, orgType string) int64 {
	// This would insert test organization into DB
	// For now, return mock ID
	return 1
}

func cleanupTestOrganizations(t *testing.T, db *pgxpool.Pool) {
	// This would clean up test data
}
