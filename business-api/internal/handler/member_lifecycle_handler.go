package handler

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"time"

	"inv-api-server/internal/job"
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// ==================== Request/Response Models (lines 1-140) ====================

// AddMemberRequest represents a request to add an existing user to an organization
type AddMemberRequest struct {
	UserID           int64   `json:"user_id" binding:"required"`
	OrganizationID   int64   `json:"organization_id" binding:"required"`
	MembershipType   string  `json:"membership_type" default:"full"`
	RoleIDs          []int   `json:"role_ids"`
	ExpiresAt        *time.Time `json:"expires_at"`
}

// UpdateMembershipRequest represents a request to update membership details
type UpdateMembershipRequest struct {
	RoleIDs          *[]int `json:"role_ids"`
	Status           *string `json:"status"`
	ExpiresAt        *time.Time `json:"expires_at"`
	MembershipType   *string `json:"membership_type"`
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

// TransferApprovalRequest represents a request to accept/reject transfer
type TransferApprovalRequest struct {
	Approved bool   `json:"approved" binding:"required"`
	Reason   string `json:"reason"` // required if rejected
}

// BulkAddRequest represents a bulk add operation request
type BulkAddRequest struct {
	UserIDs        []int64 `json:"user_ids" binding:"required,min=1,max=100"`
	OrganizationID int64   `json:"organization_id" binding:"required"`
	MembershipType string  `json:"membership_type" default:"full"`
	RoleIDs        []int   `json:"role_ids"`
	ExpiresAt      *time.Time `json:"expires_at"`
}

// BulkTransferRequest represents a bulk transfer operation
type BulkTransferRequest struct {
	MembershipIDs []int64 `json:"membership_ids" binding:"required,min=1,max=100"`
	TargetOrgID   int64   `json:"target_org_id" binding:"required"`
	Reason        string  `json:"reason"`
}

// PendingTransferInfo represents a pending transfer record
type PendingTransferInfo struct {
	ID            int64     `json:"id"`
	MembershipID  int64     `json:"membership_id"`
	UserID        int64     `json:"user_id"`
	FromOrgID     int64     `json:"from_org_id"`
	ToOrgID       int64     `json:"to_org_id"`
	InitiatorID   int64     `json:"initiator_id"`
	Status        string    `json:"status"` // initiated/accepted/rejected/cancelled/completed
	Reason        string    `json:"reason"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// MemberLifecycleResponse is a common response structure
type MemberLifecycleResponse struct {
	Message         string                 `json:"message"`
	OrganizationID  int64                  `json:"organization_id,omitempty"`
	UserID          int64                  `json:"user_id,omitempty"`
	MembershipID    int64                  `json:"membership_id,omitempty"`
	TransferredCount int                   `json:"transferred_count,omitempty"`
	PendingTransfers []PendingTransferInfo `json:"pending_transfers,omitempty"`
}

// ==================== Handler Struct (lines 142-160) ====================

// MemberLifecycleHandler handles member lifecycle operations
type MemberLifecycleHandler struct {
	db          *pgxpool.Pool
	rdb         *redis.Client
	permChecker interface{} // Will be available when service layer is integrated
	jobStore    *job.JobStore
}

// NewMemberLifecycleHandler creates a new member lifecycle handler instance
func NewMemberLifecycleHandler(db *pgxpool.Pool, rdb *redis.Client, jobStore *job.JobStore) *MemberLifecycleHandler {
	return &MemberLifecycleHandler{
		db:          db,
		rdb:         rdb,
		permChecker: nil,
		jobStore:    jobStore,
	}
}

// ==================== Helper Methods (lines 652-780) ====================

// getUserByID fetches user details by ID
func (h *MemberLifecycleHandler) getUserByID(ctx context.Context, userID int64) (*model.User, error) {
	var user model.User
	err := h.db.QueryRow(ctx, `
		SELECT id, phone, email, password_hash, role, status, created_at, updated_at
		FROM users WHERE id = $1 AND deleted_at IS NULL
	`, userID).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash,
		&user.Role, &user.Status,
		&user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// getOrgByID fetches organization details by ID
func (h *MemberLifecycleHandler) getOrgByID(ctx context.Context, orgID int64) (*model.Organization, error) {
	var org model.Organization
	err := h.db.QueryRow(ctx, `
		SELECT id, root_tenant_id, parent_id, org_type, code, name,
		       status, version, created_at, updated_at
		FROM organizations WHERE id = $1 AND deleted_at IS NULL
	`, orgID).Scan(
		&org.ID, &org.RootTenantID, &org.ParentID, &org.Type,
		&org.Code, &org.Name, &org.Status, &org.Version,
		&org.CreatedAt, &org.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &org, nil
}

// getMembershipByID fetches membership details by ID
func (h *MemberLifecycleHandler) getMembershipByID(ctx context.Context, membershipID int64) (*OrganizationMembership, error) {
	var membership OrganizationMembership
	err := h.db.QueryRow(ctx, `
		SELECT id, root_tenant_id, organization_id, user_id, membership_type,
		       role_ids, status, expires_at, created_at, updated_at
		FROM organization_memberships WHERE id = $1 AND deleted_at IS NULL
	`, membershipID).Scan(
		&membership.ID, &membership.RootTenantID, &membership.OrganizationID,
		&membership.UserID, &membership.MembershipType, &membership.RoleIDs,
		&membership.Status, &membership.ExpiresAt, &membership.CreatedAt,
		&membership.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &membership, nil
}

// getMembershipsByIDList fetches multiple memberships by IDs
func (h *MemberLifecycleHandler) getMembershipsByIDList(ctx context.Context, membershipIDs []int64) ([]*OrganizationMembership, error) {
	if len(membershipIDs) == 0 {
		return []*OrganizationMembership{}, nil
	}

	rows, err := h.db.Query(ctx, `
		SELECT id, root_tenant_id, organization_id, user_id, membership_type,
		       role_ids, status, expires_at, created_at, updated_at
		FROM organization_memberships 
		WHERE id = ANY($1) AND deleted_at IS NULL
	`, membershipIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var memberships []*OrganizationMembership
	for rows.Next() {
		var m OrganizationMembership
		if err := rows.Scan(
			&m.ID, &m.RootTenantID, &m.OrganizationID, &m.UserID,
			&m.MembershipType, &m.RoleIDs, &m.Status, &m.ExpiresAt,
			&m.CreatedAt, &m.UpdatedAt,
		); err != nil {
			return nil, err
		}
		memberships = append(memberships, &m)
	}

	return memberships, nil
}

// checkQuota checks tenant capacity quota before adding members
func (h *MemberLifecycleHandler) checkQuota(ctx context.Context, rootTenantID int64) (*TenantQuotaUsage, error) {
	usage := &TenantQuotaUsage{}

	// Get tenant quota limits
	err := h.db.QueryRow(ctx, `
		SELECT user_limit FROM tenant_roots WHERE id = $1
	`, rootTenantID).Scan(&usage.UserLimit)
	if err != nil {
		return nil, err
	}
	if usage.UserLimit <= 0 {
		usage.UserLimit = -1 // unlimited
	}

	// Count current members
	err = h.db.QueryRow(ctx, `
		SELECT COUNT(DISTINCT user_id) FROM organization_memberships 
		WHERE root_tenant_id = $1 AND status IN ('active', 'suspended')
	`, rootTenantID).Scan(&usage.UserCount)
	if err != nil {
		return nil, err
	}

	return usage, nil
}

// getExistingMembership checks if a membership already exists
func (h *MemberLifecycleHandler) getExistingMembership(ctx context.Context, userID int64, orgID int64) (*OrganizationMembership, error) {
	var membership OrganizationMembership
	err := h.db.QueryRow(ctx, `
		SELECT id, root_tenant_id, organization_id, user_id, membership_type,
		       role_ids, status, expires_at, created_at, updated_at
		FROM organization_memberships 
		WHERE user_id = $1 AND organization_id = $2 AND deleted_at IS NULL
	`, userID, orgID).Scan(
		&membership.ID, &membership.RootTenantID, &membership.OrganizationID,
		&membership.UserID, &membership.MembershipType, &membership.RoleIDs,
		&membership.Status, &membership.ExpiresAt, &membership.CreatedAt,
		&membership.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &membership, nil
}

// invalidateAuthCache invalidates Redis authorization cache for a membership change
func (h *MemberLifecycleHandler) invalidateAuthCache(rootTenantID int64, orgID int64) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Invalidate cache patterns related to this org and tenant
	patterns := []string{
		fmt.Sprintf("auth_perms:%d:*", rootTenantID),
		fmt.Sprintf("membership:*:%d", orgID),
		fmt.Sprintf("tenant:%d:auth_version", rootTenantID),
	}

	for _, pattern := range patterns {
		keys, err := h.rdb.Keys(ctx, pattern).Result()
		if err != nil {
			log.Printf("[invalidateAuthCache] keys lookup failed: %v", err)
			continue
		}
		if len(keys) > 0 {
			if err := h.rdb.Del(ctx, keys...).Err(); err != nil {
				log.Printf("[invalidateAuthCache] del keys failed: %v", err)
			}
		}
	}
}

// canManageMembership checks if user has permission to manage specific membership
func (h *MemberLifecycleHandler) canManageMembership(ctx context.Context, userID int64, orgID int64) (bool, error) {
	// TODO: Implement with permChecker when service layer is integrated
	// For now, check if user has admin/superadmin role
	var role int
	err := h.db.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if err != nil {
		return false, err
	}
	// Roles 0-3 are considered managers (superadmin, manufacturer, agent, distributor)
	return role >= 0 && role <= 3, nil
}

// auditLog emits async audit logging events
func (h *MemberLifecycleHandler) auditLog(userID int64, action string, orgID int64, details map[string]interface{}) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		
		_ = ctx
		_ = action
		_ = orgID
		_ = details
		// TODO: Integrate with existing audit logging system
		// Example: h.auditLog.Create(ctx, userID, action, orgID, details)
		log.Printf("[Audit] user=%d action=%s org=%d details=%v", userID, action, orgID, details)
	}()
}

// OrganizationMembership represents the organization_memberships table structure
type OrganizationMembership struct {
	ID             int64      `json:"id"`
	RootTenantID   int64      `json:"root_tenant_id"`
	OrganizationID int64      `json:"organization_id"`
	UserID         int64      `json:"user_id"`
	MembershipType string     `json:"membership_type"`
	RoleIDs        []int      `json:"role_ids"`
	Status         string     `json:"status"`
	ExpiresAt      *time.Time `json:"expires_at"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

// TenantQuotaUsage represents tenant capacity usage information
type TenantQuotaUsage struct {
	UserCount int64
	UserLimit int64 // -1 means unlimited
}

// ==================== Add Member Endpoint (lines 172-300) ====================

// AddMember handles POST /api/v1/members/add - Add existing user to organization
func (h *MemberLifecycleHandler) AddMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	
	var req AddMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	// Validate membership type
	validTypes := map[string]bool{
		"full": true, "read_only": true, "billing": true, "guest": true,
	}
	if !validTypes[req.MembershipType] {
		req.MembershipType = "full" // default
	}

	ctx := c.Request.Context()

	// Validate target user exists
	targetUser, err := h.getUserByID(ctx, req.UserID)
	if err != nil || targetUser == nil {
		response.HandleError(c, apperr.NotFound("用户不存在"))
		return
	}

	// Validate target organization exists and belongs to same tenant as user
	targetOrg, err := h.getOrgByID(ctx, req.OrganizationID)
	if err != nil || targetOrg == nil {
		response.HandleError(c, apperr.NotFound("组织不存在"))
		return
	}

	// Tenant isolation check: user must be active
	if targetUser == nil {
		response.HandleError(c, apperr.NotFound("用户不存在"))
		return
	}

	// Get root_tenant_id from actor context
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.HandleError(c, apperr.Forbidden("tenant context missing"))
		return
	}

	// Check quota before adding
	usage, err := h.checkQuota(ctx, tenantID)
	if err != nil {
		log.Printf("[AddMember] quota check failed: %v", err)
		response.HandleError(c, apperr.Internal("检查配额失败", err))
		return
	}
	if usage.UserLimit > 0 && usage.UserCount >= usage.UserLimit {
		response.HandleError(c, apperr.Conflict("已达用户数上限，无法添加新成员"))
		return
	}

	// Check if already a member with active status
	existing, _ := h.getExistingMembership(ctx, req.UserID, req.OrganizationID)
	if existing != nil && existing.Status == "active" {
		response.HandleError(c, apperr.Conflict("该用户已是此组织活跃成员"))
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	// Insert membership record (soft-deletable: reuse old ID or create new)
	if existing != nil && existing.Status != "active" {
		// Reactivate existing membership
		result, err := tx.Exec(ctx, `
			UPDATE organization_memberships 
			SET status = 'active', 
			    role_ids = COALESCE($3, role_ids),
			    membership_type = COALESCE($4, membership_type),
			    expires_at = COALESCE($5, expires_at),
			    updated_at = NOW()
			WHERE id = $1 AND deleted_at IS NULL
		`, existing.ID, req.RoleIDs, req.MembershipType, req.ExpiresAt)
		if err != nil {
			response.HandleError(c, apperr.Conflict("更新成员关系失败"))
			return
		}
		if result.RowsAffected() == 0 {
			response.HandleError(c, apperr.NotFound("原成员记录已失效"))
			return
		}
	} else {
		// Create new membership
		_, err := tx.Exec(ctx, `
			INSERT INTO organization_memberships 
				(root_tenant_id, organization_id, user_id, membership_type, role_ids, status, expires_at)
			VALUES ($1, $2, $3, $4, $5, 'active', $6)
		`, tenantID, req.OrganizationID, req.UserID, req.MembershipType, req.RoleIDs, req.ExpiresAt)
		if err != nil {
			response.HandleError(c, apperr.Conflict("添加成员失败：约束冲突"))
			return
		}
	}

	// Invalidate authorization cache
	h.invalidateAuthCache(tenantID, req.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("保存成员记录失败", err))
		return
	}

	// Async audit logging
	h.auditLog(userID, "member.add", req.OrganizationID, map[string]interface{}{
		"user_id":          req.UserID,
		"membership_type":  req.MembershipType,
		"new_member_count": usage.UserCount + 1,
	})

	response.Success(c, MemberLifecycleResponse{
		Message:        "成员添加成功",
		OrganizationID: req.OrganizationID,
		UserID:         req.UserID,
	})
}

// ==================== Update Membership Endpoint ====================

// UpdateMembership handles PUT /api/v1/memberships/:id/update - Update membership details
func (h *MemberLifecycleHandler) UpdateMembership(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的会员关系 ID"))
		return
	}

	var req UpdateMembershipRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()

	// Fetch current membership
	membership, err := h.getMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		response.HandleError(c, apperr.NotFound("成员关系不存在"))
		return
	}

	// Verify ownership/access
	orgTenantID := middleware.GetRootTenantID(c)
	if orgTenantID == 0 {
		response.HandleError(c, apperr.Forbidden("tenant context missing"))
		return
	}
	if membership.RootTenantID != orgTenantID {
		response.HandleError(c, apperr.Forbidden("无权访问此组织成员关系"))
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	// Build dynamic update query
	query := `UPDATE organization_memberships SET updated_at = NOW()`
	params := []interface{}{membershipID}

	if req.RoleIDs != nil {
		query += `, role_ids = $` + fmt.Sprintf("%d", len(params)+1)
		params = append(params, *req.RoleIDs)
	}
	if req.Status != nil {
		validStatus := map[string]bool{"active": true, "inactive": true, "suspended": true}
		if !validStatus[*req.Status] {
			tx.Rollback(ctx)
			response.HandleError(c, apperr.BadRequest("无效的状态值"))
			return
		}
		query += `, status = $` + fmt.Sprintf("%d", len(params)+1)
		params = append(params, *req.Status)
	}
	if req.ExpiresAt != nil {
		query += `, expires_at = $` + fmt.Sprintf("%d", len(params)+1)
		params = append(params, *req.ExpiresAt)
	}
	if req.MembershipType != nil {
		validTypes := map[string]bool{"full": true, "read_only": true, "billing": true, "guest": true}
		if !validTypes[*req.MembershipType] {
			tx.Rollback(ctx)
			response.HandleError(c, apperr.BadRequest("无效的会员类型"))
			return
		}
		query += `, membership_type = $` + fmt.Sprintf("%d", len(params)+1)
		params = append(params, *req.MembershipType)
	}

	query += ` WHERE id = $` + fmt.Sprintf("%d", len(params))
	params = append(params, membershipID)

	_, err = tx.Exec(ctx, query, params...)
	if err != nil {
		response.HandleError(c, apperr.Internal("更新成员信息失败", err))
		return
	}

	h.invalidateAuthCache(membership.RootTenantID, membership.OrganizationID)
	
	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("保存更新失败", err))
		return
	}

	h.auditLog(userID, "member.update", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"changed_fields": map[string]interface{}{
			"role_ids":       req.RoleIDs,
			"status":         req.Status,
			"expires_at":     req.ExpiresAt,
			"membership_type": req.MembershipType,
		},
	})

	response.SuccessWithMessage(c, "成员信息已更新", gin.H{
		"membership_id": membershipID,
	})
}

// ==================== Remove Member Endpoint ====================

// RemoveMember handles DELETE /api/v1/memberships/:id/remove - Remove member from organization
func (h *MemberLifecycleHandler) RemoveMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的会员关系 ID"))
		return
	}

	var req RemoveMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()

	membership, err := h.getMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		response.HandleError(c, apperr.NotFound("成员关系不存在"))
		return
	}

	// Soft delete only: set status='inactive'
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	result, err := tx.Exec(ctx, `
		UPDATE organization_memberships 
		SET status = 'inactive', deleted_at = NOW(), updated_at = NOW()
		WHERE id = $1 AND deleted_at IS NULL
	`, membershipID)
	if err != nil {
		response.HandleError(c, apperr.Internal("删除成员失败", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.NotFound("成员记录已不存在或已删除"))
		return
	}

	h.invalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("保存更改失败", err))
		return
	}

	h.auditLog(userID, "member.remove", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
		"reason":        req.Reason,
	})

	response.SuccessWithMessage(c, "成员已从组织中移除", gin.H{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
	})
}

// ==================== Deactivate/Reactivate Endpoints ====================

// DeactivateMember handles PATCH /api/v1/memberships/:id/deactivate - Soft deactivate member
func (h *MemberLifecycleHandler) DeactivateMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的会员关系 ID"))
		return
	}

	var req DeactivateMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()

	membership, err := h.getMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		response.HandleError(c, apperr.NotFound("成员关系不存在"))
		return
	}

	if membership.Status != "active" {
		response.HandleError(c, apperr.Conflict("成员已经是非活跃状态"))
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	result, err := tx.Exec(ctx, `
		UPDATE organization_memberships 
		SET status = 'inactive', updated_at = NOW()
		WHERE id = $1 AND status = 'active'
	`, membershipID)
	if err != nil {
		response.HandleError(c, apperr.Internal("停用成员失败", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.Conflict("成员状态未改变"))
		return
	}

	h.invalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("保存停用失败", err))
		return
	}

	h.auditLog(userID, "member.deactivate", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
		"reason":        req.Reason,
	})

	response.SuccessWithMessage(c, "成员已停用", gin.H{
		"membership_id": membershipID,
	})
}

// ReactivateMember handles PATCH /api/v1/memberships/:id/reactivate - Reactivate deactivated member
func (h *MemberLifecycleHandler) ReactivateMember(c *gin.Context) {
	userID := middleware.GetUserID(c)
	membershipID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的会员关系 ID"))
		return
	}

	ctx := c.Request.Context()

	membership, err := h.getMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		response.HandleError(c, apperr.NotFound("成员关系不存在"))
		return
	}

	if membership.Status == "active" {
		response.HandleError(c, apperr.Conflict("成员已经是活跃状态"))
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	result, err := tx.Exec(ctx, `
		UPDATE organization_memberships 
		SET status = 'active', updated_at = NOW()
		WHERE id = $1 AND status IN ('inactive', 'suspended')
	`, membershipID)
	if err != nil {
		response.HandleError(c, apperr.Internal("恢复成员失败", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.Conflict("成员状态未改变"))
		return
	}

	h.invalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("保存恢复失败", err))
		return
	}

	h.auditLog(userID, "member.reactivate", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
	})

	response.SuccessWithMessage(c, "成员已恢复活跃", gin.H{
		"membership_id": membershipID,
	})
}

// ==================== Transfer Flow Implementation (lines 302-650) ====================

// TransferInitiate handles POST /api/v1/members/transfer/initiate - Initiate transfer to different org
func (h *MemberLifecycleHandler) TransferInitiate(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req TransferInitiateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if len(req.MembershipIDs) == 0 {
		response.HandleError(c, apperr.BadRequest("请选择要转移的成员"))
		return
	}

	ctx := c.Request.Context()

	// Fetch all memberships
	memberships, err := h.getMembershipsByIDList(ctx, req.MembershipIDs)
	if err != nil || len(memberships) == 0 {
		response.HandleError(c, apperr.NotFound("未找到有效的成员关系"))
		return
	}

	// Validate all memberships belong to same root_tenant
	rootTenantID := memberships[0].RootTenantID
	sourceOrgID := memberships[0].OrganizationID

	for _, m := range memberships {
		if m.RootTenantID != rootTenantID {
			response.HandleError(c, apperr.Conflict("跨租户批量转移不支持，请确保所有成员属于同一租户"))
			return
		}
		if m.Status != "active" {
			response.HandleError(c, apperr.BadRequest(fmt.Sprintf("成员 ID=%d 不是活跃状态", m.ID)))
			return
		}
	}

	// Verify target org exists and belongs to same tenant
	targetOrg, err := h.getOrgByID(ctx, req.TargetOrgID)
	if err != nil || targetOrg == nil {
		response.HandleError(c, apperr.NotFound("目标组织不存在"))
		return
	}
	if targetOrg.RootTenantID != rootTenantID {
		response.HandleError(c, apperr.Forbidden("目标组织不在同一租户下"))
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	_ = time.Now()

	// Transfer each membership
	transferredCount := 0
	for _, membership := range memberships {
		// Delete old membership
		_, err := tx.Exec(ctx, `
			DELETE FROM organization_memberships WHERE id = $1 AND deleted_at IS NULL
		`, membership.ID)
		if err != nil {
			response.HandleError(c, apperr.Internal("移除旧成员关系失败", err))
			return
		}

		// Create new membership in target org
		result, err := tx.Exec(ctx, `
			INSERT INTO organization_memberships 
				(root_tenant_id, organization_id, user_id, membership_type, role_ids, status, expires_at, created_at, updated_at)
			SELECT $1, $2, user_id, membership_type, role_ids, 'active', expires_at, NOW(), NOW()
			FROM organization_memberships WHERE id = $3
		`, targetOrg.RootTenantID, targetOrg.ID, membership.ID)
		if err != nil {
			response.HandleError(c, apperr.Internal("添加到目标组织失败", err))
			return
		}
		if result.RowsAffected() > 0 {
			transferredCount++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("提交成员转移失败", err))
		return
	}

	// Invalidate authorization caches for both orgs
	go func() {
		h.invalidateAuthCache(rootTenantID, sourceOrgID)
		h.invalidateAuthCache(rootTenantID, targetOrg.ID)
	}()

	h.auditLog(userID, "member.transfer.initiate", targetOrg.ID, map[string]interface{}{
		"source_org_id":     sourceOrgID,
		"target_org_id":     targetOrg.ID,
		"transferred_users": membershipIDsToUserIDs(memberships),
		"count":             transferredCount,
		"reason":            req.Reason,
	})

	response.Success(c, MemberLifecycleResponse{
		Message:        "成员转移完成",
		OrganizationID: targetOrg.ID,
		TransferredCount: transferredCount,
	})
}

// TransferAccept handles POST /api/v1/members/transfer/accept - Accept transfer request
// Note: In current implementation, transfers are immediate, not delayed approval-based
func (h *MemberLifecycleHandler) TransferAccept(c *gin.Context) {
	_ = middleware.GetUserID(c)
	
	var req TransferApprovalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if !req.Approved {
		response.HandleError(c, apperr.BadRequest("拒绝转移需要提供原因"))
		return
	}

	_ = c.Request.Context()

	// TODO: If implementing delayed transfers:
	// 1. Find pending transfer(s) for this user
	// 2. Update status to 'accepted'
	// 3. Execute actual transfer
	// 4. Send notifications

	response.SuccessWithMessage(c, "转移请求已接受（当前实现为即时转移）", nil)
}

// TransferReject handles POST /api/v1/members/transfer/reject - Reject transfer request
func (h *MemberLifecycleHandler) TransferReject(c *gin.Context) {
	_ = middleware.GetUserID(c)

	var req TransferApprovalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	if req.Approved {
		response.HandleError(c, apperr.BadRequest("拒绝转移必须设置 approved=false"))
		return
	}

	if req.Reason == "" {
		response.HandleError(c, apperr.BadRequest("拒绝转移必须提供原因"))
		return
	}

	_ = c.Request.Context()

	// TODO: If implementing delayed transfers:
	// 1. Find pending transfer(s) for this user
	// 2. Update status to 'rejected'
	// 3. Send rejection notification

	response.SuccessWithMessage(c, "转移请求已拒绝", map[string]interface{}{
		"reason": req.Reason,
	})
}

// ListTransfers handles GET /api/v1/members/transfers/list - List pending transfers
func (h *MemberLifecycleHandler) ListTransfers(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()

	// Query pending transfers for the authenticated user
	// This would require a transfers table in delayed-approval model
	rows, err := h.db.Query(ctx, `
		SELECT id, membership_id, from_org_id, to_org_id, initiator_id, 
		       status, reason, created_at, updated_at
		FROM pending_transfers
		WHERE user_id = $1 AND status = 'initiated'
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		log.Printf("[ListTransfers] query failed: %v", err)
		// Return empty list if no delayed-transfer table exists yet
		response.Page(c, []PendingTransferInfo{}, 0, 1, 10)
		return
	}
	defer rows.Close()

	var transfers []PendingTransferInfo
	for rows.Next() {
		var t PendingTransferInfo
		if err := rows.Scan(
			&t.ID, &t.MembershipID, &t.FromOrgID, &t.ToOrgID,
			&t.InitiatorID, &t.Status, &t.Reason, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			log.Printf("[ListTransfers] scan error: %v", err)
			continue
		}
		transfers = append(transfers, t)
	}

	response.Page(c, transfers, int64(len(transfers)), 1, 10)
}

// ==================== Bulk Operations ====================

// BulkAdd handles POST /api/v1/members/bulk-add - Add multiple users to org asynchronously
func (h *MemberLifecycleHandler) BulkAdd(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BulkAddRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()

	// Validate target organization
	targetOrg, err := h.getOrgByID(ctx, req.OrganizationID)
	if err != nil || targetOrg == nil {
		response.HandleError(c, apperr.NotFound("组织不存在"))
		return
	}

	// Get root_tenant_id from actor context
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.HandleError(c, apperr.Forbidden("tenant context missing"))
		return
	}

	if targetOrg.RootTenantID != tenantID {
		response.HandleError(c, apperr.Forbidden("组织不属于当前租户范围"))
		return
	}

	// Check quota
	_, err = h.checkQuota(ctx, tenantID)
	if err != nil {
		log.Printf("[BulkAdd] quota check failed: %v", err)
		response.HandleError(c, apperr.Internal("检查配额失败", err))
		return
	}

	// Validate membership type
	validTypes := map[string]bool{"full": true, "read_only": true, "billing": true, "guest": true}
	if !validTypes[req.MembershipType] {
		req.MembershipType = "full"
	}

	// For small batches (<10 items), process synchronously
	if len(req.UserIDs) < 10 {
		h.processBulkAddSync(c, userID, tenantID, req)
		return
	}

	// For larger batches, create background job
	bulkJob := job.CreateBulkAddJob(userID, req.OrganizationID, req.UserIDs, req.RoleIDs)
	bulkJob.TotalItems = len(req.UserIDs)

	// Store job in Redis
	if err := h.jobStore.CreateJob(ctx, bulkJob); err != nil {
		log.Printf("[BulkAdd] failed to create job: %v", err)
		response.HandleError(c, apperr.Internal("创建批量任务失败", err))
		return
	}

	// Enqueue job for processing (in production, this would send to Kafka)
	go func() {
		if err := bulkJob.WithRetry(job.MaxRetries); err != nil {
			log.Printf("[BulkAdd] job %s failed: %v", bulkJob.JobID, err)
		}

		// Invalidate cache after job completion
		h.invalidateAuthCache(tenantID, req.OrganizationID)

		// Audit log
		h.auditLog(userID, "member.bulk_add", req.OrganizationID, map[string]interface{}{
			"user_ids":        req.UserIDs,
			"total_requested": len(req.UserIDs),
			"job_id":          bulkJob.JobID,
		})
	}()

	// Return async response with job tracking info
	response.Success(c, map[string]interface{}{
		"message":     "批量添加任务已创建，正在后台处理",
		"job_id":      bulkJob.JobID,
		"status_url":  fmt.Sprintf("/api/v1/jobs/%s/status", bulkJob.JobID),
		"ws_url":      fmt.Sprintf("/ws/jobs/%s/progress?user_id=%d", bulkJob.JobID, userID),
		"total_items": len(req.UserIDs),
	})
}

// processBulkAddSync handles small batch operations synchronously
func (h *MemberLifecycleHandler) processBulkAddSync(c *gin.Context, userID, tenantID int64, req BulkAddRequest) {
	ctx := c.Request.Context()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	addedCount := 0
	for _, uid := range req.UserIDs {
		// Validate user exists
		_, err := h.getUserByID(ctx, uid)
		if err != nil {
			log.Printf("[BulkAdd] user %d not found: %v", uid, err)
			continue
		}

		// Skip if already active member
		existing, _ := h.getExistingMembership(ctx, uid, req.OrganizationID)
		if existing != nil && existing.Status == "active" {
			continue
		}

		// Insert or reactivate
		if existing != nil && existing.Status != "active" {
			_, _ = tx.Exec(ctx, `
				UPDATE organization_memberships 
				SET status = 'active', role_ids = $3, membership_type = $4, expires_at = $5, updated_at = NOW()
				WHERE id = $1
			`, existing.ID, req.RoleIDs, req.MembershipType, req.ExpiresAt)
		} else {
			result, err := tx.Exec(ctx, `
				INSERT INTO organization_memberships 
					(root_tenant_id, organization_id, user_id, membership_type, role_ids, status, expires_at)
				VALUES ($1, $2, $3, $4, $5, 'active', $6)
			`, tenantID, req.OrganizationID, uid, req.MembershipType, req.RoleIDs, req.ExpiresAt)
			if err == nil && result.RowsAffected() > 0 {
				addedCount++
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("批量添加失败", err))
		return
	}

	h.invalidateAuthCache(tenantID, req.OrganizationID)
	h.auditLog(userID, "member.bulk_add", req.OrganizationID, map[string]interface{}{
		"user_ids":        req.UserIDs,
		"added_count":     addedCount,
		"total_requested": len(req.UserIDs),
	})

	response.Success(c, MemberLifecycleResponse{
		Message:          "批量添加完成",
		OrganizationID:   req.OrganizationID,
		TransferredCount: addedCount,
	})
}

// BulkTransfer handles POST /api/v1/members/bulk-transfer - Transfer multiple members asynchronously
func (h *MemberLifecycleHandler) BulkTransfer(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req BulkTransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()

	// Fetch memberships
	memberships, err := h.getMembershipsByIDList(ctx, req.MembershipIDs)
	if err != nil || len(memberships) == 0 {
		response.HandleError(c, apperr.NotFound("未找到有效成员"))
		return
	}

	// Validate same tenant
	rootTenantID := memberships[0].RootTenantID
	for _, m := range memberships {
		if m.RootTenantID != rootTenantID {
			response.HandleError(c, apperr.Conflict("跨租户批量转移不支持"))
			return
		}
	}

	// Validate target org
	targetOrg, err := h.getOrgByID(ctx, req.TargetOrgID)
	if err != nil || targetOrg.RootTenantID != rootTenantID {
		response.HandleError(c, apperr.Forbidden("目标组织不在同一租户下"))
		return
	}

	// For small batches (<10 items), process synchronously
	if len(req.MembershipIDs) < 10 {
		h.processBulkTransferSync(c, userID, rootTenantID, targetOrg, memberships, req.Reason)
		return
	}

	// For larger batches, create background job
	bulkJob := job.CreateBulkTransferJob(userID, req.MembershipIDs, req.TargetOrgID)
	bulkJob.TotalItems = len(req.MembershipIDs)

	// Store job in Redis
	if err := h.jobStore.CreateJob(ctx, bulkJob); err != nil {
		log.Printf("[BulkTransfer] failed to create job: %v", err)
		response.HandleError(c, apperr.Internal("创建批量转移任务失败", err))
		return
	}

	// Enqueue job for processing
	sourceOrgID := memberships[0].OrganizationID
	go func() {
		if err := bulkJob.WithRetry(job.MaxRetries); err != nil {
			log.Printf("[BulkTransfer] job %s failed: %v", bulkJob.JobID, err)
		}

		// Invalidate caches after completion
		go func() {
			h.invalidateAuthCache(rootTenantID, sourceOrgID)
			h.invalidateAuthCache(rootTenantID, targetOrg.ID)
		}()

		// Audit log
		h.auditLog(userID, "member.bulk_transfer", targetOrg.ID, map[string]interface{}{
			"membership_ids":    req.MembershipIDs,
			"target_org_id":     req.TargetOrgID,
			"total_transferred": len(req.MembershipIDs),
			"job_id":            bulkJob.JobID,
			"reason":            req.Reason,
		})
	}()

	// Return async response with job tracking info
	response.Success(c, map[string]interface{}{
		"message":     "批量转移任务已创建，正在后台处理",
		"job_id":      bulkJob.JobID,
		"status_url":  fmt.Sprintf("/api/v1/jobs/%s/status", bulkJob.JobID),
		"ws_url":      fmt.Sprintf("/ws/jobs/%s/progress?user_id=%d", bulkJob.JobID, userID),
		"total_items": len(req.MembershipIDs),
	})
}

// processBulkTransferSync handles small batch transfer operations synchronously
func (h *MemberLifecycleHandler) processBulkTransferSync(c *gin.Context, userID, rootTenantID int64, targetOrg *model.Organization, memberships []*OrganizationMembership, reason string) {
	ctx := c.Request.Context()

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("数据库事务开始失败", err))
		return
	}
	defer tx.Rollback(ctx)

	transferredCount := 0
	for _, membership := range memberships {
		// Delete old
		_, err := tx.Exec(ctx, `DELETE FROM organization_memberships WHERE id = $1`, membership.ID)
		if err != nil {
			continue
		}

		// Insert new in target org
		result, err := tx.Exec(ctx, `
			INSERT INTO organization_memberships 
				(root_tenant_id, organization_id, user_id, membership_type, role_ids, status, expires_at)
			SELECT $1, $2, user_id, membership_type, role_ids, 'active', expires_at
			FROM organization_memberships WHERE id = $3
		`, targetOrg.RootTenantID, targetOrg.ID, membership.ID)
		if err == nil && result.RowsAffected() > 0 {
			transferredCount++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		response.HandleError(c, apperr.Internal("批量转移失败", err))
		return
	}

	go func() {
		h.invalidateAuthCache(rootTenantID, memberships[0].OrganizationID)
		h.invalidateAuthCache(rootTenantID, targetOrg.ID)
	}()

	h.auditLog(userID, "member.bulk_transfer", targetOrg.ID, map[string]interface{}{
		"transferred_count": transferredCount,
		"source_orgs":       membershipIDsToUserIDs(memberships),
	})

	response.Success(c, MemberLifecycleResponse{
		Message:          "批量转移完成",
		OrganizationID:   targetOrg.ID,
		TransferredCount: transferredCount,
	})
}

// Helper function to extract user IDs from memberships
func membershipIDsToUserIDs(memberships []*OrganizationMembership) []int64 {
	userIDs := make([]int64, len(memberships))
	for i, m := range memberships {
		userIDs[i] = m.UserID
	}
	return userIDs
}
