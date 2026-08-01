package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/mail"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
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

// RoleAssignmentInput represents one org-role assignment in a batch invitation.
type RoleAssignmentInput struct {
	OrganizationID int64  `json:"organization_id" binding:"required"`
	RoleCode       string `json:"role_code" binding:"required"`
}

// CreateInvitationRequest represents the request to create invitations.
// Supports both the batch format (emails x assignments) and the legacy
// single-invitation format (email + role_id + organization_id).
type CreateInvitationRequest struct {
	Emails       []string              `json:"emails"`
	Assignments  []RoleAssignmentInput `json:"assignments"`
	ExpiresHours int                   `json:"expires_hours" binding:"required,min=1,max=720"` // max 30 days

	// Legacy single-invitation fields (backward compatible)
	Email          string `json:"email"`
	RoleID         int    `json:"role_id"`
	OrganizationID *int64 `json:"organization_id"`
}

// CreateInvitationResult represents the outcome for a single recipient email.
type CreateInvitationResult struct {
	Email        string `json:"email"`
	InvitationID int64  `json:"invitation_id,omitempty"`
	Status       string `json:"status"` // created | duplicate | failed
	Error        string `json:"error,omitempty"`
	InviteLink   string `json:"invite_link,omitempty"` // relative link, prefix with frontend origin
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
	ID             int64     `json:"id"`
	Email          string    `json:"email"`
	RoleID         int16     `json:"role_id"`
	RoleName       string    `json:"role_name"`
	RoleCodes      []string  `json:"role_codes"`
	OrganizationID *int64    `json:"organization_id,omitempty"`
	Organization   *string   `json:"organization,omitempty"`
	Status         string    `json:"status"`
	ExpiresAt      string    `json:"expires_at"`
	CreatedAt      string    `json:"created_at"`
	InviterName    string    `json:"inviter_name"`
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

// Create generates and sends invitations.
// POST /api/v1/invitations/create
// Batch format: {"emails":["a@x.com","b@x.com"],"assignments":[{"organization_id":1,"role_code":"agent"}],"expires_hours":72}
// Legacy format: {"email":"a@x.com","role_id":2,"organization_id":1,"expires_hours":72}
func (h *InvitationHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isSystemAdmin := middleware.GetIsSystemAdmin(c)

	var req CreateInvitationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Warn("Invalid request body", zap.Error(err))
		response.Error(c, 400, "请求参数无效")
		return
	}

	// Normalize input: batch format or legacy single format
	emails := normalizeEmails(req.Emails, req.Email)
	assignments, err := normalizeAssignments(req.Assignments, req.OrganizationID, req.RoleID)
	if err != nil {
		response.Error(c, 400, err.Error())
		return
	}
	if len(emails) == 0 {
		response.Error(c, 400, "至少需要一个有效的邮箱地址")
		return
	}
	if len(assignments) == 0 {
		response.Error(c, 400, "至少需要一个组织与角色分配")
		return
	}

	// Validate role codes against the channel role model
	for _, a := range assignments {
		if !validRoleCodes[a.RoleCode] {
			response.Error(c, 400, fmt.Sprintf("无效的角色代码: %s", a.RoleCode))
			return
		}
	}

	ctx := c.Request.Context()

	// Permission: system admins may invite to any organization in the tenant;
	// organization admins (org_admin role) may invite to their own organizations.
	if !isSystemAdmin {
		ok, err := h.canCreateInvitationsFor(ctx, userID, assignments)
		if err != nil {
			logger.Error("Failed to verify org admin permission", zap.Error(err))
			response.Error(c, 500, "权限校验失败")
			return
		}
		if !ok {
			response.Error(c, 403, "无权发送邀请（需要系统管理员或目标组织管理员）")
			return
		}
	}

	// Role hierarchy check: non-system-admin inviters may only assign roles that
	// their own organization type can invite (see inviterAllowedRolesByOrgType).
	// System admins are unrestricted. Violations return a detailed 403 listing
	// every illegal assignment instead of a generic error.
	if !isSystemAdmin {
		inviterOrgTypes, err := h.inviterOrgTypes(ctx, userID)
		if err != nil {
			logger.Error("Failed to resolve inviter org types", zap.Error(err))
			response.Error(c, 500, "权限校验失败")
			return
		}
		allowed := resolveAllowedRoles(inviterOrgTypes, isSystemAdmin)
		allowedSet := make(map[string]bool, len(allowed))
		for _, r := range allowed {
			allowedSet[r] = true
		}
		var illegal []string
		for _, a := range assignments {
			if !allowedSet[a.RoleCode] {
				illegal = append(illegal, fmt.Sprintf("%s（组织 %d）", a.RoleCode, a.OrganizationID))
			}
		}
		if len(illegal) > 0 {
			response.Error(c, 403, fmt.Sprintf("无权邀请角色 %s（当前可邀请角色：%s）",
				strings.Join(illegal, "、"), strings.Join(allowed, "、")))
			return
		}
	}

	// Get inviter info
	inviter, err := h.userRepo.GetByID(ctx, userID)
	if err != nil || inviter == nil {
		response.Error(c, 404, "邀请人不存在")
		return
	}

	// Verify all target organizations belong to the caller's tenant
	callerTenantID := middleware.GetRootTenantID(c)
	orgCache := make(map[int64]*model.Organization)
	for _, a := range assignments {
		if _, ok := orgCache[a.OrganizationID]; ok {
			continue
		}
		org, err := h.orgRepo.GetByID(ctx, a.OrganizationID)
		if err != nil || org == nil {
			response.Error(c, 404, fmt.Sprintf("组织 %d 不存在", a.OrganizationID))
			return
		}
		if org.RootTenantID != callerTenantID {
			logger.Warn("Organization not in caller's tenant",
				zap.Int64("user_tenant", callerTenantID),
				zap.Int64("org_tenant", org.RootTenantID))
			response.Error(c, 403, "无法为其他租户的组织发送邀请")
			return
		}
		orgCache[a.OrganizationID] = org
	}

	// Check pending-invitation quota per organization (from organization_quotas)
	quotaChecked := make(map[int64]bool)
	for _, a := range assignments {
		if quotaChecked[a.OrganizationID] {
			continue
		}
		maxPending, err := h.checkInvitationQuota(ctx, callerTenantID, a.OrganizationID)
		if err != nil {
			logger.Error("Failed to check invitation quota", zap.Error(err))
			response.Error(c, 500, "检查配额失败")
			return
		}
		currentCount, _ := h.invitationRepo.CountByStatus(ctx, h.db, callerTenantID, a.OrganizationID, "pending")
		if currentCount+int64(len(emails)) > maxPending {
			response.Error(c, 403, fmt.Sprintf("组织 %s 的邀请名额已满（最多允许 %d 个待处理邀请）", orgCache[a.OrganizationID].Name, maxPending))
			return
		}
		quotaChecked[a.OrganizationID] = true
	}

	// Build role_assignments JSONB (same assignments for every recipient email)
	assignJSON, err := json.Marshal(assignments)
	if err != nil {
		response.Error(c, 500, "序列化角色分配失败")
		return
	}

	// Role label for the notification email (based on the first assignment)
	roleName := repository.GetRoleName(roleIDFromCode(assignments[0].RoleCode))
	orgName := orgCache[assignments[0].OrganizationID].Name

	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	now := time.Now()
	type createdItem struct {
		invitation *model.Invitation
		rawToken   string
	}
	var created []createdItem
	results := make([]CreateInvitationResult, 0, len(emails))

	for _, email := range emails {
		result := CreateInvitationResult{Email: email}

		// Generate secure token (crypto/rand)
		tokenBytes := make([]byte, 32)
		if _, err := rand.Read(tokenBytes); err != nil {
			result.Status = "failed"
			result.Error = "生成邀请码失败"
			results = append(results, result)
			continue
		}
		rawToken := hex.EncodeToString(tokenBytes)
		tokenDigest := sha256.Sum256([]byte(rawToken))

		invitation := &model.Invitation{
			RootTenantID:    callerTenantID,
			OrganizationID:  &assignments[0].OrganizationID, // primary org for legacy compatibility
			InvitedBy:       userID,
			Recipient:       email,
			TokenKeyID:      "default",
			TokenDigest:     tokenDigest[:], // raw BYTEA for DB
			RoleAssignments: string(assignJSON),
			ExpiresAt:       now.Add(time.Duration(req.ExpiresHours) * time.Hour),
			Status:          "pending",
			Version:         1,
			CreatedAt:       now,
			UpdatedAt:       now,
		}

		if err := h.invitationRepo.Insert(ctx, tx, invitation); err != nil {
			if strings.Contains(err.Error(), "uq_invitations_pending_recipient") ||
				strings.Contains(err.Error(), "unique_violation") {
				result.Status = "duplicate"
				result.Error = "该邮箱已有待处理的邀请"
			} else {
				result.Status = "failed"
				result.Error = "保存邀请失败"
				logger.Error("Invitation insert failed", zap.Error(err),
					zap.String("email", email))
			}
			results = append(results, result)
			continue
		}

		result.InvitationID = invitation.ID
		result.Status = "created"
		result.InviteLink = "/invite/" + rawToken
		results = append(results, result)
		created = append(created, createdItem{invitation: invitation, rawToken: rawToken})
	}

	if len(created) == 0 {
		_ = tx.Rollback(ctx)
		response.Success(c, gin.H{"created": 0, "results": results})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		logger.Error("Invitation commit failed", zap.Error(err))
		response.Error(c, 500, "保存邀请失败")
		return
	}

	// Async notification dispatch (email errors do not roll back the transaction)
	for _, item := range created {
		inv := item.invitation
		rawToken := item.rawToken
		go func() {
			if h.emailService == nil {
				logger.Info("Invitation created, notification dispatched",
					zap.Int64("invitation_id", inv.ID),
					zap.String("email", inv.Recipient),
					zap.String("token_hint", rawToken[:8]+"****"))
				return
			}
			emailCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			_ = emailCtx
			if err := h.emailService.SendInvitationEmail(
				inv.Recipient,
				rawToken[:8], // Show first 8 chars only in email
				roleName,
				orgName,
				req.ExpiresHours,
				"CSERGY Smart Energy Platform",
				"/invite/"+rawToken,
			); err != nil {
				logger.Warn("Failed to send invitation email",
					zap.Int64("invitation_id", inv.ID),
					zap.String("email", inv.Recipient),
					zap.Error(err))
			}
		}()
	}

	response.Success(c, gin.H{
		"created": len(created),
		"results": results,
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

	// Auto-expire stale pending invitations before listing
	if err := h.invitationRepo.MarkExpired(ctx, h.db, middleware.GetRootTenantID(c)); err != nil {
		logger.Warn("Failed to mark expired invitations", zap.Error(err))
	}

	// Build filter conditions
	filter := repository.ListInvitationsFilter{
		RootTenantID:   middleware.GetRootTenantID(c),
		Status:         query.Status,
		Email:          query.Email,
		OrganizationID: query.OrganizationID,
	}

	// Non-system admins only see invitations for their own organizations and
	// all descendant organizations (same subtree scoping as GetOrgHierarchy).
	userID := middleware.GetUserID(c)
	if !middleware.GetIsSystemAdmin(c) && userID > 0 {
		visibleIDs, err := h.visibleOrganizationIDs(ctx, filter.RootTenantID, userID)
		if err != nil {
			logger.Error("Failed to resolve visible organizations", zap.Error(err))
			response.Error(c, 500, "查询邀请列表失败")
			return
		}
		filter.OrganizationIDs = visibleIDs
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
	if invitation.InvitedBy != userID && !middleware.GetIsSystemAdmin(c) {
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

	// Parse role assignments (multi-org multi-role JSONB, legacy role_id format supported)
	assignments := invitation.ParseRoleAssignments()
	if len(assignments) == 0 {
		response.Error(c, 500, "邀请缺少角色分配信息")
		return
	}

	// Validate every target organization exists and belongs to the invitation tenant
	orgCache := make(map[int64]bool)
	for _, a := range assignments {
		orgID := a.OrganizationID
		if orgID == nil {
			orgID = invitation.OrganizationID
		}
		if orgID == nil {
			response.Error(c, 500, "组织信息错误")
			return
		}
		if orgCache[*orgID] {
			continue
		}
		org, err := h.orgRepo.GetByID(ctx, *orgID)
		if err != nil || org == nil {
			response.Error(c, 500, "组织信息错误")
			return
		}
		if org.RootTenantID != invitation.RootTenantID {
			logger.Warn("Invitation org tenant mismatch",
				zap.Int64("invitation_id", invitation.ID),
				zap.Int64("org_tenant", org.RootTenantID),
				zap.Int64("invitation_tenant", invitation.RootTenantID))
			response.Error(c, 500, "组织信息错误")
			return
		}
		orgCache[*orgID] = true
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

	// Create new user account (email registration bound to the invitation recipient)
	newUser := &model.User{
		Email:        invitation.Recipient,
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

	// Update user role based on invitation (dual permission model: role==0 -> system admin)
	roleID := invitation.FirstRoleID()
	if err := h.userRepo.UpdateRoleWithTx(ctx, tx, newUser.ID, roleID); err != nil {
		response.Error(c, 500, "更新用户角色失败")
		return
	}
	newUser.Role = roleID
	newUser.IsSystemAdmin = roleID == 0

	// Create membership + role assignment for every org-role pair in the invitation
	membershipByOrg := make(map[int64]int64) // organization_id -> membership_id (reuse within tx)
	for _, a := range assignments {
		orgID := a.OrganizationID
		if orgID == nil {
			orgID = invitation.OrganizationID
		}
		if orgID == nil {
			response.Error(c, 500, "组织信息错误")
			return
		}
		roleCode := a.RoleCode
		if roleCode == "" && a.RoleID > 0 {
			roleCode, _ = roleIDToCode[a.RoleID]
		}
		if !validRoleCodes[roleCode] {
			response.Error(c, 500, fmt.Sprintf("无效的角色代码: %s", roleCode))
			return
		}

		membershipID, ok := membershipByOrg[*orgID]
		if !ok {
			membership := &model.OrganizationMembership{
				RootTenantID:   invitation.RootTenantID,
				OrganizationID: *orgID,
				UserID:         newUser.ID,
				Status:         "active",
				Version:        1,
			}
			if err := h.orgRepo.CreateMembership(ctx, tx, membership); err != nil {
				response.Error(c, 500, "加入组织失败")
				return
			}
			membershipByOrg[*orgID] = membership.ID
			membershipID = membership.ID
		}

		roleAssignment := &model.MembershipRoleAssignment{
			RootTenantID:   invitation.RootTenantID,
			OrganizationID: *orgID,
			MembershipID:   membershipID,
			RoleCode:       roleCode,
			Status:         "active",
			Version:        1,
		}
		if err := h.orgRepo.CreateRoleAssignment(ctx, tx, roleAssignment); err != nil {
			response.Error(c, 500, "分配角色失败")
			return
		}
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

	// Invalidate any cached permissions for the new user (scoped to the invitation tenant)
	if h.rbacCache != nil {
		go func(uid int64) {
			h.rbacCache.InvalidateAllForUser(invitation.RootTenantID, uid)
		}(newUser.ID)
	}

	// Generate JWT tokens for auto-login
	accessToken, refreshToken, err := h.jwtService.GenerateToken(newUser.ID, newUser.Phone, newUser.IsSystemAdmin)
	if err != nil {
		response.Error(c, 500, "生成令牌失败")
		return
	}

	if err := h.jwtService.StoreRefreshToken(ctx, newUser.ID, refreshToken, 7*24*time.Hour); err != nil {
		logger.Warn("Failed to store refresh token after invite acceptance", zap.Error(err))
	}

	// Load permissions for response
	permissions := loadUserPermissions(c, h.userRepo, newUser.ID)

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

// canCreateInvitationsFor reports whether the user is an org_admin of every
// target organization (used for non-system-admin invitation creation).
func (h *InvitationHandler) canCreateInvitationsFor(ctx context.Context, userID int64, assignments []RoleAssignmentInput) (bool, error) {
	seen := make(map[int64]bool)
	for _, a := range assignments {
		if seen[a.OrganizationID] {
			continue
		}
		seen[a.OrganizationID] = true

		var isAdmin bool
		err := h.db.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1
				FROM membership_role_assignments ra
				JOIN organization_memberships m
				  ON m.id = ra.membership_id AND m.organization_id = ra.organization_id
				WHERE ra.organization_id = $1 AND m.user_id = $2
				  AND ra.role_code = 'org_admin' AND ra.status = 'active' AND m.status = 'active'
			)
		`, a.OrganizationID, userID).Scan(&isAdmin)
		if err != nil {
			return false, err
		}
		if !isAdmin {
			return false, nil
		}
	}
	return true, nil
}

// CopyLink returns guidance for invitation links.
// The DB only stores the SHA-256 token digest, so the raw token cannot be
// recovered; the full link is only returned once at creation time.
// GET /api/v1/invitations/:id/copy-link
func (h *InvitationHandler) CopyLink(c *gin.Context) {
	invitationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid invitation ID")
		return
	}

	ctx := c.Request.Context()
	userID := middleware.GetUserID(c)

	invitation, err := h.invitationRepo.GetById(ctx, h.db, invitationID)
	if err != nil || invitation == nil {
		response.Error(c, 404, "邀请不存在")
		return
	}

	// Only the inviter or a system admin may request the link
	if invitation.InvitedBy != userID && !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "无权获取此邀请链接")
		return
	}

	response.SuccessWithMessage(c, "邀请链接仅在创建时可见，如需重新邀请请创建新的邀请", gin.H{
		"invitation_id": invitation.ID,
		"email":        invitation.Recipient,
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
	if invitation.InvitedBy != middleware.GetUserID(c) && !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "无权查看此邀请详情")
		return
	}

	// Get inviter info
	inviter, err := h.userRepo.GetByID(ctx, invitation.InvitedBy)
	inviterName := "未知用户"
	if err == nil && inviter != nil {
		inviterName = inviter.Nickname
	}

	roleCodes := parseRoleCodes(invitation.RoleAssignments)
	roleName := strings.Join(roleCodes, ", ")
	if roleName == "" {
		roleName = repository.GetRoleName(invitation.FirstRoleID())
	}

	response.Success(c, InvitationResponse{
		ID:        invitation.ID,
		Email:     invitation.Recipient,
		RoleName:  roleName,
		ExpiresAt: invitation.ExpiresAt.Format(time.RFC3339),
		CreatedBy: inviterName,
		Status:    invitation.Status,
	})
}

// ============================================================================
// Helper Methods
// ============================================================================

// visibleOrganizationIDs returns the caller's own active organizations plus
// every descendant (via organization_closure) — the same subtree scoping used
// by GetOrgHierarchy for non-system admins. The closure table includes self
// rows, so own organizations are covered automatically.
func (h *InvitationHandler) visibleOrganizationIDs(ctx context.Context, tenantID, userID int64) ([]int64, error) {
	visible := make(map[int64]struct{})
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT organization_id
		FROM organization_memberships
		WHERE user_id = $1 AND root_tenant_id = $2 AND status = 'active'
	`, userID, tenantID)
	if err != nil {
		return nil, err
	}
	var ownIDs []int64
	for rows.Next() {
		var oid int64
		if err := rows.Scan(&oid); err == nil {
			ownIDs = append(ownIDs, oid)
			visible[oid] = struct{}{}
		}
	}
	rows.Close()

	if len(ownIDs) > 0 {
		descRows, err := h.db.Query(ctx, `
			SELECT DISTINCT descendant_id
			FROM organization_closure
			WHERE root_tenant_id = $1 AND ancestor_id = ANY($2)
		`, tenantID, ownIDs)
		if err != nil {
			return nil, err
		}
		for descRows.Next() {
			var did int64
			if err := descRows.Scan(&did); err == nil {
				visible[did] = struct{}{}
			}
		}
		descRows.Close()
	}

	ids := make([]int64, 0, len(visible))
	for id := range visible {
		ids = append(ids, id)
	}
	return ids, nil
}

func (h *InvitationHandler) checkInvitationQuota(ctx context.Context, rootTenantID, organizationID int64) (int64, error) {
	// Query the real quota from organization_quotas (initialized at org creation
	// with resource_type = 'pending_invitations'); fall back to 20 if unset.
	var quota int64
	err := h.db.QueryRow(ctx, `
		SELECT quota_limit FROM organization_quotas
		WHERE root_tenant_id = $1 AND organization_id = $2 AND resource_type = 'pending_invitations'
	`, rootTenantID, organizationID).Scan(&quota)
	if err != nil {
		if err == pgx.ErrNoRows {
			return 20, nil
		}
		return 0, err
	}
	if quota <= 0 {
		return 20, nil
	}
	return quota, nil
}

// validRoleCodes is the canonical channel role model for invitations.
var validRoleCodes = map[string]bool{
	"org_admin":   true,
	"agent":       true,
	"distributor": true,
	"installer":   true,
	"customer":    true,
}

// inviterAllowedRolesByOrgType restricts which channel roles an inviter may
// assign, based on the inviter's own organization type:
//
//	manufacturer -> {agent, distributor, installer, customer}
//	agent        -> {installer, customer}
//	distributor  -> {installer, customer}
//	installer    -> {customer}
//	customer     -> (cannot invite channel roles)
//
// org_admin is a management role (not a channel identity) and stays assignable
// everywhere; it is appended by resolveAllowedRoles.
var inviterAllowedRolesByOrgType = map[string][]string{
	"manufacturer": {"agent", "distributor", "installer", "customer"},
	"agent":        {"installer", "customer"},
	"distributor":  {"installer", "customer"},
	"installer":    {"customer"},
	"customer":     nil,
}

// resolveAllowedRoles returns the role codes an inviter may assign.
// System admins may assign every role; other inviters get the union over their
// own organization types plus org_admin. Multiple memberships yield the union
// of the allowed sets of every involved org type.
func resolveAllowedRoles(inviterOrgTypes []string, isSystemAdmin bool) []string {
	if isSystemAdmin {
		return []string{"agent", "distributor", "installer", "customer", "org_admin"}
	}
	allowed := []string{"org_admin"} // management role is always assignable
	seen := map[string]bool{"org_admin": true}
	for _, t := range inviterOrgTypes {
		for _, r := range inviterAllowedRolesByOrgType[t] {
			if !seen[r] {
				seen[r] = true
				allowed = append(allowed, r)
			}
		}
	}
	return allowed
}

// inviterOrgTypes returns the distinct org types of the user's active
// memberships (orgs not deleted).
func (h *InvitationHandler) inviterOrgTypes(ctx context.Context, userID int64) ([]string, error) {
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT o.org_type
		FROM organization_memberships m
		JOIN organizations o ON o.id = m.organization_id
		WHERE m.user_id = $1 AND m.status = 'active' AND o.deleted_at IS NULL
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var types []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		types = append(types, t)
	}
	return types, rows.Err()
}

// roleIDToCode maps legacy numeric role IDs to role codes.
var roleIDToCode = map[int]string{
	1: "org_admin",
	2: "agent",
	3: "distributor",
	4: "installer",
	5: "customer",
}

// roleIDFromCode maps a role code back to its legacy numeric ID; returns 5 (customer) if unknown.
func roleIDFromCode(code string) int {
	for id, c := range roleIDToCode {
		if c == code {
			return id
		}
	}
	return 5
}

// normalizeEmails deduplicates, trims and validates recipient emails.
func normalizeEmails(emails []string, legacyEmail string) []string {
	seen := make(map[string]bool)
	var out []string
	add := func(raw string) {
		e := strings.ToLower(strings.TrimSpace(raw))
		if e == "" || seen[e] {
			return
		}
		if _, err := mail.ParseAddress(e); err != nil {
			return
		}
		seen[e] = true
		out = append(out, e)
	}
	if legacyEmail != "" {
		add(legacyEmail)
	}
	for _, e := range emails {
		add(e)
	}
	return out
}

// normalizeAssignments converts legacy single-org payloads into the
// canonical assignments format.
func normalizeAssignments(assignments []RoleAssignmentInput, legacyOrgID *int64, legacyRoleID int) ([]RoleAssignmentInput, error) {
	if len(assignments) > 0 {
		return assignments, nil
	}
	if legacyOrgID != nil && *legacyOrgID > 0 && legacyRoleID > 0 {
		roleCode, ok := roleIDToCode[legacyRoleID]
		if !ok {
			return nil, fmt.Errorf("无效的角色 ID: %d", legacyRoleID)
		}
		return []RoleAssignmentInput{{OrganizationID: *legacyOrgID, RoleCode: roleCode}}, nil
	}
	return nil, nil
}

// parseRoleCodes extracts role codes from a role_assignments JSONB string.
func parseRoleCodes(roleAssignmentsJSON string) []string {
	if roleAssignmentsJSON == "" || roleAssignmentsJSON == "[]" {
		return nil
	}
	var items []model.RoleAssignmentItem
	if err := json.Unmarshal([]byte(roleAssignmentsJSON), &items); err != nil {
		return nil
	}
	codes := make([]string, 0, len(items))
	for _, it := range items {
		if it.RoleCode != "" {
			codes = append(codes, it.RoleCode)
		} else if it.RoleID > 0 {
			if code, ok := roleIDToCode[it.RoleID]; ok {
				codes = append(codes, code)
			}
		}
	}
	return codes
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
			RoleCodes:   parseRoleCodes(item.RoleAssignments),
			Status:      item.Status,
			ExpiresAt:   item.ExpiresAt.Format(time.RFC3339),
			CreatedAt:   item.CreatedAt.Format(time.RFC3339),
			InviterName: item.InviterName,
		}
		if item.OrganizationID != nil {
			orgID := *item.OrganizationID
			il.OrganizationID = &orgID
		}
		if item.OrgName != nil {
			il.Organization = item.OrgName
		}
		result = append(result, il)
	}
	return result
}

// loadUserPermissions loads user permissions from the new organization-based permission system.
// Falls back to empty list if the repository is unavailable.
func loadUserPermissions(c *gin.Context, userRepo *repository.UserRepository, userID int64) []string {
	permissions := make([]string, 0)
	if userRepo == nil {
		return permissions
	}
	user, err := userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		if err != nil {
			logger.Warn("Failed to load user for permissions", zap.Int64("user_id", userID), zap.Error(err))
		}
		return permissions
	}
	// In the new system, system admins have all permissions
	if user.IsSystemAdmin {
		return []string{"*"}
	}
	// For non-admin users, return empty list during migration period
	// (full permission loading is handled by AuthorizationRepository.LoadAllPermissionCodes)
	return permissions
}
