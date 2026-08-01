package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-api-server/internal/job"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

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
	OrganizationID   int64
	TransferredCount int
}

type PendingTransferInfo struct {
	ID           int64     `json:"id"`
	MembershipID int64     `json:"membership_id"`
	UserID       int64     `json:"user_id"`
	FromOrgID    int64     `json:"from_org_id"`
	ToOrgID      int64     `json:"to_org_id"`
	InitiatorID  int64     `json:"initiator_id"`
	Status       string    `json:"status"`
	Reason       string    `json:"reason"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type BulkAddParams struct {
	UserIDs        []int64
	OrganizationID int64
	MembershipType string
	ExpiresAt      *time.Time
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

	// Tenant isolation: org must belong to the same tenant as the caller
	if targetOrg.RootTenantID != tenantID {
		return nil, newServiceError(403, "无权操作此组织")
	}

	// Check quota before adding
	usage, err := s.repo.CheckQuota(ctx, tenantID)
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

func (s *MemberLifecycleService) TransferInitiate(ctx context.Context, actorUserID int64, membershipIDs []int64, targetOrgID int64, reason string) (*TransferResult, error) {
	if len(membershipIDs) == 0 {
		return nil, newServiceError(400, "请选择要转移的成员")
	}

	// Fetch all memberships
	memberships, err := s.repo.GetMembershipsByIDList(ctx, membershipIDs)
	if err != nil || len(memberships) == 0 {
		return nil, newServiceError(404, "未找到有效的成员关系")
	}

	// Validate all memberships belong to same root_tenant
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

	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	// Transfer each membership
	transferredCount := 0
	for _, membership := range memberships {
		if err := s.repo.DeleteMembership(ctx, tx, membership.ID); err != nil {
			return nil, newServiceError(500, "移除旧成员关系失败")
		}

		rowsAffected, err := s.repo.CreateMembershipInOrg(ctx, tx, targetOrg.RootTenantID, targetOrg.ID, membership.UserID, membership.ExpiresAt)
		if err != nil {
			return nil, newServiceError(500, "添加到目标组织失败")
		}
		if rowsAffected > 0 {
			transferredCount++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, newServiceError(500, "提交成员转移失败")
	}

	// Invalidate authorization caches for both orgs
	go func() {
		s.repo.InvalidateAuthCache(rootTenantID, sourceOrgID)
		s.repo.InvalidateAuthCache(rootTenantID, targetOrg.ID)
	}()

	s.auditLog(actorUserID, "member.transfer.initiate", targetOrg.ID, map[string]interface{}{
		"source_org_id":     sourceOrgID,
		"target_org_id":     targetOrg.ID,
		"transferred_users": membershipIDsToUserIDs(memberships),
		"count":             transferredCount,
		"reason":            reason,
	})

	return &TransferResult{
		OrganizationID:   targetOrg.ID,
		TransferredCount: transferredCount,
	}, nil
}

func (s *MemberLifecycleService) TransferAccept(ctx context.Context, actorUserID int64, transferID int64) error {
	transferStatus, err := s.repo.GetTransferRequestStatus(ctx, transferID)
	if err != nil {
		return newServiceError(404, "转移请求不存在")
	}
	if transferStatus != "initiated" {
		return newServiceError(400, "转移请求状态不允许接受")
	}

	if err := s.repo.AcceptTransferRequest(ctx, transferID); err != nil {
		return newServiceError(500, "更新转移请求失败")
	}

	return nil
}

func (s *MemberLifecycleService) TransferReject(ctx context.Context, actorUserID int64, transferID int64, reason string) error {
	if reason == "" {
		return newServiceError(400, "拒绝转移必须提供原因")
	}

	transferStatus, err := s.repo.GetTransferRequestStatus(ctx, transferID)
	if err != nil {
		return newServiceError(404, "转移请求不存在")
	}
	if transferStatus != "initiated" {
		return newServiceError(400, "转移请求状态不允许拒绝")
	}

	if err := s.repo.RejectTransferRequest(ctx, transferID, reason); err != nil {
		return newServiceError(500, "更新转移请求失败")
	}

	return nil
}

func (s *MemberLifecycleService) ListTransfers(ctx context.Context, userID int64) ([]PendingTransferInfo, error) {
	transfers, err := s.repo.ListPendingTransfers(ctx, userID)
	if err != nil {
		logger.Error("ListTransfers query failed", zap.Error(err))
		return []PendingTransferInfo{}, nil
	}

	result := make([]PendingTransferInfo, len(transfers))
	for i, t := range transfers {
		result[i] = PendingTransferInfo{
			ID:           t.ID,
			MembershipID: t.MembershipID,
			UserID:       t.UserID,
			FromOrgID:    t.FromOrgID,
			ToOrgID:      t.ToOrgID,
			InitiatorID:  t.InitiatorID,
			Status:       t.Status,
			Reason:       t.Reason,
			CreatedAt:    t.CreatedAt,
			UpdatedAt:    t.UpdatedAt,
		}
	}

	return result, nil
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

	if targetOrg.RootTenantID != tenantID {
		return nil, newServiceError(403, "组织不属于当前租户范围")
	}

	// Check quota
	if _, err := s.repo.CheckQuota(ctx, tenantID); err != nil {
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
	// Fetch memberships
	memberships, err := s.repo.GetMembershipsByIDList(ctx, req.MembershipIDs)
	if err != nil || len(memberships) == 0 {
		return nil, newServiceError(404, "未找到有效成员")
	}

	// Validate same tenant
	rootTenantID := memberships[0].RootTenantID
	for _, m := range memberships {
		if m.RootTenantID != rootTenantID {
			return nil, newServiceError(409, "跨租户批量转移不支持")
		}
	}

	// Validate target org
	targetOrg, err := s.repo.GetOrgByID(ctx, req.TargetOrgID)
	if err != nil || targetOrg.RootTenantID != rootTenantID {
		return nil, newServiceError(403, "目标组织不在同一租户下")
	}

	// For small batches (<10 items), process synchronously
	if len(req.MembershipIDs) < 10 {
		return s.processBulkTransferSync(ctx, actorUserID, rootTenantID, targetOrg, memberships, req.Reason)
	}

	// For larger batches, create background job
	bulkJob := job.CreateBulkTransferJob(actorUserID, req.MembershipIDs, req.TargetOrgID)
	bulkJob.TotalItems = len(req.MembershipIDs)

	if err := s.jobStore.CreateJob(ctx, bulkJob); err != nil {
		logger.Error("BulkTransfer failed to create job", zap.Error(err))
		return nil, newServiceError(500, "创建批量转移任务失败")
	}

	sourceOrgID := memberships[0].OrganizationID
	go func() {
		if err := bulkJob.WithRetry(job.MaxRetries); err != nil {
			logger.Error("BulkTransfer job failed", zap.String("job_id", bulkJob.JobID), zap.Error(err))
		}
		go func() {
			s.repo.InvalidateAuthCache(rootTenantID, sourceOrgID)
			s.repo.InvalidateAuthCache(rootTenantID, targetOrg.ID)
		}()
		s.auditLog(actorUserID, "member.bulk_transfer", targetOrg.ID, map[string]interface{}{
			"membership_ids":    req.MembershipIDs,
			"target_org_id":     req.TargetOrgID,
			"total_transferred": len(req.MembershipIDs),
			"job_id":            bulkJob.JobID,
			"reason":            req.Reason,
		})
	}()

	return &BulkTransferResult{
		IsAsync:    true,
		JobID:      bulkJob.JobID,
		StatusURL:  fmt.Sprintf("/api/v1/jobs/%s/status", bulkJob.JobID),
		WSURL:      fmt.Sprintf("/ws/jobs/%s/progress?user_id=%d", bulkJob.JobID, actorUserID),
		TotalItems: len(req.MembershipIDs),
	}, nil
}

func (s *MemberLifecycleService) processBulkTransferSync(ctx context.Context, actorUserID int64, rootTenantID int64, targetOrg *model.Organization, memberships []*model.OrganizationMembership, reason string) (*BulkTransferResult, error) {
	tx, err := s.repo.BeginTx(ctx)
	if err != nil {
		return nil, newServiceError(500, "数据库事务开始失败")
	}
	defer tx.Rollback(ctx)

	transferredCount := 0
	for _, membership := range memberships {
		if err := s.repo.DeleteMembership(ctx, tx, membership.ID); err != nil {
			continue
		}

		rowsAffected, err := s.repo.CreateMembershipInOrg(ctx, tx, targetOrg.RootTenantID, targetOrg.ID, membership.UserID, membership.ExpiresAt)
		if err == nil && rowsAffected > 0 {
			transferredCount++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, newServiceError(500, "批量转移失败")
	}

	go func() {
		s.repo.InvalidateAuthCache(rootTenantID, memberships[0].OrganizationID)
		s.repo.InvalidateAuthCache(rootTenantID, targetOrg.ID)
	}()

	s.auditLog(actorUserID, "member.bulk_transfer", targetOrg.ID, map[string]interface{}{
		"transferred_count": transferredCount,
		"source_orgs":       membershipIDsToUserIDs(memberships),
	})

	return &BulkTransferResult{
		OrganizationID:   targetOrg.ID,
		TransferredCount: transferredCount,
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
