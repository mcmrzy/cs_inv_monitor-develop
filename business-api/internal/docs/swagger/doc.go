// Package swagger Inv-MQTT Multi-Level Channel Platform API documentation
//
// @title Inv-MQTT Multi-Level Channel Platform API
// @version 1.0.0
// @description 光伏逆变器监控系统 - 多级渠道平台 API 参考文档
//
// @description 核心功能:
// @description - **组织管理**: 制造商、代理商、分销商、客户、服务商的多级组织架构
// @description - **邀请系统**: 用户邀请与自动注册
// @description - **设备认领**: 设备唯一性验证与所有权转移
// @description - **成员生命周期**: 成员添加、移除、转移的完整流程
//
// @contact.name CSERGY Smart Energy Platform Support
// @contact.email support@csergy.com
// @license.name Proprietary
// @license.url https://csergy.com/terms
//
// @host api.inv-mqtt.com
// @BasePath /api/v1
// @schemes https
//
// @securitydefinitions.bearer BearerAuth
// @in header
// @name Authorization
// @description JWT token in format "Bearer <token>"
//
// @security BearerAuth
package docs

// ============================================================================
// Organization Handlers
// ============================================================================

// CreateOrganization handles POST /api/v1/organizations - Create organization
// @Summary 创建组织单元
// @Tags Organizations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param CreateOrganizationRequest body CreateOrganizationRequest true "Organization data"
// @Success 201 {object} OrganizationWithChildren "Organization created"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 403 {object} ErrorResponse "Forbidden for end users"
// @Failure 409 {object} ErrorResponse "Conflict - duplicate or hierarchy violation"
// @Router /organizations [post]
// @Example CreateOrganizationRequest {"name": "Tech Corp", "type": "agent", "parent_id": null}
func CreateOrganization() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// ListOrganizations handles GET /api/v1/organizations - List organizations
// @Summary 列出组织单元
// @Tags Organizations
// @Produce json
// @Security BearerAuth
// @Param page query integer false "Page number (from 1)" default(1) minimum(1)
// @Param page_size query integer false "Items per page (max 100)" default(20) minimum(1) maximum(100)
// @Param type query string false "Filter by organization type" Enum(manufacturer, agent, distributor, customer, service_partner)
// @Param status query string false "Filter by organization status" Enum(active, disabled, quarantined)
// @Success 200 {object} PaginatedOrganizationList "Organization list"
// @Failure 403 {object} ErrorResponse "Forbidden access"
// @Router /organizations [get]
// @Example PaginatedOrganizationList {"organizations": [{"id": 1, "name": "Tech Corp", "type": "agent"}], "total": 25, "page": 1, "page_size": 20}
func ListOrganizations() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// GetOrganization handles GET /api/v1/organizations/:id - Get organization details
// @Summary 获取组织详情
// @Tags Organizations
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Organization ID"
// @Success 200 {object} OrganizationWithChildren "Organization details"
// @Failure 404 {object} ErrorResponse "Organization not found"
// @Failure 403 {object} ErrorResponse "Access denied"
// @Router /organizations/{id} [get]
func GetOrganization() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// UpdateOrganization handles PUT /api/v1/organizations/:id - Update organization
// @Summary 更新组织信息
// @Tags Organizations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Organization ID"
// @Param UpdateOrganizationRequest body UpdateOrganizationRequest true "Organization data"
// @Success 200 {object} UpdateResponse "Update successful"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Organization not found"
// @Failure 403 {object} ErrorResponse "Permission denied"
// @Router /organizations/{id} [put]
// @Example UpdateOrganizationRequest {"name": "Tech Corp (Updated)"}
func UpdateOrganization() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// DeleteOrganization handles DELETE /api/v1/organizations/:id - Soft delete organization
// @Summary 删除组织 (软删除)
// @Tags Organizations
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Organization ID"
// @Success 200 {object} DeleteResponse "Delete successful"
// @Failure 400 {object} ErrorResponse "Cannot delete organization with children"
// @Failure 404 {object} ErrorResponse "Organization not found"
// @Router /organizations/{id} [delete]
func DeleteOrganization() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// MoveOrganization handles POST /api/v1/organizations/:id/move - Move organization
// @Summary 移动组织到新父级
// @Tags Organizations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Organization ID"
// @Param MoveOrganizationRequest body MoveOrganizationRequest true "Target parent"
// @Success 200 {object} MoveResponse "Move successful"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Organization not found"
// @Failure 409 {object} ErrorResponse "Circular reference conflict"
// @Router /organizations/{id}/move [post]
// @Example MoveOrganizationRequest {"parent_id": 5}
func MoveOrganization() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// ToggleOrganizationStatus handles PATCH /api/v1/organizations/:id/status - Toggle status
// @Summary 切换组织状态
// @Tags Organizations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Organization ID"
// @Param ToggleStatusRequest body ToggleStatusRequest true "Status update"
// @Success 200 {object} StatusResponse "Status updated"
// @Failure 400 {object} ErrorResponse "Invalid status value"
// @Failure 404 {object} ErrorResponse "Organization not found"
// @Router /organizations/{id}/status [patch]
// @Example ToggleStatusRequest {"status": "disabled"}
func ToggleOrganizationStatus() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// GetOrganizationTree handles GET /api/v1/organizations/:id/tree - Get subtree recursively
// @Summary 获取组织树形结构
// @Tags Organizations
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Organization ID"
// @Success 200 {object} OrgTreeResponse "Organization tree structure"
// @Failure 404 {object} ErrorResponse "Organization not found"
// @Router /organizations/{id}/tree [get]
func GetOrganizationTree() {
	// Implementation in business-api/internal/handler/organization_handler.go
}

// ============================================================================
// Invitation Handlers
// ============================================================================

// CreateInvitation handles POST /api/v1/invitations/create - Send invitation
// @Summary 发送邀请
// @Tags Invitations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param CreateInvitationRequest body CreateInvitationRequest true "Invitation data"
// @Success 200 {object} InvitationResponse "Invitation sent"
// @Failure 400 {object} ErrorResponse "Invalid request or quota exceeded"
// @Failure 403 {object} ErrorResponse "Insufficient permissions"
// @Failure 409 {object} ErrorResponse "Email already has pending invitation"
// @Router /invitations/create [post]
// @Example CreateInvitationRequest {"email": "newuser@example.com", "role_id": 3, "organization_id": 123, "expires_hours": 168}
func CreateInvitation() {
	// Implementation in business-api/internal/handler/invitation_handler.go
}

// ListInvitations handles GET /api/v1/invitations/list - List pending invitations
// @Summary 列出邀请
// @Tags Invitations
// @Produce json
// @Security BearerAuth
// @Param status query string false "Filter by status" Enum(pending, used, expired, revoked)
// @Param email query string false "Filter by email"
// @Param organization_id query integer false "Filter by organization"
// @Param page query integer false "Page number" default(1)
// @Param page_size query integer false "Items per page" default(20) maximum(100)
// @Success 200 {object} PaginatedInvitationList "Invitation list"
// @Router /invitations/list [get]
func ListInvitations() {
	// Implementation in business-api/internal/handler/invitation_handler.go
}

// RevokeInvitation handles DELETE /api/v1/invitations/:id/revoke - Cancel invitation
// @Summary 撤销邀请
// @Tags Invitations
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Invitation ID"
// @Success 200 {object} DeleteResponse "Revoked successfully"
// @Failure 400 {object} ErrorResponse "Non-pending invitation cannot be revoked"
// @Failure 404 {object} ErrorResponse "Invitation not found"
// @Failure 403 {object} ErrorResponse "Insufficient permissions"
// @Router /invitations/{id}/revoke [delete]
func RevokeInvitation() {
	// Implementation in business-api/internal/handler/invitation_handler.go
}

// GetInvitationDetails handles GET /api/v1/invitations/:id/details - Get invite details
// @Summary 获取邀请详情
// @Tags Invitations
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Invitation ID"
// @Success 200 {object} InvitationResponse "Invitation details"
// @Failure 404 {object} ErrorResponse "Invitation not found"
// @Failure 403 {object} ErrorResponse "Access denied"
// @Router /invitations/{id}/details [get]
func GetInvitationDetails() {
	// Implementation in business-api/internal/handler/invitation_handler.go
}

// AcceptInvitation handles POST /api/v1/invitations/accept - Accept invitation (PUBLIC)
// @Summary 接受邀请并自动注册
// @Tags Invitations
// @Accept json
// @Produce json
// @Param AcceptInvitationRequest body AcceptInvitationRequest true "Invitation code and registration data"
// @Success 200 {object} AcceptInvitationResponse "Registration successful with auto-login"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 401 {object} ErrorResponse "Invitation code invalid, expired, or used"
// @Failure 409 {object} ErrorResponse "Email or phone already registered"
// @Router /invitations/accept [post]
// @Example AcceptInvitationRequest {"invitation_code": "ABC12345", "password": "SecurePass123!", "phone": "+8613800138000", "nickname": "New User"}
func AcceptInvitation() {
	// Implementation in business-api/internal/handler/invitation_handler.go
	// NOTE: This is a PUBLIC endpoint - no JWT authentication required
}

// ============================================================================
// Device Claim/Transfer Handlers
// ============================================================================

// GenerateClaimCode handles POST /api/v1/devices/claim-code/generate - Generate claim code
// @Summary 生成设备认领码
// @Tags Devices
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param GenerateClaimCodeRequest body GenerateClaimCodeRequest true "Device SN and expiration"
// @Success 200 {object} GenerateClaimCodeResponse "Claim code generated"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 403 {object} ErrorResponse "No permission to manage device"
// @Failure 404 {object} ErrorResponse "Device not found"
// @Failure 409 {object} ErrorResponse "Device already claimed"
// @Router /devices/claim-code/generate [post]
// @Example GenerateClaimCodeRequest {"sn": "SN202407220001", "expires_hours": 168}
func GenerateClaimCode() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// VerifyClaimCode handles POST /api/v1/devices/claim-code/verify - Verify claim code
// @Summary 验证认领码
// @Tags Devices
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param VerifyClaimCodeRequest body VerifyClaimCodeRequest true "Claim code to verify"
// @Success 200 {object} VerifyClaimCodeResponse "Claim code valid"
// @Failure 404 {object} ErrorResponse "Claim code invalid"
// @Failure 403 {object} ErrorResponse "Claim code expired"
// @Router /devices/claim-code/verify [post]
// @Example VerifyClaimCodeRequest {"claim_code": "A1B2C3D4E5F6G7H8"}
func VerifyClaimCode() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// ClaimDevice handles POST /api/v1/devices/:sn/claim - Claim device
// @Summary 认领设备
// @Tags Devices
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param sn path string true "Device serial number"
// @Param ClaimDeviceRequest body ClaimDeviceRequest true "Claim data"
// @Success 200 {object} ClaimDeviceResponse "Device claimed successfully"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 403 {object} ErrorResponse "Invalid claim code or cross-tenant restriction"
// @Failure 404 {object} ErrorResponse "Device or claim code not found"
// @Failure 409 {object} ErrorResponse "Device already claimed"
// @Router /devices/{sn}/claim [post]
// @Example ClaimDeviceRequest {"sn": "SN202407220001", "claim_code": "A1B2C3D4E5F6G7H8"}
func ClaimDevice() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// RequestTransfer handles POST /api/v1/devices/:sn/request-transfer - Initiate ownership transfer
// @Summary 发起设备所有权转移
// @Tags Devices
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param sn path string true "Device serial number"
// @Param TransferRequestRequest body TransferRequestRequest true "Transfer request data"
// @Success 200 {object} TransferRequestResponse "Transfer request submitted"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 403 {object} ErrorResponse "Not device owner or same tenant"
// @Failure 404 {object} ErrorResponse "Device not found"
// @Failure 409 {object} ErrorResponse "Already has pending transfer request"
// @Router /devices/{sn}/request-transfer [post]
// @Example TransferRequestRequest {"device_sn": "SN202407220001", "to_tenant_id": 5, "reason": "Business adjustment"}
func RequestTransfer() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// ListTransfers handles GET /api/v1/devices/transfers/list - List transfer requests
// @Summary 列出转移请求
// @Tags Devices
// @Produce json
// @Security BearerAuth
// @Param status query string false "Filter by status" Enum(pending, approved, rejected, cancelled)
// @Param type query string false "Scope filter" Enum(mine, all)
// @Success 200 {object} ListTransfersResponse "Transfer list"
// @Router /devices/transfers/list [get]
func ListTransfers() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// ApproveTransfer handles POST /api/v1/devices/transfers/:id/approve - Approve transfer
// @Summary 批准转移请求
// @Tags Devices
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Transfer request ID"
// @Param TransferApprovalRequest body TransferApprovalRequest true "Approval data"
// @Success 200 {object} TransferApprovalResponse "Transfer approved"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 403 {object} ErrorResponse "Not transfer source or already processed"
// @Failure 404 {object} ErrorResponse "Transfer request not found"
// @Failure 409 {object} ErrorResponse "Transfer status does not allow approval"
// @Router /devices/transfers/{id}/approve [post]
// @Example TransferApprovalRequest {"approved": true, "reason": ""}
func ApproveTransfer() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// RejectTransfer handles POST /api/v1/devices/transfers/:id/reject - Reject transfer
// @Summary 拒绝转移请求
// @Tags Devices
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Transfer request ID"
// @Param TransferApprovalRequest body TransferApprovalRequest true "Rejection data (requires reason)"
// @Success 200 {object} TransferApprovalResponse "Transfer rejected"
// @Failure 400 {object} ErrorResponse "Invalid request or missing reason"
// @Failure 403 {object} ErrorResponse "No permission to reject"
// @Failure 404 {object} ErrorResponse "Transfer request not found"
// @Router /devices/transfers/{id}/reject [post]
// @Example TransferApprovalRequest {"approved": false, "reason": "Quality issue detected"}
func RejectTransfer() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// CancelTransfer handles POST /api/v1/devices/transfers/:id/cancel - Cancel transfer
// @Summary 取消转移请求
// @Tags Devices
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Transfer request ID"
// @Success 200 {object} TransferApprovalResponse "Transfer cancelled"
// @Failure 403 {object} ErrorResponse "Not requester or no admin permissions"
// @Failure 404 {object} ErrorResponse "Transfer request not found"
// @Failure 409 {object} ErrorResponse "Transfer status does not allow cancellation"
// @Router /devices/transfers/{id}/cancel [post]
func CancelTransfer() {
	// Implementation in business-api/internal/handler/device_claim_transfer_handler.go
}

// ============================================================================
// Member Lifecycle Handlers
// ============================================================================

// AddMember handles POST /api/v1/members/add - Add member to organization
// @Summary 添加成员到组织
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param AddMemberRequest body AddMemberRequest true "Member data"
// @Success 200 {object} MemberLifecycleResponse "Member added successfully"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "User or organization not found"
// @Failure 409 {object} ErrorResponse "Already active member or quota exceeded"
// @Router /members/add [post]
// @Example AddMemberRequest {"user_id": 12345, "organization_id": 678, "membership_type": "full", "role_ids": [3, 5]}
func AddMember() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// UpdateMembership handles PUT /api/v1/memberships/:id/update - Update membership
// @Summary 更新成员关系
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Membership ID"
// @Param UpdateMembershipRequest body UpdateMembershipRequest true "Update data"
// @Success 200 {object} UpdateResponse "Update successful"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Membership not found"
// @Router /memberships/{id}/update [put]
func UpdateMembership() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// RemoveMember handles DELETE /api/v1/memberships/:id/remove - Remove member (soft delete)
// @Summary 移除成员 (软删除)
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Membership ID"
// @Param RemoveMemberRequest body RemoveMemberRequest true "Reason"
// @Success 200 {object} RemoveMemberResponse "Member removed"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Membership not found"
// @Router /memberships/{id}/remove [delete]
// @Example RemoveMemberRequest {"reason": "Project completed"}
func RemoveMember() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// DeactivateMember handles PATCH /api/v1/memberships/:id/deactivate - Deactivate member
// @Summary 停用成员
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Membership ID"
// @Param DeactivateMemberRequest body DeactivateMemberRequest true "Reason"
// @Success 200 {object} DeactivateResponse "Member deactivated"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Membership not found"
// @Failure 409 {object} ErrorResponse "Member already inactive"
// @Router /memberships/{id}/deactivate [patch]
// @Example DeactivateMemberRequest {"reason": "Temporary suspension"}
func DeactivateMember() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// ReactivateMember handles PATCH /api/v1/memberships/:id/reactivate - Reactivate member
// @Summary 恢复成员为活跃状态
// @Tags Members
// @Produce json
// @Security BearerAuth
// @Param id path integer true "Membership ID"
// @Success 200 {object} ActivateResponse "Member reactivated"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Membership not found"
// @Failure 409 {object} ErrorResponse "Member already active"
// @Router /memberships/{id}/reactivate [patch]
func ReactivateMember() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// TransferInitiate handles POST /api/v1/members/transfer/initiate - Initiate transfer
// @Summary 发起成员转移
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param TransferInitiateRequest body TransferInitiateRequest true "Transfer data"
// @Success 200 {object} MemberLifecycleResponse "Transfer completed"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 404 {object} ErrorResponse "Members or target organization not found"
// @Failure 409 {object} ErrorResponse "Cross-tenant or status conflict"
// @Router /members/transfer/initiate [post]
// @Example TransferInitiateRequest {"membership_ids": [123, 456], "target_org_id": 999, "reason": "Business adjustment"}
func TransferInitiate() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// TransferAccept handles POST /api/v1/members/transfer/accept - Accept transfer
// @Summary 接受成员转移
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param TransferApprovalRequest body TransferApprovalRequest true "Approval data"
// @Success 200 {object} TransferAcceptResponse "Transfer accepted"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Router /members/transfer/accept [post]
// @Example TransferApprovalRequest {"approved": true}
func TransferAccept() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// TransferReject handles POST /api/v1/members/transfer/reject - Reject transfer
// @Summary 拒绝成员转移
// @Tags Members
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param TransferApprovalRequest body TransferApprovalRequest true "Rejection data (requires reason)"
// @Success 200 {object} TransferRejectResponse "Transfer rejected"
// @Failure 400 {object} ErrorResponse "Invalid request or missing reason"
// @Router /members/transfer/reject [post]
// @Example TransferApprovalRequest {"approved": false, "reason": "Not suitable for this organization"}
func TransferReject() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// ListMemberTransfers handles GET /api/v1/members/transfers/list - List pending transfers
// @Summary 列出待处理转移
// @Tags Members
// @Produce json
// @Security BearerAuth
// @Param page query integer false "Page number" default(1)
// @Param page_size query integer false "Items per page" default(20) maximum(100)
// @Success 200 {object} PaginatedMemberTransfersResponse "Transfer list"
// @Router /members/transfers/list [get]
func ListMemberTransfers() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// BulkAdd handles POST /api/v1/members/bulk-add - Add multiple users
// @Summary 批量添加成员
// @Tags Bulk Operations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param BulkAddRequest body BulkAddRequest true "Bulk add data"
// @Success 200 {object} MemberLifecycleResponse "Bulk add completed"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 409 {object} ErrorResponse "Partial user not found or quota exceeded"
// @Router /members/bulk-add [post]
// @Example BulkAddRequest {"user_ids": [123, 456, 789], "organization_id": 678, "membership_type": "full"}
func BulkAdd() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// BulkTransfer handles POST /api/v1/members/bulk-transfer - Transfer multiple members
// @Summary 批量转移成员
// @Tags Bulk Operations
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param BulkTransferRequest body BulkTransferRequest true "Bulk transfer data"
// @Success 200 {object} MemberLifecycleResponse "Bulk transfer completed"
// @Failure 400 {object} ErrorResponse "Invalid request"
// @Failure 409 {object} ErrorResponse "Cross-tenant transfer not supported"
// @Router /members/bulk-transfer [post]
// @Example BulkTransferRequest {"membership_ids": [123, 456], "target_org_id": 999}
func BulkTransfer() {
	// Implementation in business-api/internal/handler/member_lifecycle_handler.go
}

// ============================================================================
// Common Types - Documentation only
// ============================================================================

// ErrorResponse represents an error response
// @Description Error response with code and message
type ErrorResponse struct {
	Code    string      `json:"code"`
	Message string      `json:"message"`
	Details interface{} `json:"details,omitempty"`
}

// CreateOrganizationRequest represents a request to create an organization
type CreateOrganizationRequest struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	ParentID *int64 `json:"parent_id,omitempty"`
}

// OrganizationWithChildren represents an organization with child count
type OrganizationWithChildren struct {
	ID              int64   `json:"id"`
	RootTenantID    int64   `json:"root_tenant_id"`
	ParentID        *int64  `json:"parent_id,omitempty"`
	Type            string  `json:"type"`
	Code            string  `json:"code,omitempty"`
	Name            string  `json:"name"`
	Status          string  `json:"status"`
	Version         int64   `json:"version"`
	ChildrenCount   int     `json:"children_count"`
	CreatedAt       string  `json:"created_at"`
	UpdatedAt       string  `json:"updated_at"`
}

// PaginatedOrganizationList represents paginated organization list
type PaginatedOrganizationList struct {
	Organizations []OrganizationWithChildren `json:"organizations"`
	Total         int64                      `json:"total"`
	Page          int                        `json:"page"`
	PageSize      int                        `json:"page_size"`
}

// UpdateResponse represents a generic update response
type UpdateResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

// DeleteResponse represents a generic delete response
type DeleteResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

// StatusResponse represents a status update response
type StatusResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message,omitempty"`
	Data    struct {
		ID     int64  `json:"id"`
		Status string `json:"status"`
	} `json:"data"`
}

// MoveResponse represents a move operation response
type MoveResponse struct {
	Success bool `json:"success"`
	Data    struct {
		ID       int64 `json:"id"`
		ParentID int64 `json:"parent_id"`
		MovedAt  string `json:"moved_at"`
	} `json:"data"`
}

// OrgTreeResponse represents organization tree response
type OrgTreeResponse struct {
	RootOrganization interface{} `json:"root_organization"`
	Subtree          []interface{} `json:"subtree"`
	TotalNodes       int           `json:"total_nodes"`
}

// UpdateOrganizationRequest represents a request to update organization
type UpdateOrganizationRequest struct {
	Name string `json:"name"`
}

// MoveOrganizationRequest represents a request to move organization
type MoveOrganizationRequest struct {
	ParentID int64 `json:"parent_id"`
}

// ToggleStatusRequest represents a request to toggle organization status
type ToggleStatusRequest struct {
	Status string `json:"status"`
}

// CreateInvitationRequest represents a request to create an invitation
type CreateInvitationRequest struct {
	Email          string `json:"email"`
	RoleID         int    `json:"role_id"`
	OrganizationID *int64 `json:"organization_id,omitempty"`
	ExpiresHours   int    `json:"expires_hours"`
}

// InvitationResponse represents invitation details
type InvitationResponse struct {
	ID        int64  `json:"id"`
	Email     string `json:"email"`
	RoleName  string `json:"role_name"`
	TokenHint string `json:"token_hint"`
	ExpiresAt string `json:"expires_at"`
	CreatedBy string `json:"created_by"`
	Status    string `json:"status"`
}

// PaginatedInvitationList represents paginated invitation list
type PaginatedInvitationList struct {
	Total    int         `json:"total"`
	Items    []interface{} `json:"items"`
	Page     int         `json:"page"`
	PageSize int         `json:"page_size"`
}

// AcceptInvitationRequest represents a request to accept invitation
type AcceptInvitationRequest struct {
	InvitationCode string `json:"invitation_code"`
	Password       string `json:"password"`
	Phone          string `json:"phone"`
	Nickname       string `json:"nickname"`
}

// AcceptInvitationResponse represents successful acceptance
type AcceptInvitationResponse struct {
	InvitationID int64       `json:"invitation_id"`
	User         interface{} `json:"user"`
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	ExpiresIn    int64       `json:"expires_in"`
	Permissions  []string    `json:"permissions"`
}

// GenerateClaimCodeRequest represents a request to generate claim code
type GenerateClaimCodeRequest struct {
	SN           string `json:"sn"`
	ExpiresHours int    `json:"expires_hours"`
}

// GenerateClaimCodeResponse represents claim code generation result
type GenerateClaimCodeResponse struct {
	ClaimCode string `json:"claim_code"`
	ExpiresAt string `json:"expires_at"`
	Note      string `json:"note"`
	SN        string `json:"sn"`
}

// VerifyClaimCodeRequest represents a request to verify claim code
type VerifyClaimCodeRequest struct {
	ClaimCode string `json:"claim_code"`
}

// VerifyClaimCodeResponse represents verification result
type VerifyClaimCodeResponse struct {
	Valid         bool   `json:"valid"`
	SN            string `json:"sn"`
	ExpiresAt     string `json:"expires_at"`
	RemainingTime int    `json:"remaining_time"`
}

// ClaimDeviceRequest represents a request to claim device
type ClaimDeviceRequest struct {
	SN        string `json:"sn"`
	ClaimCode string `json:"claim_code"`
	UserID    *int64 `json:"user_id,omitempty"`
}

// ClaimDeviceResponse represents claim result
type ClaimDeviceResponse struct {
	Message   string `json:"message"`
	DeviceSN  string `json:"device_sn"`
	ClaimedBy int64  `json:"claimed_by"`
}

// TransferRequestRequest represents a request to transfer device
type TransferRequestRequest struct {
	DeviceSN   string `json:"device_sn"`
	ToTenantID int64  `json:"to_tenant_id"`
	Reason     string `json:"reason,omitempty"`
}

// TransferRequestResponse represents transfer request result
type TransferRequestResponse struct {
	TransferID int64  `json:"transfer_id"`
	Message    string `json:"message"`
}

// ListTransfersResponse represents transfer list
type ListTransfersResponse struct {
	Transfers []interface{} `json:"transfers"`
	Total     int           `json:"total"`
}

// TransferApprovalRequest represents approval request
type TransferApprovalRequest struct {
	Approved bool   `json:"approved"`
	Reason   string `json:"reason,omitempty"`
}

// TransferApprovalResponse represents approval result
type TransferApprovalResponse struct {
	Message    string `json:"message"`
	TransferID int64  `json:"transfer_id"`
}

// AddMemberRequest represents a request to add member
type AddMemberRequest struct {
	UserID         int64     `json:"user_id"`
	OrganizationID int64     `json:"organization_id"`
	MembershipType string    `json:"membership_type"`
	RoleIDs        []int     `json:"role_ids"`
	ExpiresAt      *string   `json:"expires_at,omitempty"`
}

// UpdateMembershipRequest represents a request to update membership
type UpdateMembershipRequest struct {
	RoleIDs        *[]int   `json:"role_ids,omitempty"`
	Status         *string  `json:"status,omitempty"`
	ExpiresAt      *string  `json:"expires_at,omitempty"`
	MembershipType *string  `json:"membership_type,omitempty"`
}

// RemoveMemberRequest represents a request to remove member
type RemoveMemberRequest struct {
	Reason string `json:"reason"`
}

// DeactivateMemberRequest represents a request to deactivate member
type DeactivateMemberRequest struct {
	Reason string `json:"reason"`
}

// RemoveMemberResponse represents member removal result
type RemoveMemberResponse struct {
	Success bool `json:"success"`
	Message string `json:"message"`
	Data    struct {
		MembershipID int64 `json:"membership_id"`
		UserID       int64 `json:"user_id"`
	} `json:"data"`
}

// ActivateResponse represents member activation
type ActivateResponse struct {
	Success bool `json:"success"`
	Message string `json:"message"`
	Data    struct {
		MembershipID int64 `json:"membership_id"`
	} `json:"data"`
}

// DeactivateResponse represents member deactivation
type DeactivateResponse struct {
	Success bool `json:"success"`
	Message string `json:"message"`
	Data    struct {
		MembershipID int64 `json:"membership_id"`
	} `json:"data"`
}

// TransferInitiateRequest represents a request to initiate transfer
type TransferInitiateRequest struct {
	MembershipIDs []int64 `json:"membership_ids"`
	TargetOrgID   int64   `json:"target_org_id"`
	Reason        string  `json:"reason,omitempty"`
}

// TransferAcceptResponse represents transfer acceptance
type TransferAcceptResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

// TransferRejectResponse represents transfer rejection
type TransferRejectResponse struct {
	Success bool `json:"success"`
	Message string `json:"message"`
	Data    struct {
		Reason string `json:"reason"`
	} `json:"data"`
}

// PaginatedMemberTransfersResponse represents paginated transfer list
type PaginatedMemberTransfersResponse struct {
	PendingTransfers []interface{} `json:"pending_transfers"`
	Total            int           `json:"total"`
	Page             int           `json:"page"`
	PageSize         int           `json:"page_size"`
}

// BulkAddRequest represents bulk add request
type BulkAddRequest struct {
	UserIDs        []int64   `json:"user_ids"`
	OrganizationID int64     `json:"organization_id"`
	MembershipType string    `json:"membership_type"`
	RoleIDs        []int     `json:"role_ids"`
	ExpiresAt      *string   `json:"expires_at,omitempty"`
}

// BulkTransferRequest represents bulk transfer request
type BulkTransferRequest struct {
	MembershipIDs []int64 `json:"membership_ids"`
	TargetOrgID   int64   `json:"target_org_id"`
	Reason        string  `json:"reason,omitempty"`
}

// MemberLifecycleResponse represents member operation result
type MemberLifecycleResponse struct {
	Message          string `json:"message"`
	OrganizationID   int64  `json:"organization_id,omitempty"`
	UserID           int64  `json:"user_id,omitempty"`
	MembershipID     int64  `json:"membership_id,omitempty"`
	TransferredCount int    `json:"transferred_count,omitempty"`
}
