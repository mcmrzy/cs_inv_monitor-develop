package handler

import (
	"context"
	"errors"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// ==================== Request/Response Models ====================

// AddMemberRequest represents a request to add an existing user to an organization
type AddMemberRequest struct {
	UserID         int64      `json:"user_id" binding:"required"`
	OrganizationID int64      `json:"organization_id" binding:"required"`
	MembershipType string     `json:"membership_type" default:"full"`
	RoleIDs        []int      `json:"role_ids"`
	ExpiresAt      *time.Time `json:"expires_at"`
}

// UpdateMembershipRequest represents a request to update membership details
type UpdateMembershipRequest struct {
	RoleIDs        *[]int     `json:"role_ids"`
	Status         *string    `json:"status"`
	ExpiresAt      *time.Time `json:"expires_at"`
	MembershipType *string    `json:"membership_type"`
}

// UpdateMemberRoleRequest represents a request to set a member's role (single identity)
type UpdateMemberRoleRequest struct {
	Role string `json:"role" binding:"required"`
}

// RemoveMemberRequest represents a request to remove a member
type RemoveMemberRequest struct {
	Reason string `json:"reason"`
}

// DeactivateMemberRequest represents a request to deactivate a member
type DeactivateMemberRequest struct {
	Reason string `json:"reason"`
}

// TransferInitiateRequest represents a request to initiate member transfer
type TransferInitiateRequest struct {
	MembershipIDs []int64 `json:"membership_ids" binding:"required"`
	TargetOrgID   int64   `json:"target_org_id" binding:"required"`
	Reason        string  `json:"reason"`
}

// BulkAddRequest represents a bulk add operation request
type BulkAddRequest struct {
	UserIDs        []int64    `json:"user_ids" binding:"required,min=1,max=100"`
	OrganizationID int64      `json:"organization_id" binding:"required"`
	MembershipType string     `json:"membership_type" default:"full"`
	RoleIDs        []int      `json:"role_ids"`
	ExpiresAt      *time.Time `json:"expires_at"`
}

// BulkTransferRequest represents a bulk transfer operation
type BulkTransferRequest struct {
	MembershipIDs []int64 `json:"membership_ids" binding:"required,min=1,max=100"`
	TargetOrgID   int64   `json:"target_org_id" binding:"required"`
	Reason        string  `json:"reason"`
}

// TransferApprovalRequest represents a request to accept/reject transfer
type TransferApprovalRequest struct {
	Approved bool   `json:"approved" binding:"required"`
	Reason   string `json:"reason"` // required if rejected
}

// MemberLifecycleResponse is a common response structure
type MemberLifecycleResponse struct {
	Message          string `json:"message"`
	OrganizationID   int64  `json:"organization_id,omitempty"`
	UserID           int64  `json:"user_id,omitempty"`
	MembershipID     int64  `json:"membership_id,omitempty"`
	TransferredCount int    `json:"transferred_count,omitempty"`
}

// ==================== Service Interface ====================

// MemberLifecycleServiceInterface defines the service operations used by the handler.
// This interface enables unit testing with mock service implementations.
// The concrete *service.MemberLifecycleService satisfies this interface.
type MemberLifecycleServiceInterface interface {
	AddMember(ctx context.Context, actorUserID int64, tenantID int64, req service.AddMemberParams) (*service.AddMemberResult, error)
	UpdateMembership(ctx context.Context, actorUserID int64, tenantID int64, membershipID int64, req service.UpdateMembershipParams) error
	RemoveMember(ctx context.Context, actorUserID int64, membershipID int64, reason string) error
	DeactivateMember(ctx context.Context, actorUserID int64, membershipID int64, reason string) error
	ReactivateMember(ctx context.Context, actorUserID int64, membershipID int64) error
	TransferInitiate(ctx context.Context, actorUserID int64, membershipIDs []int64, targetOrgID int64, reason string) (*service.TransferResult, error)
	TransferAccept(ctx context.Context, actorUserID int64, transferID int64) error
	TransferReject(ctx context.Context, actorUserID int64, transferID int64, reason string) error
	ListTransfers(ctx context.Context, userID int64) ([]service.PendingTransferInfo, error)
	ListMembers(ctx context.Context, orgID int64, page, pageSize int, roleFilter string) (*service.ListMembersResult, error)
	BulkAdd(ctx context.Context, actorUserID int64, tenantID int64, req service.BulkAddParams) (*service.BulkAddResult, error)
	BulkTransfer(ctx context.Context, actorUserID int64, req service.BulkTransferParams) (*service.BulkTransferResult, error)
	UpdateMemberRole(ctx context.Context, actorUserID int64, tenantID int64, membershipID int64, role string) error
}

// ==================== Handler Struct ====================

// MemberLifecycleHandler handles member lifecycle operations
type MemberLifecycleHandler struct {
	svc MemberLifecycleServiceInterface
}

// NewMemberLifecycleHandler creates a new member lifecycle handler instance
func NewMemberLifecycleHandler(svc MemberLifecycleServiceInterface) *MemberLifecycleHandler {
	return &MemberLifecycleHandler{svc: svc}
}

// handleServiceError maps a service error to an HTTP response
func handleServiceError(c *gin.Context, err error) {
	var svcErr *service.MemberServiceError
	if errors.As(err, &svcErr) {
		response.Error(c, svcErr.Code, svcErr.Message)
		return
	}
	response.Error(c, 500, "内部服务器错误")
}

// ==================== Add Member Endpoint ====================

// AddMember handles POST /api/v1/members/add - Add existing user to organization
func (h *MemberLifecycleHandler) AddMember(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req AddMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if req.MembershipType == "" {
		req.MembershipType = "full"
	}

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	result, err := h.svc.AddMember(c.Request.Context(), userID, tenantID, service.AddMemberParams{
		UserID:         req.UserID,
		OrganizationID: req.OrganizationID,
		MembershipType: req.MembershipType,
		ExpiresAt:      req.ExpiresAt,
	})
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.Success(c, MemberLifecycleResponse{
		Message:        "成员添加成功",
		OrganizationID: result.OrganizationID,
		UserID:         result.UserID,
	})
}

// ==================== Update Membership Endpoint ====================

// UpdateMembership handles PUT /api/v1/memberships/:id/update - Update membership details
func (h *MemberLifecycleHandler) UpdateMembership(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "无效的会员关系 ID")
		return
	}

	var req UpdateMembershipRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	err = h.svc.UpdateMembership(c.Request.Context(), userID, tenantID, membershipID, service.UpdateMembershipParams{
		Status:    req.Status,
		ExpiresAt: req.ExpiresAt,
	})
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "成员信息已更新", gin.H{
		"membership_id": membershipID,
	})
}

// ==================== Update Member Role Endpoint ====================

// UpdateMemberRole handles PUT /api/v1/members/memberships/:id/role - Set member role (single identity)
func (h *MemberLifecycleHandler) UpdateMemberRole(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "无效的会员关系 ID")
		return
	}

	var req UpdateMemberRoleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	err = h.svc.UpdateMemberRole(c.Request.Context(), userID, tenantID, membershipID, req.Role)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "成员角色已更新", gin.H{
		"membership_id": membershipID,
		"role":          req.Role,
	})
}

// ==================== Remove Member Endpoint ====================

// RemoveMember handles DELETE /api/v1/memberships/:id/remove - Remove member from organization
func (h *MemberLifecycleHandler) RemoveMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "无效的会员关系 ID")
		return
	}

	var req RemoveMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	err = h.svc.RemoveMember(c.Request.Context(), userID, membershipID, req.Reason)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "成员已从组织中移除", gin.H{
		"membership_id": membershipID,
	})
}

// ==================== Deactivate/Reactivate Endpoints ====================

// DeactivateMember handles PATCH /api/v1/memberships/:id/deactivate - Soft deactivate member
func (h *MemberLifecycleHandler) DeactivateMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "无效的会员关系 ID")
		return
	}

	var req DeactivateMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	err = h.svc.DeactivateMember(c.Request.Context(), userID, membershipID, req.Reason)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "成员已停用", gin.H{
		"membership_id": membershipID,
	})
}

// ReactivateMember handles PATCH /api/v1/memberships/:id/reactivate - Reactivate deactivated member
func (h *MemberLifecycleHandler) ReactivateMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "无效的会员关系 ID")
		return
	}

	err = h.svc.ReactivateMember(c.Request.Context(), userID, membershipID)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "成员已恢复活跃", gin.H{
		"membership_id": membershipID,
	})
}

// ==================== List Members Endpoint ====================

// ListMembers handles GET /api/v1/organizations/:id/members - List members of an organization
func (h *MemberLifecycleHandler) ListMembers(c *gin.Context) {
	orgID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "20"))
	roleFilter := c.Query("role") // optional role filter
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	result, err := h.svc.ListMembers(c.Request.Context(), orgID, page, pageSize, roleFilter)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.Page(c, result.Items, result.Total, result.Page, result.Size)
}

// ==================== Transfer Flow ====================

// TransferInitiate handles POST /api/v1/members/transfer/initiate - Initiate transfer to different org
func (h *MemberLifecycleHandler) TransferInitiate(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req TransferInitiateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	result, err := h.svc.TransferInitiate(c.Request.Context(), userID, req.MembershipIDs, req.TargetOrgID, req.Reason)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.Success(c, MemberLifecycleResponse{
		Message:          "成员转移完成",
		OrganizationID:   result.OrganizationID,
		TransferredCount: result.TransferredCount,
	})
}

// TransferAccept handles POST /api/v1/members/transfer/accept - Accept transfer request
func (h *MemberLifecycleHandler) TransferAccept(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		TransferID int64 `json:"transfer_id" binding:"required"`
		Approved   bool  `json:"approved"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if !req.Approved {
		response.Error(c, 400, "拒绝转移需要使用 transfer/reject 接口")
		return
	}

	err := h.svc.TransferAccept(c.Request.Context(), userID, req.TransferID)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "转移请求已接受", map[string]interface{}{
		"transfer_id": req.TransferID,
		"status":      "accepted",
	})
}

// TransferReject handles POST /api/v1/members/transfer/reject - Reject transfer request
func (h *MemberLifecycleHandler) TransferReject(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		TransferID int64  `json:"transfer_id" binding:"required"`
		Approved   bool   `json:"approved"`
		Reason     string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	if req.Approved {
		response.Error(c, 400, "拒绝转移必须设置 approved=false")
		return
	}

	err := h.svc.TransferReject(c.Request.Context(), userID, req.TransferID, req.Reason)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	response.SuccessWithMessage(c, "转移请求已拒绝", map[string]interface{}{
		"transfer_id": req.TransferID,
		"reason":      req.Reason,
	})
}

// ListTransfers handles GET /api/v1/members/transfers/list - List pending transfers
func (h *MemberLifecycleHandler) ListTransfers(c *gin.Context) {
	userID := middleware.GetUserID(c)

	transfers, err := h.svc.ListTransfers(c.Request.Context(), userID)
	if err != nil {
		handleServiceError(c, err)
		return
	}

	if transfers == nil {
		transfers = []service.PendingTransferInfo{}
	}

	response.Page(c, transfers, int64(len(transfers)), 1, 10)
}

// ==================== Bulk Operations ====================

// BulkAdd handles POST /api/v1/members/bulk-add - Add multiple users to org asynchronously
func (h *MemberLifecycleHandler) BulkAdd(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BulkAddRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	result, err := h.svc.BulkAdd(c.Request.Context(), userID, tenantID, service.BulkAddParams{
		UserIDs:        req.UserIDs,
		OrganizationID: req.OrganizationID,
		MembershipType: req.MembershipType,
		ExpiresAt:      req.ExpiresAt,
	})
	if err != nil {
		handleServiceError(c, err)
		return
	}

	if result.IsAsync {
		response.Success(c, map[string]interface{}{
			"message":     "批量添加任务已创建，正在后台处理",
			"job_id":      result.JobID,
			"status_url":  result.StatusURL,
			"ws_url":      result.WSURL,
			"total_items": result.TotalItems,
		})
		return
	}

	response.Success(c, MemberLifecycleResponse{
		Message:          "批量添加完成",
		OrganizationID:   result.OrganizationID,
		TransferredCount: result.AddedCount,
	})
}

// BulkTransfer handles POST /api/v1/members/bulk-transfer - Transfer multiple members asynchronously
func (h *MemberLifecycleHandler) BulkTransfer(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BulkTransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	result, err := h.svc.BulkTransfer(c.Request.Context(), userID, service.BulkTransferParams{
		MembershipIDs: req.MembershipIDs,
		TargetOrgID:   req.TargetOrgID,
		Reason:        req.Reason,
	})
	if err != nil {
		handleServiceError(c, err)
		return
	}

	if result.IsAsync {
		response.Success(c, map[string]interface{}{
			"message":     "批量转移任务已创建，正在后台处理",
			"job_id":      result.JobID,
			"status_url":  result.StatusURL,
			"ws_url":      result.WSURL,
			"total_items": result.TotalItems,
		})
		return
	}

	response.Success(c, MemberLifecycleResponse{
		Message:          "批量转移完成",
		OrganizationID:   result.OrganizationID,
		TransferredCount: result.TransferredCount,
	})
}
