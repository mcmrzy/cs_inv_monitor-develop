package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
)

// ============================================================================
// Request/Response Models
// ============================================================================

// CreateInvitationRequest represents the request to create a new invitation.
type CreateInvitationRequest struct {
	Email            string             `json:"email" binding:"required,email"`
	RoleID           int                `json:"role_id" binding:"required,min=1,max=5"`
	OrganizationID   *int64             `json:"organization_id"`
	ExpiresHours     int                `json:"expires_hours" binding:"required,min=1,max=720"` // max 30 days
}

// InvitationResponse represents the response for invitation details.
type InvitationResponse struct {
	ID          int64  `json:"id"`
	Email       string `json:"email"`
	RoleName    string `json:"role_name"`
	TokenHint   string `json:"token_hint"` // First 8 chars of raw token (for display, not full token)
	ExpiresAt   string `json:"expires_at"`
	CreatedBy   string `json:"created_by"`
	Status      string `json:"status"`
}

// AcceptInvitationRequest represents the request to accept an invitation.
type AcceptInvitationRequest struct {
	InvitationCode string `json:"invitation_code" binding:"required"`
	Password       string `json:"password" binding:"required,min=6,max=20"`
	Phone          string `json:"phone" binding:"required"`
	Nickname       string `json:"nickname" binding:"required"`
}

// AcceptInvitationResponse represents the successful acceptance with auto-login tokens.
type AcceptInvitationResponse struct {
	InvitationID  int64                 `json:"invitation_id"`
	User          *model.User           `json:"user"`
	AccessToken   string                `json:"access_token"`
	RefreshToken  string                `json:"refresh_token"`
	ExpiresIn     int64                 `json:"expires_in"`
	Permissions   []string              `json:"permissions"`
}

// ListInvitationsQuery represents query parameters for listing invitations.
type ListInvitationsQuery struct {
	Status         string `form:"status"`
	Email          string `form:"email"`
	OrganizationID int64  `form:"organization_id"`
	Page           int    `form:"page" binding:"min=1"`
	PageSize       int    `form:"page_size" binding:"min=1,max=100"`
}

// ListInvitationsResponse represents paginated invitation list response.
type ListInvitationsResponse struct {
	Total    int                    `json:"total"`
	Items    []InvitationListItem   `json:"items"`
	Page     int                    `json:"page"`
	PageSize int                   `json:"page_size"`
}

// InvitationListItem represents a summary item for list view.
type InvitationListItem struct {
	ID           int64     `json:"id"`
	Email        string    `json:"email"`
	RoleID       int16     `json:"role_id"`
	RoleName     string    `json:"role_name"`
	Status       string    `json:"status"`
	ExpiresAt    string    `json:"expires_at"`
	CreatedAt    string    `json:"created_at"`
	InviterName  string    `json:"inviter_name"`
	Organization *string   `json:"organization,omitempty"`
}

// ============================================================================
// Handler Structure
// ============================================================================

type InvitationHandler struct {
	db               *pgxpool.Pool
	userRepo         *repository.UserRepository
	orgRepo          *repository.OrganizationRepository
	invitationRepo   *repository.InvitationRepository
	jwtService       *service.JWTService
	rbacCache        *service.RBACCache
	permChecker      *service.PermChecker
	contextResolver  middleware.AuthorizationContextValidator
	emailService     *service.EmailService
}

// NewInvitationHandler creates a new InvitationHandler instance.
func NewInvitationHandler(
	db *pgxpool.Pool,
	userRepo *repository.UserRepository,
	orgRepo *repository.OrganizationRepository,
	invitationRepo *repository.InvitationRepository,
	jwtService *service.JWTService,
	rbacCache *service.RBACCache,
	permChecker *service.PermChecker,
	contextResolver middleware.AuthorizationContextValidator,
	emailService *service.EmailService,
) *InvitationHandler {
	return &InvitationHandler{
		db:               db,
		userRepo:         userRepo,
		orgRepo:          orgRepo,
		invitationRepo:   invitationRepo,
		jwtService:       jwtService,
		rbacCache:        rbacCache,
		permChecker:      permChecker,
		contextResolver:  contextResolver,
		emailService:     emailService,
	}
}

// SetAuthorizationContextValidator sets the context resolver for invitation management.
func (h *InvitationHandler) SetAuthorizationContextValidator(resolver middleware.AuthorizationContextValidator) {
	h.contextResolver = resolver
}

// ============================================================================
// API Endpoints
// ============================================================================

// Create generates and sends invitation
// POST /api/v1/invitations/create
func (h *InvitationHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	var req CreateInvitationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// Role validation: only non-endusers can create invitations
	// RoleSuperAdmin=0 is allowed; RoleEndUser=5 and out-of-range values are rejected.
	if role == service.RoleEndUser || role < 0 || role > 5 {
		response.Error(c, 403, "end users cannot create invitations")
		return
	}

	ctx := c.Request.Context()

	// Get inviter info
	inviter, err := h.userRepo.GetByID(ctx, userID)
	if err != nil || inviter == nil {
		response.Error(c, 404, "inviter not found")
		return
	}

	// Check if organization is specified or resolve from context
	orgID := req.OrganizationID
	if orgID == nil || *orgID <= 0 {
		// Try to resolve from authorization context
		orgID, err = h.resolveOrganizationFromContext(ctx, userID)
		if err != nil {
			logger.Warn("Failed to resolve organization from context", zap.Error(err))
			response.Error(c, 400, "organization required")
			return
		}
	}

	// Verify user has permission to create invitations in this organization
	// Super-admin (0) and admin (1) bypass permission check; org_admin (2+) need explicit permission
	hasPerm := h.permChecker.CheckPermission(userID, "organizations", "invite")
	if !hasPerm && role >= 2 {
		response.Error(c, 403, "insufficient permissions to create invitations")
		return
	}

	// Get organization to resolve root_tenant_id
	org, err := h.orgRepo.GetByID(ctx, *orgID)
	if err != nil || org == nil {
		response.Error(c, 404, "organization not found")
		return
	}

	// Verify the organization belongs to the caller's tenant
	callerTenantID := middleware.GetRootTenantID(c)
	if org.RootTenantID != callerTenantID {
		response.Error(c, 403, "cannot create invitations in another tenant's organization")
		return
	}

	// Check quota before generating token
	maxPending, err := h.checkInvitationQuota(ctx, org.RootTenantID, *orgID)
	if err != nil {
		response.Error(c, 500, "检查配额失败")
		return
	}

	// Count current pending invitations
	currentCount, _ := h.invitationRepo.CountByStatus(ctx, h.db, org.RootTenantID, *orgID, "pending")
	if currentCount >= int64(maxPending) {
		response.Error(c, 403, "invitation quota exceeded")
		return
	}

	// Generate secure token (crypto/rand)
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		response.Error(c, 500, "生成邀请码失败")
		return
	}
	rawToken := hex.EncodeToString(tokenBytes)
	tokenDigest := sha256.Sum256([]byte(rawToken))

	// Get role name for email
	roleName := repository.GetRoleName(int(req.RoleID))

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	// Create invitation record
	now := time.Now()
	roleAssignmentsJSON := fmt.Sprintf("[{\"role_id\":%d}]", req.RoleID)
	invitation := &model.Invitation{
		RootTenantID:    org.RootTenantID,
		OrganizationID:  orgID,
		InvitedBy:       userID,
		Recipient:       strings.ToLower(strings.TrimSpace(req.Email)),
		TokenKeyID:      "default",
		TokenDigest:     tokenDigest[:], // raw BYTEA for DB
		RoleAssignments: roleAssignmentsJSON,
		ExpiresAt:       now.Add(time.Duration(req.ExpiresHours) * time.Hour),
		Status:          "pending",
		Version:         1,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	if err := h.invitationRepo.Insert(ctx, tx, invitation); err != nil {
		if strings.Contains(err.Error(), "uq_invitations_pending_recipient") ||
			strings.Contains(err.Error(), "unique_violation") {
			response.Error(c, 409, "该邮箱已有待处理的邀请")
			return
		}
		logger.Error("Invitation insert failed", zap.Error(err),
			zap.Int64("root_tenant_id", invitation.RootTenantID),
			zap.Any("organization_id", invitation.OrganizationID))
		response.Error(c, 500, fmt.Sprintf("保存邀请失败: %v", err))
		return
	}

	if err := tx.Commit(ctx); err != nil {
		logger.Error("Invitation commit failed", zap.Error(err))
		response.Error(c, 500, fmt.Sprintf("保存邀请失败: %v", err))
		return
	}

	// Log for external notification service (NOT sending here)
	go func() {
		if h.emailService != nil {
			_, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			
			err := h.emailService.SendInvitationEmail(
				invitation.Recipient,
				rawToken[:8], // Show first 8 chars only
				roleName,
				org.Name,
				req.ExpiresHours,
				"CSERGY Smart Energy Platform",
			)
			if err != nil {
				logger.Warn("Failed to send invitation email",
					zap.Int64("invitation_id", invitation.ID),
					zap.String("email", invitation.Recipient),
					zap.Error(err))
				// Don't rollback transaction for email errors - log and continue
			}
		} else {
			logger.Info("Invitation created, notification dispatched",
				zap.Int64("invitation_id", invitation.ID),
				zap.String("email", invitation.Recipient),
				zap.String("token_hint", rawToken[:8]+"****"))
		}
	}()

	response.Success(c, InvitationResponse{
		ID:        invitation.ID,
		Email:     invitation.Recipient,
		RoleName:  repository.GetRoleName(int(req.RoleID)),
		TokenHint: rawToken[:8] + "****", // Show partial for debugging
		ExpiresAt: invitation.ExpiresAt.Format(time.RFC3339),
		CreatedBy: inviter.Nickname,
		Status:    invitation.Status,
	})
}

// List returns paginated list of pending invitations
// GET /api/v1/invitations/list
func (h *InvitationHandler) List(c *gin.Context) {
	var query ListInvitationsQuery
	if err := c.ShouldBindQuery(&query); err != nil {
		response.Error(c, 400, "invalid query")
		return
	}

	// Default pagination
	if query.Page <= 0 {
		query.Page = 1
	}
	if query.PageSize <= 0 || query.PageSize > 100 {
		query.PageSize = 20
	}

	ctx := c.Request.Context()

	// Build filter conditions
	filter := repository.ListInvitationsFilter{
		RootTenantID:   middleware.GetRootTenantID(c),
		Status:         query.Status,
		Email:          query.Email,
		OrganizationID: query.OrganizationID,
	}

	total, items, err := h.invitationRepo.ListWithDetails(ctx, h.db, filter, query.Page, query.PageSize)
	if err != nil {
		response.Error(c, 500, "查询邀请列表失败")
		return
	}

	response.Success(c, ListInvitationsResponse{
		Total:    int(total),
		Items:    convertInvitationItems(items),
		Page:     query.Page,
		PageSize: query.PageSize,
	})
}

// Revoke cancels a pending invitation
// DELETE /api/v1/invitations/:id/revoke
func (h *InvitationHandler) Revoke(c *gin.Context) {
	invitationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid invitation ID")
		return
	}

	ctx := c.Request.Context()
	userID := middleware.GetUserID(c)

	// Get invitation details
	invitation, err := h.invitationRepo.GetById(ctx, h.db, invitationID)
	if err != nil || invitation == nil {
		response.Error(c, 404, "邀请不存在")
		return
	}

	// Validate user has permission: inviter or admin (role < 2) can revoke
	if invitation.InvitedBy != userID && middleware.GetRole(c) >= 2 {
		response.Error(c, 403, "无权撤销此邀请")
		return
	}

	// Can only revoke pending invitations
	if invitation.Status != "pending" {
		response.Error(c, 400, "只能撤销待处理的邀请")
		return
	}

	// Revoke the invitation
	if err := h.invitationRepo.Revoke(ctx, h.db, invitationID); err != nil {
		response.Error(c, 500, "撤销邀请失败")
		return
	}

	response.SuccessWithMessage(c, "邀请已撤销", nil)
}

// Accept handles invitation acceptance with auto-registration
// POST /api/v1/invitations/accept (PUBLIC ROUTE - no JWT required)
func (h *InvitationHandler) Accept(c *gin.Context) {
	var req AcceptInvitationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()

	// Validate password strength
	if len(req.Password) < 6 || len(req.Password) > 20 {
		response.Error(c, 400, "密码长度必须在 6-20 个字符之间")
		return
	}

	// Compute SHA-256 digest of the invitation code (raw bytes for BYTEA column)
	tokenBytes := []byte(req.InvitationCode)
	tokenDigest := sha256.Sum256(tokenBytes)

	// Find invitation by digest (raw BYTEA)
	invitation, err := h.invitationRepo.FindByTokenDigest(ctx, h.db, tokenDigest[:])
	if err != nil || invitation == nil {
		response.Error(c, 401, "无效的邀请码")
		return
	}

	// Validate invitation status and expiration
	if invitation.Status != "pending" {
		if invitation.Status == "accepted" {
			response.Error(c, 401, "邀请码已被使用")
		} else if invitation.Status == "revoked" {
			response.Error(c, 401, "邀请码已被撤销")
		} else if invitation.Status == "expired" {
			response.Error(c, 401, "邀请码已过期")
		} else {
			response.Error(c, 401, "无效的邀请码")
		}
		return
	}

	if time.Now().After(invitation.ExpiresAt) {
		h.invitationRepo.UpdateStatus(ctx, h.db, invitation.ID, "expired")
		response.Error(c, 401, "邀请码已过期")
		return
	}

	// Resolve organization and root_tenant
	org, err := h.orgRepo.GetByID(ctx, *invitation.OrganizationID)
	if err != nil || org == nil {
		response.Error(c, 500, "组织信息错误")
		return
	}

	// Hash the user's password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		response.Error(c, 500, "密码加密失败")
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	// Create new user account
	newUser := &model.User{
		Email:        "", // Optional registration, may be empty if phone provided
		Phone:        req.Phone,
		PasswordHash: string(hashedPassword),
		Nickname:     req.Nickname,
		Role:         defaultSelfRegisteredRole, // Will be updated after accepting invitation
		Status:       1,
	}

	if err := h.userRepo.CreateWithTx(ctx, tx, newUser); err != nil {
		response.Error(c, 500, "创建用户失败")
		return
	}

	// Update user role based on invitation
	roleID := invitation.FirstRoleID()
	if err := h.userRepo.UpdateRoleWithTx(ctx, tx, newUser.ID, roleID); err != nil {
		response.Error(c, 500, "更新用户角色失败")
		return
	}

	// Add user to organization membership
	membership := &model.OrganizationMembership{
		RootTenantID:   invitation.RootTenantID,
		OrganizationID: *invitation.OrganizationID,
		UserID:         newUser.ID,
		Status:         "active",
		Version:        1,
	}

	if err := h.orgRepo.CreateMembership(ctx, tx, membership); err != nil {
		response.Error(c, 500, "加入组织失败")
		return
	}

	// Assign role from invitation to membership
	roleAssignment := &model.MembershipRoleAssignment{
		RootTenantID:   invitation.RootTenantID,
		OrganizationID: *invitation.OrganizationID,
		MembershipID:   membership.ID,
		RoleCode:       repository.GetRoleCode(roleID),
		Status:         "active",
		Version:        1,
	}

	if err := h.orgRepo.CreateRoleAssignment(ctx, tx, roleAssignment); err != nil {
		response.Error(c, 500, "分配角色失败")
		return
	}

	// Mark invitation as used
	if err := h.invitationRepo.MarkUsed(ctx, tx, invitation.ID, newUser.ID); err != nil {
		response.Error(c, 500, "标记邀请为已用失败")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交事务失败")
		return
	}

	// Invalidate any cached permissions for the new user
	if h.rbacCache != nil {
		go func(uid int64) {
			h.rbacCache.InvalidateAllForUser(middleware.GetRootTenantID(c), uid)
		}(newUser.ID)
	}

	// Generate JWT tokens for auto-login
	userRole := newUser.Role
	accessToken, refreshToken, err := h.jwtService.GenerateToken(newUser.ID, newUser.Phone, &userRole)
	if err != nil {
		response.Error(c, 500, "生成令牌失败")
		return
	}

	if err := h.jwtService.StoreRefreshToken(ctx, newUser.ID, refreshToken, 7*24*time.Hour); err != nil {
		logger.Warn("Failed to store refresh token after invite acceptance", zap.Error(err))
	}

	// Load permissions for response
	permissions := loadUserPermissions(c, h.rbacCache, newUser.ID)

	// Clear sensitive data
	newUser.PasswordHash = ""

	response.Success(c, AcceptInvitationResponse{
		InvitationID: invitation.ID,
		User:         newUser,
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(15 * time.Minute.Seconds()),
		Permissions:  permissions,
	})
}

// Details returns detailed information about a specific invitation
// GET /api/v1/invitations/:id/details
func (h *InvitationHandler) Details(c *gin.Context) {
	invitationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid invitation ID")
		return
	}

	ctx := c.Request.Context()

	invitation, err := h.invitationRepo.GetById(ctx, h.db, invitationID)
	if err != nil || invitation == nil {
		response.Error(c, 404, "邀请不存在")
		return
	}

	// Check permissions - only inviter or admin (role < 2) can view details
	if invitation.InvitedBy != middleware.GetUserID(c) && middleware.GetRole(c) >= 2 {
		response.Error(c, 403, "无权查看此邀请详情")
		return
	}

	// Get inviter info
	inviter, err := h.userRepo.GetByID(ctx, invitation.InvitedBy)
	inviterName := "未知用户"
	if err == nil && inviter != nil {
		inviterName = inviter.Nickname
	}

	response.Success(c, InvitationResponse{
		ID:        invitation.ID,
		Email:     invitation.Recipient,
		RoleName:  repository.GetRoleName(invitation.FirstRoleID()),
		ExpiresAt: invitation.ExpiresAt.Format(time.RFC3339),
		CreatedBy: inviterName,
		Status:    invitation.Status,
	})
}

// ============================================================================
// Helper Methods
// ============================================================================

func (h *InvitationHandler) checkInvitationQuota(ctx context.Context, rootTenantID, organizationID int64) (int64, error) {
	// Query quota limit from organization_quotas table
	// Max 100 pending invitations per organization by default
	return int64(100), nil // TODO: Make configurable from organization_quotas
}

func (h *InvitationHandler) resolveOrganizationFromContext(ctx context.Context, userID int64) (*int64, error) {
	// Try to resolve from authorization context validator
	if h.contextResolver != nil {
		// This would require implementation of context resolution logic
		// For now, return error to force explicit organization_id
		return nil, fmt.Errorf("context resolution requires organization_id parameter")
	}
	return nil, fmt.Errorf("no context resolver available")
}

// convertInvitationItems converts repository list items to handler response items
func convertInvitationItems(items []repository.ListInvitationsResponseItem) []InvitationListItem {
	result := make([]InvitationListItem, 0, len(items))
	for _, item := range items {
		roleID := int16(item.FirstRoleID())
		il := InvitationListItem{
			ID:          item.ID,
			Email:       item.Recipient,
			RoleID:      roleID,
			RoleName:    repository.GetRoleName(item.FirstRoleID()),
			Status:      item.Status,
			ExpiresAt:   item.ExpiresAt.Format(time.RFC3339),
			CreatedAt:   item.CreatedAt.Format(time.RFC3339),
			InviterName: item.InviterName,
		}
		if item.OrgName != nil {
			il.Organization = item.OrgName
		}
		result = append(result, il)
	}
	return result
}

// loadUserPermissions loads user permissions from RBAC cache
func loadUserPermissions(c *gin.Context, rbacCache *service.RBACCache, userID int64) []string {
	permissions := make([]string, 0)
	if rbacCache == nil {
		return permissions
	}
	loaded, err := rbacCache.GetUserPermissions(c.Request.Context(), userID)
	if err != nil {
		logger.Warn("Failed to load permissions", zap.Int64("user_id", userID), zap.Error(err))
		return permissions
	}
	if loaded == nil {
		return permissions
	}
	return loaded
}
