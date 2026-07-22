package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"inv-api-server/internal/model"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// ============================================================================
// HTTP Test Helpers
// ============================================================================

// createTestRequest creates a new HTTP test request with JSON body
func createTestRequest(method, path string, body interface{}) *http.Request {
	var buf bytes.Buffer
	if body != nil {
		json.NewEncoder(&buf).Encode(body)
	}
	
	req := httptest.NewRequest(method, path, &buf)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return req
}

// encodeJSON encodes an object to JSON bytes
func encodeJSON(v interface{}) ([]byte, error) {
	var buf bytes.Buffer
	err := json.NewEncoder(&buf).Encode(v)
	return buf.Bytes(), err
}

// decodeJSON decodes JSON response into an object
func decodeJSON(resp *httptest.ResponseRecorder, v interface{}) error {
	return json.Unmarshal(resp.Body.Bytes(), v)
}

// ============================================================================
// Gin Test Context Helpers
// ============================================================================

// createTestGinContext creates a gin.Context for testing with mock request
func createTestGinContext(path string, method string, body interface{}) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	
	c.Request = createTestRequest(method, path, body)
	return c, w
}

// setAuthClaimsInContext sets fake auth claims in gin context
func setAuthClaimsInContext(c *gin.Context, userID int64, role int, rootTenantID int64) {
	c.Set("user_id", userID)
	c.Set("role", role)
	c.Set("root_tenant_id", rootTenantID)
}

// setRoleOnlyInContext sets only the role in context (no user_id)
func setRoleOnlyInContext(c *gin.Context, role int) {
	gin.SetMode(gin.TestMode)
	c.Set("role", role)
}

// ============================================================================
// Assert Helpers
// ============================================================================

// assertHTTPError asserts that the response is an HTTP error with expected status and message
func assertHTTPError(t *testing.T, w *httptest.ResponseRecorder, statusCode int, containsMsg string) {
	assert.Equal(t, statusCode, w.Code, "Expected HTTP status %d, got %d", statusCode, w.Code)
	
	if statusCode >= 400 {
		var resp map[string]interface{}
		err := decodeJSON(w, &resp)
		assert.NoError(t, err, "Response should be valid JSON")
		
		if containsMsg != "" {
			assert.Contains(t, w.Body.String(), containsMsg, "Response should contain message: %s", containsMsg)
		}
	}
}

// assertSuccess asserts that the response is successful
func assertSuccess(t *testing.T, w *httptest.ResponseRecorder) {
	assert.Equal(t, http.StatusOK, w.Code, "Expected OK status, got %d", w.Code)
}

// ============================================================================
// Test Suite Base
// ============================================================================

// BaseTestSuite is a base test suite for all handler tests
type BaseTestSuite struct {
	suite.Suite
	db      *pgxpool.Pool
	router  *gin.Engine
	context *gin.Context
	writer  *httptest.ResponseRecorder
}

// SetupSuite initializes database connection
func (suite *BaseTestSuite) SetupSuite() {
	// This would connect to a test database
	// For now, it's a placeholder
}

// TearDownSuite closes database connection
func (suite *BaseTestSuite) TearDownSuite() {
	if suite.db != nil {
		suite.db.Close()
	}
}

// SetupTest prepares each test case
func (suite *BaseTestSuite) SetupTest() {
	gin.SetMode(gin.TestMode)
	suite.writer = httptest.NewRecorder()
}

// ============================================================================
// Mock Data Generators
// ============================================================================

// GenerateMockOrganization creates a mock organization for testing
func GenerateMockOrganization(id int64, rootTenantID int64, parentID *int64, orgType, name string) *model.Organization {
	return &model.Organization{
		ID:           id,
		RootTenantID: rootTenantID,
		ParentID:     parentID,
		Type:         orgType,
		Name:         name,
		Status:       model.OrganizationStatusActive,
		Version:      1,
		CreatedAt:    nowUTC(),
		UpdatedAt:    nowUTC(),
	}
}

// nowUTC returns current UTC time for consistent test timestamps
func nowUTC() time.Time {
	return time.Now().UTC()
}

// Mock Invitation struct for testing
type Invitation struct {
	ID        int64     `json:"id"`
	Email     string    `json:"email"`
	RoleName  string    `json:"role_name"`
	TokenHint string    `json:"token_hint"`
	ExpiresAt time.Time `json:"expires_at"`
	Status    string    `json:"status"`
	CreatedBy string    `json:"created_by"`
}

// MockOrganizationMembership represents the organization_memberships table structure for tests
type MockOrganizationMembership struct {
	ID             int64      `json:"id"`
	RootTenantID   int64      `json:"root_tenant_id"`
	OrganizationID int64      `json:"organization_id"`
	UserID         int64      `json:"user_id"`
	MembershipType string     `json:"membership_type"`
	RoleIDs        []int      `json:"role_ids"`
	Status         string     `json:"status"`
	ExpiresAt      *time.Time `json:"expires_at,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

// GenerateMockInvitation creates a mock invitation for testing
func GenerateMockInvitation(id int64, email, role string, expiresHours int) *Invitation {
	return &Invitation{
		ID:          id,
		Email:       email,
		RoleName:    role,
		TokenHint:   "mocktoken",
		ExpiresAt:   nowUTC().Add(time.Duration(expiresHours) * time.Hour),
		Status:      "pending",
		CreatedBy:   "test_user",
	}
}

// GenerateMockMembership creates a mock membership for testing
func GenerateMockMembership(id, userID, orgID int64, membershipType string) *MockOrganizationMembership {
	return &MockOrganizationMembership{
		ID:             id,
		RootTenantID:   1,
		OrganizationID: orgID,
		UserID:         userID,
		MembershipType: membershipType,
		Status:         "active",
		RoleIDs:        []int{1},
		CreatedAt:      nowUTC(),
		UpdatedAt:      nowUTC(),
	}
}
