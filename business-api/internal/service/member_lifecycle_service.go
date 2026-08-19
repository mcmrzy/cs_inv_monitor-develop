package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"inv-api-server/internal/job"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"github.com/jackc/pgx/v5"
	"go.uber.org/zap"
)

// ==================== Error Types ====================

// ServiceError carries an HTTP-style status code and message from the service layer
type MemberServiceError struct {
	Code    int
	Message string
}

func (e *MemberServiceError) Error() string {
	return e.Message
}

func newServiceError(code int, message string) *MemberServiceError {
	return &MemberServiceError{Code: code, Message: message}
}

// ==================== Param / Result Types ====================

type AddMemberParams struct {
	UserID         int64
	OrganizationID int64
	MembershipType string
	ExpiresAt      *time.Time
}

type AddMemberResult struct {
	OrganizationID int64
	UserID         int64
}

type UpdateMembershipParams struct {
	Status       *string
	ExpiresAt    *time.Time
}

type TransferResult struct {
	OrganizationID int64
	PendingCount   int // 创建的待审批申请数
}

// TransferRequestInfo 转移申请展示信息（对齐前端 TransferRequest 类型）
type TransferRequestInfo struct {
	ID             int64     `json:"id"`
	ResourceType   string    `json:"resource_type"` // 恒为 "user"
	ResourceID     int64     `json:"resource_id"`   // 被转移用户 ID
	MembershipID   int64     `json:"membership_id"`
	FromOrgID      int64     `json:"from_org_id"`
	FromOrgName    string    `json:"from_org_name"`
	ToOrgID        int64     `json:"to_org_id"`
	ToOrgName      string    `json:"to_org_name"`
	RequesterID    int64     `json:"requester_id"`
	RequesterEmail string    `json:"requester_email"`
	UserEmail      string    `json:"user_email"`
	UserNickname   string    `json:"user_nickname"`
	Reason         string    `json:"reason"`
	Status         string    `json:"status"` // pending/approved/rejected
	CreatedAt      time.Time `json:"created_at"`
}

// ListTransfersResult 转移申请分页结果
type ListTransfersResult struct {
	Items []TransferRequestInfo
	Total int64
	Page  int
	Size  int
}

type BulkAddParams struct {
	UserIDs        []int64
	OrganizationID int64
	MembershipType string
	ExpiresAt      *time.Time
}

// UserLookupResult 按邮箱查用户结果（含当前所属组织，供添加成员表单展示）
type UserLookupResult struct {
	UserID        int64         `json:"user_id"`
	Email         string        `json:"email"`
	Nickname      string        `json:"nickname"`
	Phone         string        `json:"phone"`
	IsSystemAdmin bool          `json:"is_system_admin"`
	Memberships   []UserOrgInfo `json:"memberships"`
}

// UserOrgInfo 用户所属组织信息
type UserOrgInfo struct {
	MembershipID   int64     `json:"membership_id"`
	OrganizationID int64     `json:"organization_id"`
	OrgName        string    `json:"org_name"`
	OrgType        string    `json:"org_type"`
	JoinedAt       time.Time `json:"joined_at"`
}

type BulkAddResult struct {
	OrganizationID   int64
	AddedCount       int
	IsAsync          bool
	JobID            string
	StatusURL        string
	WSURL            string
	TotalItems       int
}

type BulkTransferParams struct {
	MembershipIDs []int64
	TargetOrgID   int64
	Reason        string
}

type BulkTransferResult struct {
	OrganizationID   int64
	TransferredCount int
	IsAsync          bool
	JobID            string
	StatusURL        string
	WSURL            string
	TotalItems       int
}

// ==================== Service ====================

// MemberLifecycleService contains all business logic for member lifecycle operations
type MemberLifecycleService struct {
	repo     *repository.MemberLifecycleRepository
	jobStore *job.JobStore
}

// NewMemberLifecycleService creates a new member lifecycle service
func NewMemberLifecycleService(repo *repository.MemberLifecycleRepository, jobStore *job.JobStore) *MemberLifecycleService {
	return &MemberLifecycleService{
		repo:     repo,
		jobStore: jobStore,
	}
}

// ==================== Add Member ====================

func (s *MemberLifecycleService) AddMember(ctx context.Context, actorUserID int64, tenantID int64, req AddMemberParams) (*AddMemberResult, error) {
	// Validate target user exists
	targetUser, err := s.repo.GetUserByID(ctx, req.UserID)
	if err != nil || targetUser == nil {
		return nil, newServiceError(404, "用户不存在")
	}

	// Validate target organization exists
	targetOrg, err := s.repo.GetOrgByID(ctx, req.OrganizationID)
	if err != nil || targetOrg == nil {
		return nil, newServiceError(404, "组织不存在")
	}

	// Tenant isolation & management permission:
	// 系统管理员可跨租户管理任意组织；其他用户须与组织同租户且管理该组织
	// （管理范围 = 目标组织自身或其祖先组织上的 active org_admin，与邀请流程一致）
	if targetOrg.RootTenantID != tenantID {
		isSysAdmin, aerr := s.repo.IsSystemAdmin(ctx, actorUserID)
		if aerr != nil {
			logger.Error("AddMember admin check failed", zap.Error(aerr))
			return nil, newServiceError(500, "权限校验失败")
		}
		if !isSysAdmin {
			return nil, newServiceError(403, "无权操作此组织")
		}
	} else {
		canManage, cerr := s.repo.CanManageOrg(ctx, actorUserID, req.OrganizationID)
		if cerr != nil {
			logger.Error("AddMember permission check failed", zap.Error(cerr))
			return nil, newServiceError(500, "权限校验失败")
		}
		if !canManage {
			return nil, newServiceError(403, "无权管理该组织，无法添加成员")
		}
	}

	// Check quota before adding（以组织所属租户计）
	usage, err := s.repo.CheckQuota(ctx, targetOrg.RootTenantID)
	if err != nil {
		logger.Error("AddMember quota check failed", zap.Error(err))
		return nil, newServiceError(500, "检查配额失败")
	}
	if usage.UserLimit > 0 && usage.UserCount >= usage.UserLimit {
		return nil, newServiceError(409, "已达用户数上限，无法添加新成员")
	}

	// Check if already a member with active status
	existing, _ := s.repo.GetExistingMembership(ctx, req.UserID, req.OrganizationID)
	if existing != nil && existing.Status == "active" {
		return nil, newServiceError(409, "该用户已是此组织活跃成员")
	}

	// 单一身份约束：用户已属于其他组织的活跃成员时不允许直接添加，
	// 需先在原组织移除或发起转移审批，避免击穿“一人一组织”身份模型
	currentOrgs, _ := s.repo.GetUserActiveMembershipsWithOrgs(ctx, req.UserID)
	for _, om := range currentOrgs {
		if om.OrganizationID != req.OrganizationID {
			return nil, newServiceError(409, fmt.Sprintf("该用户已属于组织「%s」，请先移除或发起转移审批", om.OrgName))
		}
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	if existing != nil && existing.Status != "active" {
		// Reactivate existing membership
		rowsAffected, err := s.repo.ReactivateMembership(ctx, tx, existing.ID, req.ExpiresAt)
		if err != nil {
			return nil, newServiceError(409, "更新成员关系失败")
		}
		if rowsAffected == 0 {
			return nil, newServiceError(404, "原成员记录已失效")
		}
	} else {
		// Create new membership
		if err := s.repo.CreateMembership(ctx, tx, tenantID, req.OrganizationID, req.UserID, req.ExpiresAt); err != nil {
			return nil, newServiceError(409, "添加成员失败：约束冲突")
		}
	}

	// Invalidate authorization cache
	s.repo.InvalidateAuthCache(tenantID, req.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		return nil, newServiceError(500, "保存成员记录失败")
	}

	// Async audit logging
	s.auditLog(actorUserID, "member.add", req.OrganizationID, map[string]interface{}{
		"user_id":          req.UserID,
		"membership_type":  req.MembershipType,
		"new_member_count": usage.UserCount + 1,
	})

	return &AddMemberResult{
		OrganizationID: req.OrganizationID,
		UserID:         req.UserID,
	}, nil
}

// ==================== Update Membership ====================

func (s *MemberLifecycleService) UpdateMembership(ctx context.Context, actorUserID int64, tenantID int64, membershipID int64, req UpdateMembershipParams) error {
	// Fetch current membership
	membership, err := s.repo.GetMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		return newServiceError(404, "成员关系不存在")
	}

	// Verify ownership/access
	if membership.RootTenantID != tenantID {
		return newServiceError(403, "无权访问此组织成员关系")
	}

	// Validate status if provided
	if req.Status != nil {
		validStatus := map[string]bool{"active": true, "inactive": true, "suspended": true}
		if !validStatus[*req.Status] {
			return newServiceError(400, "无效的状态值")
		}
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	if err := s.repo.UpdateMembershipFields(ctx, tx, membershipID, req.Status, req.ExpiresAt); err != nil {
		return newServiceError(500, "更新成员信息失败")
	}

	s.repo.InvalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "保存更新失败")
	}

	s.auditLog(actorUserID, "member.update", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"changed_fields": map[string]interface{}{
			"status":     req.Status,
			"expires_at": req.ExpiresAt,
		},
	})

	return nil
}

// ==================== Update Member Role ====================

// roleParentType 角色对应的父组织类型（层级：manufacturer -> agent -> distributor -> installer）
var roleParentType = map[string]string{
	"agent":       "manufacturer",
	"distributor": "agent",
	"installer":   "distributor",
	"customer":    "installer",
}

var roleNameZH = map[string]string{
	"agent":       "代理商组织",
	"distributor": "经销商组织",
	"installer":   "安装商组织",
	"customer":    "终端用户组织",
}

// UpdateMemberRole 设置成员角色（单一身份）：
// 将成员关系切换到目标角色对应的组织，若租户下不存在该类型组织则自动创建；
// 同时撤销该用户的其他所有活跃成员关系，确保一个用户只对应一个角色。
func (s *MemberLifecycleService) UpdateMemberRole(ctx context.Context, actorUserID int64, tenantID int64, membershipID int64, role string) error {
	validRoles := map[string]bool{"agent": true, "distributor": true, "installer": true, "customer": true}
	if !validRoles[role] {
		return newServiceError(400, "无效的角色")
	}

	membership, err := s.repo.GetMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		return newServiceError(404, "成员关系不存在")
	}
	if membership.RootTenantID != tenantID {
		return newServiceError(403, "无权访问此组织成员关系")
	}
	if membership.Status != "active" {
		return newServiceError(400, "成员关系已失效")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	targetOrgID, err := s.ensureOrgByRole(ctx, tx, tenantID, role)
	if err != nil {
		return newServiceError(500, "组织准备失败")
	}

	if err := s.repo.UpdateMembershipOrg(ctx, tx, membershipID, targetOrgID, role); err != nil {
		return newServiceError(500, "更新成员角色失败")
	}
	// 单一身份：撤销该用户的其他所有活跃成员关系
	if _, err := s.repo.RevokeOtherMemberships(ctx, tx, membership.UserID, membershipID); err != nil {
		return newServiceError(500, "更新成员角色失败")
	}

	s.repo.InvalidateAuthCache(membership.RootTenantID, membership.OrganizationID)
	s.repo.InvalidateAuthCache(tenantID, targetOrgID)

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "保存更新失败")
	}

	s.auditLog(actorUserID, "member.update_role", targetOrgID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
		"role":          role,
	})
	return nil
}

// ensureOrgByRole 确保租户下存在指定角色类型的组织，不存在则按层级自动创建
func (s *MemberLifecycleService) ensureOrgByRole(ctx context.Context, tx pgx.Tx, tenantID int64, role string) (int64, error) {
	orgID, err := s.repo.FindOrgByType(ctx, tx, tenantID, role)
	if err != nil {
		return 0, err
	}
	if orgID > 0 {
		return orgID, nil
	}
	parentType := roleParentType[role]
	var parentID int64
	if parentType == "manufacturer" {
		parentID = tenantID // 根厂家组织 id = root_tenant_id
	} else {
		parentID, err = s.ensureOrgByRole(ctx, tx, tenantID, parentType)
		if err != nil {
			return 0, err
		}
	}
	return s.repo.CreateOrgForRole(ctx, tx, tenantID, parentID, role, roleNameZH[role])
}

// ==================== Remove Member ====================

func (s *MemberLifecycleService) RemoveMember(ctx context.Context, actorUserID int64, membershipID int64, reason string) error {
	membership, err := s.repo.GetMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		return newServiceError(404, "成员关系不存在")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	rowsAffected, err := s.repo.UpdateMembershipStatus(ctx, tx, membershipID, "revoked", "active")
	if err != nil {
		return newServiceError(500, "删除成员失败")
	}
	if rowsAffected == 0 {
		return newServiceError(404, "成员记录已不存在或已删除")
	}

	s.repo.InvalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "保存更改失败")
	}

	s.auditLog(actorUserID, "member.remove", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
		"reason":        reason,
	})

	return nil
}

// ==================== Deactivate / Reactivate ====================

func (s *MemberLifecycleService) DeactivateMember(ctx context.Context, actorUserID int64, membershipID int64, reason string) error {
	membership, err := s.repo.GetMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		return newServiceError(404, "成员关系不存在")
	}

	if membership.Status != "active" {
		return newServiceError(409, "成员已经是非活跃状态")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	rowsAffected, err := s.repo.UpdateMembershipStatus(ctx, tx, membershipID, "inactive", "active")
	if err != nil {
		return newServiceError(500, "停用成员失败")
	}
	if rowsAffected == 0 {
		return newServiceError(409, "成员状态未改变")
	}

	s.repo.InvalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "保存停用失败")
	}

	s.auditLog(actorUserID, "member.deactivate", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
		"reason":        reason,
	})

	return nil
}

func (s *MemberLifecycleService) ReactivateMember(ctx context.Context, actorUserID int64, membershipID int64) error {
	membership, err := s.repo.GetMembershipByID(ctx, membershipID)
	if err != nil || membership == nil {
		return newServiceError(404, "成员关系不存在")
	}

	if membership.Status == "active" {
		return newServiceError(409, "成员已经是活跃状态")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	rowsAffected, err := s.repo.UpdateMembershipStatusWithCondition(ctx, tx, membershipID, "active", []string{"inactive", "suspended"})
	if err != nil {
		return newServiceError(500, "恢复成员失败")
	}
	if rowsAffected == 0 {
		return newServiceError(409, "成员状态未改变")
	}

	s.repo.InvalidateAuthCache(membership.RootTenantID, membership.OrganizationID)

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "保存恢复失败")
	}

	s.auditLog(actorUserID, "member.reactivate", membership.OrganizationID, map[string]interface{}{
		"membership_id": membershipID,
		"user_id":       membership.UserID,
	})

	return nil
}

// ==================== Transfer ====================

// TransferInitiate 发起成员转移审批：校验发起人管理每个成员的源组织后，
// 创建 pending 转移申请（不动 membership）；真实转移在目标组织管理员
// 审批通过后由 TransferAccept 执行。
func (s *MemberLifecycleService) TransferInitiate(ctx context.Context, actorUserID int64, membershipIDs []int64, targetOrgID int64, reason string) (*TransferResult, error) {
	if len(membershipIDs) == 0 {
		return nil, newServiceError(400, "请选择要转移的成员")
	}

	// Fetch all memberships
	memberships, err := s.repo.GetMembershipsByIDList(ctx, membershipIDs)
	if err != nil || len(memberships) == 0 {
		return nil, newServiceError(404, "未找到有效的成员关系")
	}

	// Validate all memberships belong to same root_tenant and are active
	rootTenantID := memberships[0].RootTenantID
	sourceOrgID := memberships[0].OrganizationID

	for _, m := range memberships {
		if m.RootTenantID != rootTenantID {
			return nil, newServiceError(409, "跨租户批量转移不支持，请确保所有成员属于同一租户")
		}
		if m.Status != "active" {
			return nil, newServiceError(400, fmt.Sprintf("成员 ID=%d 不是活跃状态", m.ID))
		}
	}

	// Verify target org exists and belongs to same tenant
	targetOrg, err := s.repo.GetOrgByID(ctx, targetOrgID)
	if err != nil || targetOrg == nil {
		return nil, newServiceError(404, "目标组织不存在")
	}
	if targetOrg.RootTenantID != rootTenantID {
		return nil, newServiceError(403, "目标组织不在同一租户下")
	}

	// 发起人权限：须管理每个成员的源组织（源组织 org_admin 或系统管理员）
	managedSources := make(map[int64]bool)
	for _, m := range memberships {
		if managedSources[m.OrganizationID] {
			continue
		}
		canManage, cerr := s.repo.CanManageOrg(ctx, actorUserID, m.OrganizationID)
		if cerr != nil {
			logger.Error("TransferInitiate source permission check failed", zap.Error(cerr))
			return nil, newServiceError(500, "权限校验失败")
		}
		if !canManage {
			return nil, newServiceError(403, "无权转移其他组织的成员")
		}
		managedSources[m.OrganizationID] = true
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	// 幂等：已在目标组织或已有待审批申请的成员跳过
	pendingCount := 0
	for _, membership := range memberships {
		if membership.OrganizationID == targetOrg.ID {
			continue
		}
		hasPending, herr := s.repo.HasPendingTransferRequest(ctx, membership.ID)
		if herr != nil {
			logger.Error("TransferInitiate pending check failed", zap.Error(herr))
			return nil, newServiceError(500, "检查转移申请状态失败")
		}
		if hasPending {
			continue
		}
		if err := s.repo.CreateTransferRequest(ctx, tx, rootTenantID, membership.ID, membership.UserID, membership.OrganizationID, targetOrg.ID, actorUserID, reason); err != nil {
			return nil, newServiceError(500, "创建转移申请失败")
		}
		pendingCount++
	}

	if pendingCount == 0 {
		return nil, newServiceError(409, "所选成员均已在目标组织或已存在待审批的转移申请")
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, newServiceError(500, "提交转移申请失败")
	}

	s.auditLog(actorUserID, "member.transfer.initiate", targetOrg.ID, map[string]interface{}{
		"source_org_id":   sourceOrgID,
		"target_org_id":   targetOrg.ID,
		"requested_users": membershipIDsToUserIDs(memberships),
		"pending_count":   pendingCount,
		"reason":          reason,
	})

	return &TransferResult{
		OrganizationID: targetOrg.ID,
		PendingCount:   pendingCount,
	}, nil
}

// TransferAccept 审批通过转移申请：目标组织管理员（或系统管理员）审批后，
// 在同一事务内执行真实的 membership 转移（删旧建新）并更新申请状态为 approved。
func (s *MemberLifecycleService) TransferAccept(ctx context.Context, actorUserID int64, transferID int64) error {
	req, err := s.repo.GetTransferRequestByID(ctx, transferID)
	if err != nil {
		logger.Error("TransferAccept load failed", zap.Error(err))
		return newServiceError(500, "读取转移申请失败")
	}
	if req == nil {
		return newServiceError(404, "转移申请不存在")
	}
	if req.Status != "pending" {
		return newServiceError(400, "转移申请已被处理")
	}

	// 审批人权限：须管理目标组织（to_org 祖先链上的 active org_admin 或系统管理员）
	can, cerr := s.repo.CanManageOrg(ctx, actorUserID, req.ToOrgID)
	if cerr != nil {
		logger.Error("TransferAccept permission check failed", zap.Error(cerr))
		return newServiceError(500, "权限校验失败")
	}
	if !can {
		return newServiceError(403, "仅目标组织管理员可审批此转移")
	}

	// 成员关系须仍为活跃且仍位于源组织（申请后可能已被移除/转移）
	membership, merr := s.repo.GetMembershipByID(ctx, req.MembershipID)
	if merr != nil || membership == nil || membership.Status != "active" || membership.OrganizationID != req.FromOrgID {
		return newServiceError(409, "成员关系已失效，无法执行转移")
	}

	// 目标组织须仍存在且同租户
	targetOrg, oerr := s.repo.GetOrgByID(ctx, req.ToOrgID)
	if oerr != nil || targetOrg == nil || targetOrg.RootTenantID != membership.RootTenantID {
		return newServiceError(409, "目标组织已失效，无法执行转移")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	if err := s.repo.DeleteMembership(ctx, tx, membership.ID); err != nil {
		return newServiceError(500, "移除旧成员关系失败")
	}

	// 若用户尚未存在于目标组织则创建（审批期间状态可能变化，避免唯一索引冲突）
	existingInTarget, _ := s.repo.GetExistingMembership(ctx, membership.UserID, targetOrg.ID)
	if existingInTarget == nil {
		if _, err := s.repo.CreateMembershipInOrg(ctx, tx, targetOrg.RootTenantID, targetOrg.ID, membership.UserID, membership.ExpiresAt); err != nil {
			return newServiceError(500, "添加到目标组织失败")
		}
	}

	rowsAffected, err := s.repo.UpdateTransferRequestStatus(ctx, tx, transferID, "pending", "approved", "")
	if err != nil {
		return newServiceError(500, "更新转移申请失败")
	}
	if rowsAffected == 0 {
		return newServiceError(409, "转移申请已被处理")
	}

	// Invalidate authorization caches for both orgs
	s.repo.InvalidateAuthCache(membership.RootTenantID, membership.OrganizationID)
	s.repo.InvalidateAuthCache(membership.RootTenantID, targetOrg.ID)

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "提交成员转移失败")
	}

	s.auditLog(actorUserID, "member.transfer.accept", targetOrg.ID, map[string]interface{}{
		"transfer_id":   transferID,
		"membership_id": req.MembershipID,
		"user_id":       req.UserID,
		"from_org_id":   req.FromOrgID,
		"to_org_id":     req.ToOrgID,
	})

	return nil
}

// TransferReject 拒绝转移申请：目标组织管理员（或系统管理员）可拒绝，reason 可选。
func (s *MemberLifecycleService) TransferReject(ctx context.Context, actorUserID int64, transferID int64, reason string) error {
	req, err := s.repo.GetTransferRequestByID(ctx, transferID)
	if err != nil {
		logger.Error("TransferReject load failed", zap.Error(err))
		return newServiceError(500, "读取转移申请失败")
	}
	if req == nil {
		return newServiceError(404, "转移申请不存在")
	}
	if req.Status != "pending" {
		return newServiceError(400, "转移申请已被处理")
	}

	can, cerr := s.repo.CanManageOrg(ctx, actorUserID, req.ToOrgID)
	if cerr != nil {
		logger.Error("TransferReject permission check failed", zap.Error(cerr))
		return newServiceError(500, "权限校验失败")
	}
	if !can {
		return newServiceError(403, "仅目标组织管理员可审批此转移")
	}

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	rowsAffected, err := s.repo.UpdateTransferRequestStatus(ctx, tx, transferID, "pending", "rejected", reason)
	if err != nil {
		return newServiceError(500, "更新转移申请失败")
	}
	if rowsAffected == 0 {
		return newServiceError(409, "转移申请已被处理")
	}

	if err := tx.Commit(ctx); err != nil {
		return newServiceError(500, "保存更新失败")
	}

	s.auditLog(actorUserID, "member.transfer.reject", req.ToOrgID, map[string]interface{}{
		"transfer_id": transferID,
		"user_id":     req.UserID,
		"from_org_id": req.FromOrgID,
		"to_org_id":   req.ToOrgID,
		"reason":      reason,
	})

	return nil
}

// ListTransfers 查询当前用户可审批的转移申请（分页）：
// 系统管理员可见全部；组织管理员可见目标组织在其管理范围内的申请。
func (s *MemberLifecycleService) ListTransfers(ctx context.Context, viewerUserID int64, page, pageSize int, status string) (*ListTransfersResult, error) {
	isSysAdmin, err := s.repo.IsSystemAdmin(ctx, viewerUserID)
	if err != nil {
		logger.Error("ListTransfers admin check failed", zap.Error(err))
		return nil, newServiceError(500, "查询转移申请失败")
	}

	rows, total, err := s.repo.ListTransferRequests(ctx, viewerUserID, isSysAdmin, page, pageSize, status)
	if err != nil {
		logger.Error("ListTransfers query failed", zap.Error(err))
		return nil, newServiceError(500, "查询转移申请失败")
	}

	items := make([]TransferRequestInfo, len(rows))
	for i, t := range rows {
		items[i] = TransferRequestInfo{
			ID:             t.ID,
			ResourceType:   "user",
			ResourceID:     t.UserID,
			MembershipID:   t.MembershipID,
			FromOrgID:      t.FromOrgID,
			FromOrgName:    t.FromOrgName,
			ToOrgID:        t.ToOrgID,
			ToOrgName:      t.ToOrgName,
			RequesterID:    t.InitiatorID,
			RequesterEmail: t.InitiatorEmail,
			UserEmail:      t.UserEmail,
			UserNickname:   t.UserNickname,
			Reason:         t.Reason,
			Status:         t.Status,
			CreatedAt:      t.CreatedAt,
		}
	}

	return &ListTransfersResult{
		Items: items,
		Total: total,
		Page:  page,
		Size:  pageSize,
	}, nil
}

// ==================== List Members ====================

// ListMembersResult represents the paginated result of listing members
type ListMembersResult struct {
	Items []repository.OrgMemberWithUser
	Total int64
	Page  int
	Size  int
}

// ListMembers lists all members of an organization, optionally filtered by role
func (s *MemberLifecycleService) ListMembers(ctx context.Context, orgID int64, page, pageSize int, roleFilter string) (*ListMembersResult, error) {
	members, total, err := s.repo.ListMembersByOrgID(ctx, orgID, page, pageSize, roleFilter)
	if err != nil {
		logger.Error("ListMembers query failed", zap.Int64("org_id", orgID), zap.Error(err))
		return nil, newServiceError(500, "查询成员列表失败")
	}

	return &ListMembersResult{
		Items: members,
		Total: total,
		Page:  page,
		Size:  pageSize,
	}, nil
}

// ==================== User Lookup ====================

// GetUserByEmail 按邮箱查找系统用户及其当前所属组织（添加成员表单的查询接口）。
// 权限：系统管理员或任意组织管理员可调用。
func (s *MemberLifecycleService) GetUserByEmail(ctx context.Context, actorUserID int64, email string) (*UserLookupResult, error) {
	email = strings.TrimSpace(email)
	if email == "" {
		return nil, newServiceError(400, "请输入邮箱")
	}

	isSysAdmin, err := s.repo.IsSystemAdmin(ctx, actorUserID)
	if err != nil {
		logger.Error("GetUserByEmail admin check failed", zap.Error(err))
		return nil, newServiceError(500, "权限校验失败")
	}
	if !isSysAdmin {
		isOrgAdmin, aerr := s.repo.IsAnyOrgAdmin(ctx, actorUserID)
		if aerr != nil {
			logger.Error("GetUserByEmail org admin check failed", zap.Error(aerr))
			return nil, newServiceError(500, "权限校验失败")
		}
		if !isOrgAdmin {
			return nil, newServiceError(403, "无权查询用户信息")
		}
	}

	user, uerr := s.repo.GetUserByEmail(ctx, email)
	if uerr != nil {
		logger.Error("GetUserByEmail lookup failed", zap.Error(uerr))
		return nil, newServiceError(500, "查询用户失败")
	}
	if user == nil {
		return nil, newServiceError(404, "该邮箱未注册，请先发送邀请")
	}

	memberships, merr := s.repo.GetUserActiveMembershipsWithOrgs(ctx, user.ID)
	if merr != nil {
		logger.Error("GetUserByEmail memberships failed", zap.Error(merr))
		return nil, newServiceError(500, "查询用户组织失败")
	}

	orgInfos := make([]UserOrgInfo, len(memberships))
	for i, m := range memberships {
		orgInfos[i] = UserOrgInfo{
			MembershipID:   m.MembershipID,
			OrganizationID: m.OrganizationID,
			OrgName:        m.OrgName,
			OrgType:        m.OrgType,
			JoinedAt:       m.JoinedAt,
		}
	}

	return &UserLookupResult{
		UserID:        user.ID,
		Email:         user.Email,
		Nickname:      user.Nickname,
		Phone:         user.Phone,
		IsSystemAdmin: user.IsSystemAdmin,
		Memberships:   orgInfos,
	}, nil
}

// ==================== Bulk Operations ====================

func (s *MemberLifecycleService) BulkAdd(ctx context.Context, actorUserID int64, tenantID int64, req BulkAddParams) (*BulkAddResult, error) {
	// Validate membership type
	validTypes := map[string]bool{"full": true, "read_only": true, "billing": true, "guest": true}
	if !validTypes[req.MembershipType] {
		req.MembershipType = "full"
	}

	// Validate target organization
	targetOrg, err := s.repo.GetOrgByID(ctx, req.OrganizationID)
	if err != nil || targetOrg == nil {
		return nil, newServiceError(404, "组织不存在")
	}

	// Tenant isolation & management permission（与 AddMember 一致：
	// 系统管理员可跨租户；其他用户须同租户且管理该组织）
	if targetOrg.RootTenantID != tenantID {
		isSysAdmin, aerr := s.repo.IsSystemAdmin(ctx, actorUserID)
		if aerr != nil || !isSysAdmin {
			return nil, newServiceError(403, "组织不属于当前租户范围")
		}
	} else {
		canManage, cerr := s.repo.CanManageOrg(ctx, actorUserID, req.OrganizationID)
		if cerr != nil || !canManage {
			return nil, newServiceError(403, "无权管理该组织，无法添加成员")
		}
	}

	// Check quota
	if _, err := s.repo.CheckQuota(ctx, targetOrg.RootTenantID); err != nil {
		logger.Error("BulkAdd quota check failed", zap.Error(err))
		return nil, newServiceError(500, "检查配额失败")
	}

	// For small batches (<10 items), process synchronously
	if len(req.UserIDs) < 10 {
		return s.processBulkAddSync(ctx, actorUserID, tenantID, req)
	}

	// For larger batches, create background job
	bulkJob := job.CreateBulkAddJob(actorUserID, req.OrganizationID, req.UserIDs, nil)
	bulkJob.TotalItems = len(req.UserIDs)

	if err := s.jobStore.CreateJob(ctx, bulkJob); err != nil {
		logger.Error("BulkAdd failed to create job", zap.Error(err))
		return nil, newServiceError(500, "创建批量任务失败")
	}

	// Enqueue job for processing
	go func() {
		if err := bulkJob.WithRetry(job.MaxRetries); err != nil {
			logger.Error("BulkAdd job failed", zap.String("job_id", bulkJob.JobID), zap.Error(err))
		}
		s.repo.InvalidateAuthCache(tenantID, req.OrganizationID)
		s.auditLog(actorUserID, "member.bulk_add", req.OrganizationID, map[string]interface{}{
			"user_ids":        req.UserIDs,
			"total_requested": len(req.UserIDs),
			"job_id":          bulkJob.JobID,
		})
	}()

	return &BulkAddResult{
		IsAsync:    true,
		JobID:      bulkJob.JobID,
		StatusURL:  fmt.Sprintf("/api/v1/jobs/%s/status", bulkJob.JobID),
		WSURL:      fmt.Sprintf("/ws/jobs/%s/progress?user_id=%d", bulkJob.JobID, actorUserID),
		TotalItems: len(req.UserIDs),
	}, nil
}

func (s *MemberLifecycleService) processBulkAddSync(ctx context.Context, actorUserID int64, tenantID int64, req BulkAddParams) (*BulkAddResult, error) {
	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	addedCount := 0
	for _, uid := range req.UserIDs {
		// Validate user exists
		_, err := s.repo.GetUserByID(ctx, uid)
		if err != nil {
			logger.Error("BulkAdd user not found", zap.Int64("uid", uid), zap.Error(err))
			continue
		}

		// Skip if already active member
		existing, _ := s.repo.GetExistingMembership(ctx, uid, req.OrganizationID)
		if existing != nil && existing.Status == "active" {
			continue
		}

		// 单一身份约束：跳过已属于其他组织的用户（需先移除或走转移审批）
		currentOrgs, _ := s.repo.GetUserActiveMembershipsWithOrgs(ctx, uid)
		belongsToOther := false
		for _, om := range currentOrgs {
			if om.OrganizationID != req.OrganizationID {
				belongsToOther = true
				break
			}
		}
		if belongsToOther {
			logger.Warn("BulkAdd skipped user already in another org", zap.Int64("uid", uid))
			continue
		}

		// Insert or reactivate
		if existing != nil && existing.Status != "active" {
			s.repo.ReactivateMembership(ctx, tx, existing.ID, req.ExpiresAt)
		} else {
			rowsAffected, err := s.repo.CreateMembershipInOrg(ctx, tx, tenantID, req.OrganizationID, uid, req.ExpiresAt)
			if err == nil && rowsAffected > 0 {
				addedCount++
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, newServiceError(500, "批量添加失败")
	}

	s.repo.InvalidateAuthCache(tenantID, req.OrganizationID)
	s.auditLog(actorUserID, "member.bulk_add", req.OrganizationID, map[string]interface{}{
		"user_ids":        req.UserIDs,
		"added_count":     addedCount,
		"total_requested": len(req.UserIDs),
	})

	return &BulkAddResult{
		OrganizationID: req.OrganizationID,
		AddedCount:     addedCount,
	}, nil
}

func (s *MemberLifecycleService) BulkTransfer(ctx context.Context, actorUserID int64, req BulkTransferParams) (*BulkTransferResult, error) {
	// 审批制：批量发起即批量创建 pending 转移申请（同步，无需后台任务），
	// 真实转移由目标组织管理员审批后执行。
	result, err := s.TransferInitiate(ctx, actorUserID, req.MembershipIDs, req.TargetOrgID, req.Reason)
	if err != nil {
		return nil, err
	}

	return &BulkTransferResult{
		OrganizationID:   result.OrganizationID,
		TransferredCount: result.PendingCount,
	}, nil
}

// ==================== Internal Helpers ====================

// auditLog emits async audit logging events
func (s *MemberLifecycleService) auditLog(userID int64, action string, orgID int64, details map[string]interface{}) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		detailJSON, err := json.Marshal(details)
		if err != nil {
			logger.Error("Audit failed to marshal details", zap.Error(err))
			return
		}

		s.repo.LogAudit(ctx, userID, "", action, "member_lifecycle", fmt.Sprintf("%d", orgID), string(detailJSON), "")
	}()
}

// membershipIDsToUserIDs extracts user IDs from memberships
func membershipIDsToUserIDs(memberships []*model.OrganizationMembership) []int64 {
	userIDs := make([]int64, len(memberships))
	for i, m := range memberships {
		userIDs[i] = m.UserID
	}
	return userIDs
}
