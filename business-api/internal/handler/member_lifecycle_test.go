package handler

import (
	"context"
	"testing"
	"time"

	"inv-api-server/internal/service"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// ============================================================================
// Mock Member Lifecycle Service
// ============================================================================

type mockMemberLifecycleService struct {
	addMemberFn        func(ctx context.Context, actorUserID int64, tenantID int64, req service.AddMemberParams) (*service.AddMemberResult, error)
	updateMembershipFn func(ctx context.Context, actorUserID int64, tenantID int64, membershipID int64, req service.UpdateMembershipParams) error
	removeMemberFn     func(ctx context.Context, actorUserID int64, membershipID int64, reason string) error
	deactivateMemberFn func(ctx context.Context, actorUserID int64, membershipID int64, reason string) error
	reactivateMemberFn func(ctx context.Context, actorUserID int64, membershipID int64) error
	updateMemberRoleFn func(ctx context.Context, actorUserID int64, tenantID int64, membershipID int64, role string) error
	transferInitiateFn func(ctx context.Context, actorUserID int64, membershipIDs []int64, targetOrgID int64, reason string) (*service.TransferResult, error)
	transferAcceptFn   func(ctx context.Context, actorUserID int64, transferID int64) error
	transferRejectFn   func(ctx context.Context, actorUserID int64, transferID int64, reason string) error
	listTransfersFn    func(ctx context.Context, viewerUserID int64, page, pageSize int, status string) (*service.ListTransfersResult, error)
	getUserByEmailFn   func(ctx context.Context, actorUserID int64, email string) (*service.UserLookupResult, error)
	listMembersFn     func(ctx context.Context, orgID int64, page, pageSize int, roleFilter string) (*service.ListMembersResult, error)
	bulkAddFn          func(ctx context.Context, actorUserID int64, tenantID int64, req service.BulkAddParams) (*service.BulkAddResult, error)
	bulkTransferFn     func(ctx context.Context, actorUserID int64, req service.BulkTransferParams) (*service.BulkTransferResult, error)
}

func (m *mockMemberLifecycleService) ListMembers(ctx context.Context, orgID int64, page, pageSize int, roleFilter string) (*service.ListMembersResult, error) {
	if m.listMembersFn != nil {
		return m.listMembersFn(ctx, orgID, page, pageSize, roleFilter)
	}
	return &service.ListMembersResult{Page: page, Size: pageSize}, nil
}

func (m *mockMemberLifecycleService) AddMember(ctx context.Context, a int64, t int64, r service.AddMemberParams) (*service.AddMemberResult, error) {
	if m.addMemberFn != nil {
		return m.addMemberFn(ctx, a, t, r)
	}
	return &service.AddMemberResult{OrganizationID: 100, UserID: 10}, nil
}
func (m *mockMemberLifecycleService) UpdateMembership(ctx context.Context, a int64, t int64, mi int64, r service.UpdateMembershipParams) error {
	if m.updateMembershipFn != nil {
		return m.updateMembershipFn(ctx, a, t, mi, r)
	}
	return nil
}
func (m *mockMemberLifecycleService) RemoveMember(ctx context.Context, a int64, mi int64, r string) error {
	if m.removeMemberFn != nil {
		return m.removeMemberFn(ctx, a, mi, r)
	}
	return nil
}
func (m *mockMemberLifecycleService) DeactivateMember(ctx context.Context, a int64, mi int64, r string) error {
	if m.deactivateMemberFn != nil {
		return m.deactivateMemberFn(ctx, a, mi, r)
	}
	return nil
}
func (m *mockMemberLifecycleService) ReactivateMember(ctx context.Context, a int64, mi int64) error {
	if m.reactivateMemberFn != nil {
		return m.reactivateMemberFn(ctx, a, mi)
	}
	return nil
}
func (m *mockMemberLifecycleService) UpdateMemberRole(ctx context.Context, a int64, t int64, mi int64, role string) error {
	if m.updateMemberRoleFn != nil {
		return m.updateMemberRoleFn(ctx, a, t, mi, role)
	}
	return nil
}
func (m *mockMemberLifecycleService) TransferInitiate(ctx context.Context, a int64, mi []int64, to int64, r string) (*service.TransferResult, error) {
	if m.transferInitiateFn != nil {
		return m.transferInitiateFn(ctx, a, mi, to, r)
	}
	return &service.TransferResult{OrganizationID: 200, PendingCount: 3}, nil
}
func (m *mockMemberLifecycleService) TransferAccept(ctx context.Context, a int64, ti int64) error {
	if m.transferAcceptFn != nil {
		return m.transferAcceptFn(ctx, a, ti)
	}
	return nil
}
func (m *mockMemberLifecycleService) TransferReject(ctx context.Context, a int64, ti int64, r string) error {
	if m.transferRejectFn != nil {
		return m.transferRejectFn(ctx, a, ti, r)
	}
	return nil
}
func (m *mockMemberLifecycleService) ListTransfers(ctx context.Context, u int64, page, pageSize int, status string) (*service.ListTransfersResult, error) {
	if m.listTransfersFn != nil {
		return m.listTransfersFn(ctx, u, page, pageSize, status)
	}
	return &service.ListTransfersResult{Items: []service.TransferRequestInfo{}, Page: page, Size: pageSize}, nil
}
func (m *mockMemberLifecycleService) GetUserByEmail(ctx context.Context, a int64, email string) (*service.UserLookupResult, error) {
	if m.getUserByEmailFn != nil {
		return m.getUserByEmailFn(ctx, a, email)
	}
	return &service.UserLookupResult{UserID: 10, Email: email, Nickname: "User10"}, nil
}
func (m *mockMemberLifecycleService) BulkAdd(ctx context.Context, a int64, t int64, r service.BulkAddParams) (*service.BulkAddResult, error) {
	if m.bulkAddFn != nil {
		return m.bulkAddFn(ctx, a, t, r)
	}
	return &service.BulkAddResult{OrganizationID: 100, AddedCount: 3}, nil
}
func (m *mockMemberLifecycleService) BulkTransfer(ctx context.Context, a int64, r service.BulkTransferParams) (*service.BulkTransferResult, error) {
	if m.bulkTransferFn != nil {
		return m.bulkTransferFn(ctx, a, r)
	}
	return &service.BulkTransferResult{OrganizationID: 200, TransferredCount: 3}, nil
}

// svcErr creates a *service.MemberServiceError for mock service returns.
func svcErr(code int, msg string) error {
	return &service.MemberServiceError{Code: code, Message: msg}
}

// ============================================================================
// Test Suite
// ============================================================================

type MemberLifecycleHandlerTestSuite struct {
	suite.Suite
	handler *MemberLifecycleHandler
	mockSvc *mockMemberLifecycleService
}

func (suite *MemberLifecycleHandlerTestSuite) SetupSuite() {
	gin.SetMode(gin.TestMode)
}

func (suite *MemberLifecycleHandlerTestSuite) SetupTest() {
	suite.mockSvc = &mockMemberLifecycleService{}
	suite.handler = NewMemberLifecycleHandler(suite.mockSvc)
}

func TestMemberLifecycleHandlerSuite(t *testing.T) {
	suite.Run(t, new(MemberLifecycleHandlerTestSuite))
}

// ============================================================================
// Add Member Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_Success() {
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full", RoleIDs: []int{1, 2},
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_WithExpiration() {
	expiresAt := time.Now().Add(30 * 24 * time.Hour)
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full", RoleIDs: []int{1}, ExpiresAt: &expiresAt,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_ReadOnlyType() {
	var captured service.AddMemberParams
	suite.mockSvc.addMemberFn = func(_ context.Context, _ int64, _ int64, r service.AddMemberParams) (*service.AddMemberResult, error) {
		captured = r
		return &service.AddMemberResult{OrganizationID: 100, UserID: 10}, nil
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "read_only",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 0, "")
	assert.Equal(suite.T(), "read_only", captured.MembershipType)
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/add", "POST", map[string]interface{}{
		"user_id": 10, // missing organization_id
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_InvalidMembershipType() {
	var captured service.AddMemberParams
	suite.mockSvc.addMemberFn = func(_ context.Context, _ int64, _ int64, r service.AddMemberParams) (*service.AddMemberResult, error) {
		captured = r
		return &service.AddMemberResult{OrganizationID: 100, UserID: 10}, nil
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "invalid_type",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 0, "")
	// Handler only defaults empty string to "full"; invalid types pass through
	assert.Equal(suite.T(), "invalid_type", captured.MembershipType)
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_UserNotFound() {
	suite.mockSvc.addMemberFn = func(context.Context, int64, int64, service.AddMemberParams) (*service.AddMemberResult, error) {
		return nil, svcErr(404, "用户不存在")
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 99999, OrganizationID: 100, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_OrganizationNotFound() {
	suite.mockSvc.addMemberFn = func(context.Context, int64, int64, service.AddMemberParams) (*service.AddMemberResult, error) {
		return nil, svcErr(404, "组织不存在")
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 99999, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_CrossTenantForbidden() {
	suite.mockSvc.addMemberFn = func(context.Context, int64, int64, service.AddMemberParams) (*service.AddMemberResult, error) {
		return nil, svcErr(403, "无权操作此组织")
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 403, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_QuotaExceeded() {
	suite.mockSvc.addMemberFn = func(context.Context, int64, int64, service.AddMemberParams) (*service.AddMemberResult, error) {
		return nil, svcErr(409, "已达用户数上限")
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_AlreadyActiveMember() {
	suite.mockSvc.addMemberFn = func(context.Context, int64, int64, service.AddMemberParams) (*service.AddMemberResult, error) {
		return nil, svcErr(409, "该用户已是此组织活跃成员")
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_ReactivateExisting() {
	suite.mockSvc.addMemberFn = func(context.Context, int64, int64, service.AddMemberParams) (*service.AddMemberResult, error) {
		return &service.AddMemberResult{OrganizationID: 100, UserID: 10}, nil
	}
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_MissingTenantContext() {
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full",
	})
	setAuthWithoutTenant(c, 1, false)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 403, "tenant context missing")
}

func (suite *MemberLifecycleHandlerTestSuite) TestAddMember_SystemAdminWithoutTenantAllowed() {
	// 系统管理员可能没有租户上下文（RootTenantID=0），应放行由 service 层校验
	c, w := createTestGinContext("/api/v1/members/add", "POST", AddMemberRequest{
		UserID: 10, OrganizationID: 100, MembershipType: "full",
	})
	setAuthWithoutTenant(c, 1, true)
	suite.handler.AddMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

// ============================================================================
// Update Membership Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_Success() {
	newRoleIDs := []int{2, 3}
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{RoleIDs: &newRoleIDs})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_ChangeStatus() {
	newStatus := "inactive"
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{Status: &newStatus})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_ChangeExpiration() {
	newExpires := time.Now().Add(60 * 24 * time.Hour)
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{ExpiresAt: &newExpires})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_ChangeType() {
	newType := "read_only"
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{MembershipType: &newType})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	// Handler does not pass MembershipType to service; update succeeds
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidID() {
	c, w := createTestGinContext("/api/v1/memberships/abc/update", "PUT", UpdateMembershipRequest{RoleIDs: &[]int{1}})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidRequest() {
	// expires_at with invalid date format causes binding error
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", map[string]interface{}{
		"expires_at": "not-a-valid-date",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_NotFound() {
	suite.mockSvc.updateMembershipFn = func(context.Context, int64, int64, int64, service.UpdateMembershipParams) error {
		return svcErr(404, "会员关系不存在")
	}
	c, w := createTestGinContext("/api/v1/memberships/99999/update", "PUT", UpdateMembershipRequest{RoleIDs: &[]int{1}})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "99999"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidStatus() {
	suite.mockSvc.updateMembershipFn = func(context.Context, int64, int64, int64, service.UpdateMembershipParams) error {
		return svcErr(400, "无效的状态值")
	}
	invalidStatus := "invalid_status"
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{Status: &invalidStatus})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_InvalidType() {
	// Handler does not pass MembershipType to service; invalid type is silently ignored
	invalidType := "invalid_type"
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{MembershipType: &invalidType})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_AccessDenied() {
	suite.mockSvc.updateMembershipFn = func(context.Context, int64, int64, int64, service.UpdateMembershipParams) error {
		return svcErr(403, "无权操作此会员关系")
	}
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{RoleIDs: &[]int{1}})
	setAuthClaimsInContext(c, 1, true, 2)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 403, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestUpdateMembership_MissingTenantContext() {
	c, w := createTestGinContext("/api/v1/memberships/1/update", "PUT", UpdateMembershipRequest{RoleIDs: &[]int{1}})
	setAuthWithoutTenant(c, 1, true)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.UpdateMembership(c)
	assertBizResponse(suite.T(), w, 403, "tenant context missing")
}

// ============================================================================
// Remove Member Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_Success() {
	c, w := createTestGinContext("/api/v1/memberships/1/remove", "DELETE", RemoveMemberRequest{Reason: "No longer needed"})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.RemoveMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_InvalidID() {
	c, w := createTestGinContext("/api/v1/memberships/abc/remove", "DELETE", RemoveMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.RemoveMember(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_InvalidRequest() {
	// reason as number causes binding error
	c, w := createTestGinContext("/api/v1/memberships/1/remove", "DELETE", map[string]interface{}{"reason": 123})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.RemoveMember(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_NotFound() {
	suite.mockSvc.removeMemberFn = func(context.Context, int64, int64, string) error {
		return svcErr(404, "会员关系不存在")
	}
	c, w := createTestGinContext("/api/v1/memberships/99999/remove", "DELETE", RemoveMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "99999"}}
	suite.handler.RemoveMember(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestRemoveMember_AlreadyDeleted() {
	suite.mockSvc.removeMemberFn = func(context.Context, int64, int64, string) error {
		return svcErr(404, "会员关系已被删除")
	}
	c, w := createTestGinContext("/api/v1/memberships/1/remove", "DELETE", RemoveMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.RemoveMember(c)
	assertBizResponse(suite.T(), w, 404, "")
}

// ============================================================================
// Deactivate Member Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_Success() {
	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", DeactivateMemberRequest{Reason: "Temporary suspension"})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.DeactivateMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_InvalidID() {
	c, w := createTestGinContext("/api/v1/memberships/abc/deactivate", "PATCH", DeactivateMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.DeactivateMember(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", map[string]interface{}{"reason": 123})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.DeactivateMember(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_NotFound() {
	suite.mockSvc.deactivateMemberFn = func(context.Context, int64, int64, string) error {
		return svcErr(404, "会员关系不存在")
	}
	c, w := createTestGinContext("/api/v1/memberships/99999/deactivate", "PATCH", DeactivateMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "99999"}}
	suite.handler.DeactivateMember(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_AlreadyInactive() {
	suite.mockSvc.deactivateMemberFn = func(context.Context, int64, int64, string) error {
		return svcErr(409, "成员已处于停用状态")
	}
	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", DeactivateMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.DeactivateMember(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestDeactivateMember_StatusNotChanged() {
	suite.mockSvc.deactivateMemberFn = func(context.Context, int64, int64, string) error {
		return svcErr(409, "状态冲突")
	}
	c, w := createTestGinContext("/api/v1/memberships/1/deactivate", "PATCH", DeactivateMemberRequest{})
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.DeactivateMember(c)
	assertBizResponse(suite.T(), w, 409, "")
}

// ============================================================================
// Reactivate Member Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_Success() {
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.ReactivateMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_InvalidID() {
	c, w := createTestGinContext("/api/v1/memberships/abc/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "abc"}}
	suite.handler.ReactivateMember(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_NotFound() {
	suite.mockSvc.reactivateMemberFn = func(context.Context, int64, int64) error {
		return svcErr(404, "会员关系不存在")
	}
	c, w := createTestGinContext("/api/v1/memberships/99999/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "99999"}}
	suite.handler.ReactivateMember(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_AlreadyActive() {
	suite.mockSvc.reactivateMemberFn = func(context.Context, int64, int64) error {
		return svcErr(409, "成员已处于活跃状态")
	}
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.ReactivateMember(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_FromSuspended() {
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.ReactivateMember(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestReactivateMember_StatusNotChanged() {
	suite.mockSvc.reactivateMemberFn = func(context.Context, int64, int64) error {
		return svcErr(409, "状态冲突")
	}
	c, w := createTestGinContext("/api/v1/memberships/1/reactivate", "PATCH", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	c.Params = gin.Params{{Key: "id", Value: "1"}}
	suite.handler.ReactivateMember(c)
	assertBizResponse(suite.T(), w, 409, "")
}

// ============================================================================
// Transfer Initiate Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_Success() {
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{1, 2, 3}, TargetOrgID: 200, Reason: "Reorganization",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_SingleMember() {
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{1}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", map[string]interface{}{
		"membership_ids": []int64{1}, // missing target_org_id
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_EmptyMemberships() {
	suite.mockSvc.transferInitiateFn = func(context.Context, int64, []int64, int64, string) (*service.TransferResult, error) {
		return nil, svcErr(400, "membership_ids cannot be empty")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_MembershipsNotFound() {
	suite.mockSvc.transferInitiateFn = func(context.Context, int64, []int64, int64, string) (*service.TransferResult, error) {
		return nil, svcErr(404, "会员关系不存在")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{99999}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_CrossTenantNotSupported() {
	suite.mockSvc.transferInitiateFn = func(context.Context, int64, []int64, int64, string) (*service.TransferResult, error) {
		return nil, svcErr(409, "跨租户转移不支持")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{1, 2}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_InactiveMember() {
	suite.mockSvc.transferInitiateFn = func(context.Context, int64, []int64, int64, string) (*service.TransferResult, error) {
		return nil, svcErr(400, "包含非活跃成员")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{1, 2}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_TargetOrgNotFound() {
	suite.mockSvc.transferInitiateFn = func(context.Context, int64, []int64, int64, string) (*service.TransferResult, error) {
		return nil, svcErr(404, "目标组织不存在")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{1, 2}, TargetOrgID: 99999,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferInitiate_TargetOrgDifferentTenant() {
	suite.mockSvc.transferInitiateFn = func(context.Context, int64, []int64, int64, string) (*service.TransferResult, error) {
		return nil, svcErr(403, "目标组织属于不同租户")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/initiate", "POST", TransferInitiateRequest{
		MembershipIDs: []int64{1, 2}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferInitiate(c)
	assertBizResponse(suite.T(), w, 403, "")
}

// ============================================================================
// Transfer Accept/Reject Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_Success() {
	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", map[string]interface{}{
		"transfer_id": 1,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferAccept(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_LegacyApprovedFieldIgnored() {
	// 旧前端可能仍传 approved 字段，多余字段应被忽略而非报错
	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", map[string]interface{}{
		"transfer_id": 1, "approved": true,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferAccept(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", map[string]interface{}{
		"invalid": "field",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferAccept(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_NotPending() {
	suite.mockSvc.transferAcceptFn = func(context.Context, int64, int64) error {
		return svcErr(409, "该申请已被处理")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", map[string]interface{}{
		"transfer_id": 1,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferAccept(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferAccept_NotTargetOrgAdmin() {
	suite.mockSvc.transferAcceptFn = func(context.Context, int64, int64) error {
		return svcErr(403, "仅目标组织管理员可审批此转移")
	}
	c, w := createTestGinContext("/api/v1/members/transfer/accept", "POST", map[string]interface{}{
		"transfer_id": 1,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferAccept(c)
	assertBizResponse(suite.T(), w, 403, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_Success() {
	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", map[string]interface{}{
		"transfer_id": 1, "reason": "Not acceptable",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferReject(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", map[string]interface{}{
		"invalid": "field",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferReject(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestTransferReject_ReasonOptional() {
	// 拒绝原因改为可选字段，空 reason 也能正常拒绝
	c, w := createTestGinContext("/api/v1/members/transfer/reject", "POST", map[string]interface{}{
		"transfer_id": 1, "reason": "",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.TransferReject(c)
	assertBizResponse(suite.T(), w, 0, "")
}

// ============================================================================
// List Transfers Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_Success() {
	suite.mockSvc.listTransfersFn = func(context.Context, int64, int, int, string) (*service.ListTransfersResult, error) {
		return &service.ListTransfersResult{
			Items: []service.TransferRequestInfo{{ID: 1, MembershipID: 10, Status: "pending", ResourceType: "user"}},
			Total: 1, Page: 1, Size: 20,
		}, nil
	}
	c, w := createTestGinContext("/api/v1/members/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.ListTransfers(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_StatusFilterPassed() {
	var capturedStatus string
	suite.mockSvc.listTransfersFn = func(_ context.Context, _ int64, _ int, _ int, status string) (*service.ListTransfersResult, error) {
		capturedStatus = status
		return &service.ListTransfersResult{Items: []service.TransferRequestInfo{}, Page: 1, Size: 20}, nil
	}
	c, w := createTestGinContext("/api/v1/members/transfers/list?status=pending", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.ListTransfers(c)
	assertBizResponse(suite.T(), w, 0, "")
	assert.Equal(suite.T(), "pending", capturedStatus)
}

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_InvalidStatusIgnored() {
	var capturedStatus string
	suite.mockSvc.listTransfersFn = func(_ context.Context, _ int64, _ int, _ int, status string) (*service.ListTransfersResult, error) {
		capturedStatus = status
		return &service.ListTransfersResult{Items: []service.TransferRequestInfo{}, Page: 1, Size: 20}, nil
	}
	c, w := createTestGinContext("/api/v1/members/transfers/list?status=whatever", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.ListTransfers(c)
	assertBizResponse(suite.T(), w, 0, "")
	assert.Equal(suite.T(), "", capturedStatus)
}

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_EmptyResult() {
	suite.mockSvc.listTransfersFn = func(context.Context, int64, int, int, string) (*service.ListTransfersResult, error) {
		return &service.ListTransfersResult{Items: []service.TransferRequestInfo{}, Page: 1, Size: 20}, nil
	}
	c, w := createTestGinContext("/api/v1/members/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.ListTransfers(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestListTransfers_QueryFailed() {
	suite.mockSvc.listTransfersFn = func(context.Context, int64, int, int, string) (*service.ListTransfersResult, error) {
		return nil, svcErr(500, "查询失败")
	}
	c, w := createTestGinContext("/api/v1/members/transfers/list", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.ListTransfers(c)
	assertBizResponse(suite.T(), w, 500, "")
}

// ============================================================================
// Batch Accept/Reject Transfers Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestBatchAcceptTransfers_Success() {
	c, w := createTestGinContext("/api/v1/members/transfers/batch-accept", "POST", map[string]interface{}{
		"transfer_ids": []int64{1, 2, 3},
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BatchAcceptTransfers(c)
	assertBizResponse(suite.T(), w, 0, "已批准 3 项")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBatchAcceptTransfers_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/transfers/batch-accept", "POST", map[string]interface{}{
		"invalid": "field",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BatchAcceptTransfers(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBatchAcceptTransfers_PartialFailure() {
	suite.mockSvc.transferAcceptFn = func(_ context.Context, _ int64, transferID int64) error {
		if transferID == 2 {
			return svcErr(409, "该申请已被处理")
		}
		return nil
	}
	c, w := createTestGinContext("/api/v1/members/transfers/batch-accept", "POST", map[string]interface{}{
		"transfer_ids": []int64{1, 2, 3},
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BatchAcceptTransfers(c)
	assertBizResponse(suite.T(), w, 0, "已批准 2 项")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBatchAcceptTransfers_AllFailed() {
	suite.mockSvc.transferAcceptFn = func(context.Context, int64, int64) error {
		return svcErr(409, "该申请已被处理")
	}
	c, w := createTestGinContext("/api/v1/members/transfers/batch-accept", "POST", map[string]interface{}{
		"transfer_ids": []int64{1, 2},
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BatchAcceptTransfers(c)
	assertBizResponse(suite.T(), w, 409, "该申请已被处理")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBatchRejectTransfers_Success() {
	c, w := createTestGinContext("/api/v1/members/transfers/batch-reject", "POST", map[string]interface{}{
		"transfer_ids": []int64{1, 2}, "reason": "Batch cleanup",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BatchRejectTransfers(c)
	assertBizResponse(suite.T(), w, 0, "已拒绝 2 项")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBatchRejectTransfers_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/transfers/batch-reject", "POST", map[string]interface{}{
		"transfer_ids": []int64{},
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BatchRejectTransfers(c)
	assertBizResponse(suite.T(), w, 400, "")
}

// ============================================================================
// Get User By Email Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestGetUserByEmail_Success() {
	suite.mockSvc.getUserByEmailFn = func(_ context.Context, _ int64, email string) (*service.UserLookupResult, error) {
		return &service.UserLookupResult{
			UserID: 10, Email: email, Nickname: "User10",
			Memberships: []service.UserOrgInfo{{OrganizationID: 100, OrgName: "Org A"}},
		}, nil
	}
	c, w := createTestGinContext("/api/v1/members/users/by-email?email=user10@example.com", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.GetUserByEmail(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestGetUserByEmail_MissingEmail() {
	c, w := createTestGinContext("/api/v1/members/users/by-email", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.GetUserByEmail(c)
	assertBizResponse(suite.T(), w, 400, "请输入邮箱")
}

func (suite *MemberLifecycleHandlerTestSuite) TestGetUserByEmail_NotFound() {
	suite.mockSvc.getUserByEmailFn = func(context.Context, int64, string) (*service.UserLookupResult, error) {
		return nil, svcErr(404, "该邮箱未注册")
	}
	c, w := createTestGinContext("/api/v1/members/users/by-email?email=nobody@example.com", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.GetUserByEmail(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestGetUserByEmail_Forbidden() {
	suite.mockSvc.getUserByEmailFn = func(context.Context, int64, string) (*service.UserLookupResult, error) {
		return nil, svcErr(403, "无权查询用户信息")
	}
	c, w := createTestGinContext("/api/v1/members/users/by-email?email=user10@example.com", "GET", nil)
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.GetUserByEmail(c)
	assertBizResponse(suite.T(), w, 403, "")
}

// ============================================================================
// Bulk Add Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_Success() {
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10, 20, 30}, OrganizationID: 100, MembershipType: "full",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", map[string]interface{}{
		"user_ids": []int64{10}, // missing organization_id
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_OrganizationNotFound() {
	suite.mockSvc.bulkAddFn = func(context.Context, int64, int64, service.BulkAddParams) (*service.BulkAddResult, error) {
		return nil, svcErr(404, "组织不存在")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10}, OrganizationID: 99999,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_OrganizationNotInTenant() {
	suite.mockSvc.bulkAddFn = func(context.Context, int64, int64, service.BulkAddParams) (*service.BulkAddResult, error) {
		return nil, svcErr(403, "无权操作此组织")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10}, OrganizationID: 100,
	})
	setAuthClaimsInContext(c, 1, true, 2)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 403, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_InvalidMembershipType() {
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10}, OrganizationID: 100, MembershipType: "invalid",
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	// Handler only defaults empty string to "full"; invalid types pass through
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_SkipExistingMembers() {
	suite.mockSvc.bulkAddFn = func(context.Context, int64, int64, service.BulkAddParams) (*service.BulkAddResult, error) {
		return &service.BulkAddResult{OrganizationID: 100, AddedCount: 1}, nil
	}
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10, 20}, OrganizationID: 100,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_ReactivateInactive() {
	suite.mockSvc.bulkAddFn = func(context.Context, int64, int64, service.BulkAddParams) (*service.BulkAddResult, error) {
		return &service.BulkAddResult{OrganizationID: 100, AddedCount: 1}, nil
	}
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10}, OrganizationID: 100,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_MissingTenantContext() {
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{10}, OrganizationID: 100,
	})
	setAuthWithoutTenant(c, 1, true)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 403, "tenant context missing")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkAdd_UserNotFound() {
	suite.mockSvc.bulkAddFn = func(context.Context, int64, int64, service.BulkAddParams) (*service.BulkAddResult, error) {
		return nil, svcErr(404, "用户不存在")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-add", "POST", BulkAddRequest{
		UserIDs: []int64{99999}, OrganizationID: 100,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkAdd(c)
	assertBizResponse(suite.T(), w, 404, "")
}

// ============================================================================
// Bulk Transfer Tests
// ============================================================================

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_Success() {
	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", BulkTransferRequest{
		MembershipIDs: []int64{1, 2, 3}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkTransfer(c)
	assertBizResponse(suite.T(), w, 0, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_InvalidRequest() {
	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", map[string]interface{}{
		"membership_ids": []int64{1}, // missing target_org_id
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkTransfer(c)
	assertBizResponse(suite.T(), w, 400, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_MembershipsNotFound() {
	suite.mockSvc.bulkTransferFn = func(context.Context, int64, service.BulkTransferParams) (*service.BulkTransferResult, error) {
		return nil, svcErr(404, "会员关系不存在")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", BulkTransferRequest{
		MembershipIDs: []int64{99999}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkTransfer(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_CrossTenantNotSupported() {
	suite.mockSvc.bulkTransferFn = func(context.Context, int64, service.BulkTransferParams) (*service.BulkTransferResult, error) {
		return nil, svcErr(409, "跨租户转移不支持")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", BulkTransferRequest{
		MembershipIDs: []int64{1, 2}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkTransfer(c)
	assertBizResponse(suite.T(), w, 409, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_TargetOrgNotFound() {
	suite.mockSvc.bulkTransferFn = func(context.Context, int64, service.BulkTransferParams) (*service.BulkTransferResult, error) {
		return nil, svcErr(404, "目标组织不存在")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", BulkTransferRequest{
		MembershipIDs: []int64{1}, TargetOrgID: 99999,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkTransfer(c)
	assertBizResponse(suite.T(), w, 404, "")
}

func (suite *MemberLifecycleHandlerTestSuite) TestBulkTransfer_TargetOrgDifferentTenant() {
	suite.mockSvc.bulkTransferFn = func(context.Context, int64, service.BulkTransferParams) (*service.BulkTransferResult, error) {
		return nil, svcErr(403, "目标组织属于不同租户")
	}
	c, w := createTestGinContext("/api/v1/members/bulk-transfer", "POST", BulkTransferRequest{
		MembershipIDs: []int64{1}, TargetOrgID: 200,
	})
	setAuthClaimsInContext(c, 1, true, 1)
	suite.handler.BulkTransfer(c)
	assertBizResponse(suite.T(), w, 403, "")
}
