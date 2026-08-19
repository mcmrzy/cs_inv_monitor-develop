package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"

	"inv-api-server/internal/model"
	"inv-api-server/pkg/logger"
)

// QuotaUsage represents tenant capacity usage information
type QuotaUsage struct {
	UserCount int64
	UserLimit int64 // -1 means unlimited
}

// MemberTransferRequestRow 成员转移审批记录（含组织与用户展示信息，供审批工作台展示）
type MemberTransferRequestRow struct {
	ID             int64
	MembershipID   int64
	RootTenantID   int64
	UserID         int64
	UserEmail      string
	UserNickname   string
	FromOrgID      int64
	FromOrgName    string
	ToOrgID        int64
	ToOrgName      string
	InitiatorID    int64
	InitiatorEmail string
	Status         string
	Reason         string
	RejectReason   string
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

// UserMembershipOrg 用户所属组织信息（按邮箱查用户接口返回）
type UserMembershipOrg struct {
	MembershipID   int64     `json:"membership_id"`
	OrganizationID int64     `json:"organization_id"`
	OrgName        string    `json:"org_name"`
	OrgType        string    `json:"org_type"`
	JoinedAt       time.Time `json:"joined_at"`
}

// MemberLifecycleRepository encapsulates all data access for member lifecycle operations
type MemberLifecycleRepository struct {
	db       *pgxpool.Pool
	rdb      *redis.Client
	userRepo *UserRepository
}

// NewMemberLifecycleRepository creates a new member lifecycle repository
func NewMemberLifecycleRepository(db *pgxpool.Pool, rdb *redis.Client, userRepo *UserRepository) *MemberLifecycleRepository {
	return &MemberLifecycleRepository{
		db:       db,
		rdb:      rdb,
		userRepo: userRepo,
	}
}

// ==================== Read Queries ====================

// GetUserByID fetches user details by ID
func (r *MemberLifecycleRepository) GetUserByID(ctx context.Context, userID int64) (*model.User, error) {
	return r.userRepo.GetByID(ctx, userID)
}

// GetOrgByID fetches organization details by ID
func (r *MemberLifecycleRepository) GetOrgByID(ctx context.Context, orgID int64) (*model.Organization, error) {
	query := `
		SELECT id, root_tenant_id, parent_id, org_type, COALESCE(code, ''), name,
		       status, version, created_at, updated_at
		FROM organizations WHERE id = $1 AND deleted_at IS NULL
	`
	var org model.Organization
	var persistenceStatus string
	err := r.db.QueryRow(ctx, query, orgID).Scan(
		&org.ID, &org.RootTenantID, &org.ParentID, &org.Type,
		&org.Code, &org.Name, &persistenceStatus, &org.Version,
		&org.CreatedAt, &org.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	org.Status = model.ProjectOrganizationStatus(persistenceStatus)
	return &org, nil
}

// GetMembershipByID fetches membership details by ID
func (r *MemberLifecycleRepository) GetMembershipByID(ctx context.Context, membershipID int64) (*model.OrganizationMembership, error) {
	query := `
		SELECT id, root_tenant_id, organization_id, user_id,
		       status, expires_at, created_at, updated_at
		FROM organization_memberships WHERE id = $1
	`
	var m model.OrganizationMembership
	var persistenceStatus string
	err := r.db.QueryRow(ctx, query, membershipID).Scan(
		&m.ID, &m.RootTenantID, &m.OrganizationID,
		&m.UserID, &persistenceStatus, &m.ExpiresAt,
		&m.CreatedAt, &m.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	m.Status = model.ProjectMembershipStatus(persistenceStatus)
	return &m, nil
}

// GetMembershipsByIDList fetches multiple memberships by IDs
func (r *MemberLifecycleRepository) GetMembershipsByIDList(ctx context.Context, membershipIDs []int64) ([]*model.OrganizationMembership, error) {
	if len(membershipIDs) == 0 {
		return []*model.OrganizationMembership{}, nil
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, root_tenant_id, organization_id, user_id,
		       status, expires_at, created_at, updated_at
		FROM organization_memberships
		WHERE id = ANY($1)
	`, membershipIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var memberships []*model.OrganizationMembership
	for rows.Next() {
		var m model.OrganizationMembership
		var persistenceStatus string
		if err := rows.Scan(
			&m.ID, &m.RootTenantID, &m.OrganizationID, &m.UserID,
			&persistenceStatus, &m.ExpiresAt, &m.CreatedAt, &m.UpdatedAt,
		); err != nil {
			return nil, err
		}
		m.Status = model.ProjectMembershipStatus(persistenceStatus)
		memberships = append(memberships, &m)
	}

	return memberships, nil
}

// CheckQuota checks tenant capacity quota before adding members
func (r *MemberLifecycleRepository) CheckQuota(ctx context.Context, rootTenantID int64) (*QuotaUsage, error) {
	usage := &QuotaUsage{}

	// Get tenant quota limits from organization_quotas (root org, resource_type='members')
	var userLimit int64
	err := r.db.QueryRow(ctx, `
		SELECT quota_limit FROM organization_quotas
		WHERE root_tenant_id = $1 AND organization_id = $1 AND resource_type = 'members'
	`, rootTenantID).Scan(&userLimit)
	if err != nil {
		// No quota configured = unlimited
		usage.UserLimit = -1
	} else {
		usage.UserLimit = userLimit
	}

	// Count current members
	err = r.db.QueryRow(ctx, `
		SELECT COUNT(DISTINCT user_id) FROM organization_memberships
		WHERE root_tenant_id = $1 AND status = 'active'
	`, rootTenantID).Scan(&usage.UserCount)
	if err != nil {
		return nil, err
	}

	return usage, nil
}

// GetExistingMembership checks if a membership already exists
func (r *MemberLifecycleRepository) GetExistingMembership(ctx context.Context, userID int64, orgID int64) (*model.OrganizationMembership, error) {
	var m model.OrganizationMembership
	var persistenceStatus string
	err := r.db.QueryRow(ctx, `
		SELECT id, root_tenant_id, organization_id, user_id,
		       status, version, expires_at, joined_at, created_at, updated_at
		FROM organization_memberships
		WHERE user_id = $1 AND organization_id = $2 AND status = 'active'
	`, userID, orgID).Scan(
		&m.ID, &m.RootTenantID, &m.OrganizationID,
		&m.UserID, &persistenceStatus, &m.Version,
		&m.ExpiresAt, &m.JoinedAt, &m.CreatedAt,
		&m.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	m.Status = model.ProjectMembershipStatus(persistenceStatus)
	return &m, nil
}

// IsSystemAdmin checks if user is a system admin
func (r *MemberLifecycleRepository) IsSystemAdmin(ctx context.Context, userID int64) (bool, error) {
	var isSystemAdmin bool
	err := r.db.QueryRow(ctx, `SELECT is_system_admin FROM users WHERE id = $1 AND deleted_at IS NULL`, userID).Scan(&isSystemAdmin)
	if err != nil {
		return false, err
	}
	return isSystemAdmin, nil
}

// CanManageOrg 判断用户是否可管理目标组织：
// 系统管理员（users.is_system_admin）可管理全部组织；
// 其他用户须为目标组织自身或其祖先组织（organization_closure）的 active org_admin
// （与邀请流程 canCreateInvitationsFor 同款管理范围定义）。
func (r *MemberLifecycleRepository) CanManageOrg(ctx context.Context, userID, orgID int64) (bool, error) {
	var can bool
	err := r.db.QueryRow(ctx, `
		SELECT is_system_admin OR EXISTS(
			SELECT 1
			FROM organization_closure c
			JOIN organization_memberships m
			  ON m.organization_id = c.ancestor_id AND m.status = 'active'
			JOIN membership_role_assignments ra
			  ON ra.membership_id = m.id AND ra.organization_id = m.organization_id
			WHERE c.descendant_id = $2
			  AND m.user_id = $1
			  AND ra.role_code = 'org_admin' AND ra.status = 'active'
		)
		FROM users
		WHERE id = $1 AND deleted_at IS NULL
	`, userID, orgID).Scan(&can)
	if err != nil {
		if err == pgx.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return can, nil
}

// IsAnyOrgAdmin 判断用户是否担任任意组织的 active org_admin（按邮箱查用户接口的门禁）
func (r *MemberLifecycleRepository) IsAnyOrgAdmin(ctx context.Context, userID int64) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1
			FROM organization_memberships m
			JOIN membership_role_assignments ra
			  ON ra.membership_id = m.id AND ra.organization_id = m.organization_id
			WHERE m.user_id = $1 AND m.status = 'active'
			  AND ra.role_code = 'org_admin' AND ra.status = 'active'
		)
	`, userID).Scan(&exists)
	return exists, err
}

// GetUserByEmail 按邮箱查询用户（复用 UserRepository，未找到返回 nil, nil）
func (r *MemberLifecycleRepository) GetUserByEmail(ctx context.Context, email string) (*model.User, error) {
	return r.userRepo.GetByEmail(ctx, email)
}

// GetUserActiveMembershipsWithOrgs 查询用户全部活跃成员关系及所属组织信息
func (r *MemberLifecycleRepository) GetUserActiveMembershipsWithOrgs(ctx context.Context, userID int64) ([]UserMembershipOrg, error) {
	rows, err := r.db.Query(ctx, `
		SELECT m.id, m.organization_id, o.name, o.org_type, m.joined_at
		FROM organization_memberships m
		JOIN organizations o ON o.id = m.organization_id AND o.deleted_at IS NULL
		WHERE m.user_id = $1 AND m.status = 'active'
		ORDER BY m.joined_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []UserMembershipOrg
	for rows.Next() {
		var item UserMembershipOrg
		if err := rows.Scan(&item.MembershipID, &item.OrganizationID, &item.OrgName, &item.OrgType, &item.JoinedAt); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, nil
}

// ==================== Transaction Management ====================

// BeginTx starts a new transaction
func (r *MemberLifecycleRepository) BeginTx(ctx context.Context) (pgx.Tx, error) {
	return r.db.Begin(ctx)
}

// ==================== Write Operations (within transaction) ====================

// ReactivateMembership reactivates an existing membership within a transaction
func (r *MemberLifecycleRepository) ReactivateMembership(ctx context.Context, tx pgx.Tx, membershipID int64, expiresAt *time.Time) (int64, error) {
	result, err := tx.Exec(ctx, `
		UPDATE organization_memberships
		SET status = 'active',
		    expires_at = COALESCE($2, expires_at),
		    updated_at = NOW()
		WHERE id = $1
	`, membershipID, expiresAt)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// CreateMembership creates a new membership within a transaction
func (r *MemberLifecycleRepository) CreateMembership(ctx context.Context, tx pgx.Tx, tenantID, orgID, userID int64, expiresAt *time.Time) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO organization_memberships
			(root_tenant_id, organization_id, user_id, status, expires_at)
		VALUES ($1, $2, $3, 'active', $4)
	`, tenantID, orgID, userID, expiresAt)
	return err
}

// UpdateMembershipStatus updates membership status within a transaction
// onlyStatus is the required current status for the update to apply
func (r *MemberLifecycleRepository) UpdateMembershipStatus(ctx context.Context, tx pgx.Tx, membershipID int64, newStatus, onlyStatus string) (int64, error) {
	result, err := tx.Exec(ctx, `
		UPDATE organization_memberships
		SET status = $2, updated_at = NOW()
		WHERE id = $1 AND status = $3
	`, membershipID, newStatus, onlyStatus)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// UpdateMembershipStatusWithCondition updates membership status within a transaction
// onlyStatuses is the list of required current statuses for the update to apply
func (r *MemberLifecycleRepository) UpdateMembershipStatusWithCondition(ctx context.Context, tx pgx.Tx, membershipID int64, newStatus string, onlyStatuses []string) (int64, error) {
	result, err := tx.Exec(ctx, `
		UPDATE organization_memberships
		SET status = $2, updated_at = NOW()
		WHERE id = $1 AND status = ANY($3)
	`, membershipID, newStatus, onlyStatuses)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// UpdateMembershipFields updates membership fields dynamically within a transaction
func (r *MemberLifecycleRepository) UpdateMembershipFields(ctx context.Context, tx pgx.Tx, membershipID int64, status *string, expiresAt *time.Time) error {
	query := `UPDATE organization_memberships SET updated_at = NOW()`
	params := []interface{}{}

	if status != nil {
		query += `, status = $` + fmt.Sprintf("%d", len(params)+1)
		params = append(params, *status)
	}
	if expiresAt != nil {
		query += `, expires_at = $` + fmt.Sprintf("%d", len(params)+1)
		params = append(params, *expiresAt)
	}
	query += ` WHERE id = $` + fmt.Sprintf("%d", len(params)+1)
	params = append(params, membershipID)

	_, err := tx.Exec(ctx, query, params...)
	return err
}

// DeleteMembership deletes a membership within a transaction
func (r *MemberLifecycleRepository) DeleteMembership(ctx context.Context, tx pgx.Tx, membershipID int64) error {
	_, err := tx.Exec(ctx, `DELETE FROM organization_memberships WHERE id = $1`, membershipID)
	return err
}

// CreateMembershipInOrg creates a new membership in a target org within a transaction (for transfers)
func (r *MemberLifecycleRepository) CreateMembershipInOrg(ctx context.Context, tx pgx.Tx, rootTenantID, targetOrgID, userID int64, expiresAt *time.Time) (int64, error) {
	result, err := tx.Exec(ctx, `
		INSERT INTO organization_memberships
			(root_tenant_id, organization_id, user_id, status, expires_at, created_at, updated_at)
		VALUES ($1, $2, $3, 'active', $4, NOW(), NOW())
	`, rootTenantID, targetOrgID, userID, expiresAt)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// ==================== Transfer Request Operations ====================

// memberTransferRequestSelect 转移审批记录统一查询（含组织/用户展示信息）
const memberTransferRequestSelect = `
	SELECT t.id, t.membership_id, t.root_tenant_id, t.user_id,
	       COALESCE(tu.email, ''), COALESCE(tu.nickname, ''),
	       t.from_org_id, fo.name, t.to_org_id, to2.name,
	       t.initiator_id, COALESCE(iu.email, ''),
	       t.status, COALESCE(t.reason, ''), COALESCE(t.reject_reason, ''),
	       t.created_at, t.updated_at
	FROM member_transfer_requests t
	JOIN organizations fo ON fo.id = t.from_org_id
	JOIN organizations to2 ON to2.id = t.to_org_id
	JOIN users tu ON tu.id = t.user_id
	JOIN users iu ON iu.id = t.initiator_id
`

// CreateTransferRequest 在事务内创建一条 pending 转移审批申请（不动 membership）
func (r *MemberLifecycleRepository) CreateTransferRequest(ctx context.Context, tx pgx.Tx, rootTenantID, membershipID, userID, fromOrgID, toOrgID, initiatorID int64, reason string) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO member_transfer_requests
			(root_tenant_id, membership_id, user_id, from_org_id, to_org_id, initiator_id, status, reason)
		VALUES ($1, $2, $3, $4, $5, $6, 'pending', $7)
	`, rootTenantID, membershipID, userID, fromOrgID, toOrgID, initiatorID, reason)
	return err
}

// HasPendingTransferRequest 判断指定成员关系是否已有待审批的转移申请
func (r *MemberLifecycleRepository) HasPendingTransferRequest(ctx context.Context, membershipID int64) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM member_transfer_requests
			WHERE membership_id = $1 AND status = 'pending'
		)
	`, membershipID).Scan(&exists)
	return exists, err
}

// GetTransferRequestByID 按 ID 查询转移审批记录（未找到返回 nil, nil）
func (r *MemberLifecycleRepository) GetTransferRequestByID(ctx context.Context, id int64) (*MemberTransferRequestRow, error) {
	var row MemberTransferRequestRow
	err := r.db.QueryRow(ctx, memberTransferRequestSelect+` WHERE t.id = $1`, id).Scan(
		&row.ID, &row.MembershipID, &row.RootTenantID, &row.UserID,
		&row.UserEmail, &row.UserNickname,
		&row.FromOrgID, &row.FromOrgName, &row.ToOrgID, &row.ToOrgName,
		&row.InitiatorID, &row.InitiatorEmail,
		&row.Status, &row.Reason, &row.RejectReason,
		&row.CreatedAt, &row.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &row, nil
}

// UpdateTransferRequestStatus 在事务内流转申请状态（带当前状态条件，乐观并发控制）；
// rejectReason 非空时写入拒绝原因
func (r *MemberLifecycleRepository) UpdateTransferRequestStatus(ctx context.Context, tx pgx.Tx, id int64, fromStatus, toStatus, rejectReason string) (int64, error) {
	result, err := tx.Exec(ctx, `
		UPDATE member_transfer_requests
		SET status = $3,
		    reject_reason = COALESCE(NULLIF($4, ''), reject_reason),
		    updated_at = NOW()
		WHERE id = $1 AND status = $2
	`, id, fromStatus, toStatus, rejectReason)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// ListTransferRequests 分页查询当前用户可审批的转移申请：
// 系统管理员可见全部；组织管理员仅可见 to_org 位于其管理范围（祖先链）内的申请。
func (r *MemberLifecycleRepository) ListTransferRequests(ctx context.Context, viewerUserID int64, isSystemAdmin bool, page, pageSize int, status string) ([]MemberTransferRequestRow, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	offset := (page - 1) * pageSize

	where := "WHERE ($1 = '' OR t.status = $1)"
	args := []interface{}{status}
	if !isSystemAdmin {
		where += ` AND EXISTS(
			SELECT 1
			FROM organization_closure c
			JOIN organization_memberships m
			  ON m.organization_id = c.ancestor_id AND m.status = 'active' AND m.user_id = $2
			JOIN membership_role_assignments ra
			  ON ra.membership_id = m.id AND ra.organization_id = m.organization_id
			WHERE c.descendant_id = t.to_org_id
			  AND ra.role_code = 'org_admin' AND ra.status = 'active'
		)`
		args = append(args, viewerUserID)
	}

	var total int64
	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM member_transfer_requests t %s`, where)
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := fmt.Sprintf(`%s %s ORDER BY t.created_at DESC LIMIT $%d OFFSET $%d`,
		memberTransferRequestSelect, where, len(args)+1, len(args)+2)
	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var result []MemberTransferRequestRow
	for rows.Next() {
		var row MemberTransferRequestRow
		if err := rows.Scan(
			&row.ID, &row.MembershipID, &row.RootTenantID, &row.UserID,
			&row.UserEmail, &row.UserNickname,
			&row.FromOrgID, &row.FromOrgName, &row.ToOrgID, &row.ToOrgName,
			&row.InitiatorID, &row.InitiatorEmail,
			&row.Status, &row.Reason, &row.RejectReason,
			&row.CreatedAt, &row.UpdatedAt,
		); err != nil {
			logger.Error("ListTransferRequests scan error", zap.Error(err))
			continue
		}
		result = append(result, row)
	}
	return result, total, nil
}

// ==================== Redis Cache Operations ====================

// InvalidateAuthCache invalidates Redis authorization cache for a membership change
func (r *MemberLifecycleRepository) InvalidateAuthCache(rootTenantID int64, orgID int64) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	patterns := []string{
		fmt.Sprintf("auth_perms:%d:*", rootTenantID),
		fmt.Sprintf("membership:*:%d", orgID),
		fmt.Sprintf("tenant:%d:auth_version", rootTenantID),
	}

	for _, pattern := range patterns {
		keys, err := r.rdb.Keys(ctx, pattern).Result()
		if err != nil {
			logger.Error("invalidateAuthCache keys lookup failed", zap.Error(err))
			continue
		}
		if len(keys) > 0 {
			if err := r.rdb.Del(ctx, keys...).Err(); err != nil {
				logger.Error("invalidateAuthCache del keys failed", zap.Error(err))
			}
		}
	}
}

// ==================== List Members ====================

// OrgMemberWithUser represents a member with user details
// This is used for the frontend member list display
// Since we don't have email/phone in organization_memberships,
// we join with the users table to get those details
// In the new org system, the "email" is actually the user's identifier
// and "phone" is the user's phone number from the users table
// The frontend expects these fields in the response
// Note: In the new org system, users are added by user_id, not by email
// So we need to join with the users table to get the email/phone
// The frontend OrgMember type expects: id, user_id, organization_id, role, status, email, phone, nickname, joined_at
// But in our system, role is stored as role_code in membership_role_assignments
// and status is stored in organization_memberships
// We'll need to handle this mapping carefully

type OrgMemberWithUser struct {
	ID             int64      `json:"id"`
	UserID         int64      `json:"user_id"`
	OrganizationID int64      `json:"organization_id"`
	Role           string     `json:"role"`
	Status         string     `json:"status"`
	Email          string     `json:"email"`
	Phone          *string    `json:"phone,omitempty"`
	Nickname       *string    `json:"nickname,omitempty"`
	JoinedAt       time.Time  `json:"joined_at"`
}

// ListMembersByOrgID lists all members of an organization with user details, optionally filtered by role
func (r *MemberLifecycleRepository) ListMembersByOrgID(ctx context.Context, orgID int64, page, pageSize int, roleFilter string) ([]OrgMemberWithUser, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	offset := (page - 1) * pageSize

	// Build WHERE clause with optional role filter (role = org type now)
	whereClause := "WHERE m.organization_id = $1"
	args := []interface{}{orgID}
	argIdx := 2
	if roleFilter != "" {
		if roleFilter == "org_admin" {
			whereClause += fmt.Sprintf(" AND o.org_type = $%d", argIdx)
			args = append(args, "manufacturer")
		} else {
			whereClause += fmt.Sprintf(" AND o.org_type = $%d", argIdx)
			args = append(args, roleFilter)
		}
		argIdx++
	}

	// Get total count
	var total int64
	countQuery := fmt.Sprintf(`
		SELECT COUNT(*) FROM organization_memberships m
		JOIN organizations o ON o.id = m.organization_id AND o.deleted_at IS NULL
		%s
	`, whereClause)
	err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// Get members with user details and roles (role derived from org type)
	query := fmt.Sprintf(`
		SELECT 
			m.id, m.user_id, m.organization_id,
			CASE WHEN o.org_type = 'manufacturer' THEN 'org_admin' ELSE o.org_type END as role,
			m.status,
			COALESCE(u.email, '') as email,
			u.phone,
			u.nickname,
			m.joined_at
		FROM organization_memberships m
		JOIN organizations o ON o.id = m.organization_id AND o.deleted_at IS NULL
		LEFT JOIN users u ON u.id = m.user_id
		%s
		ORDER BY m.joined_at DESC
		LIMIT $%d OFFSET $%d
	`, whereClause, argIdx, argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var members []OrgMemberWithUser
	for rows.Next() {
		var m OrgMemberWithUser
		var persistenceStatus string
		if err := rows.Scan(
			&m.ID, &m.UserID, &m.OrganizationID,
			&m.Role, &persistenceStatus,
			&m.Email, &m.Phone, &m.Nickname, &m.JoinedAt,
		); err != nil {
			logger.Error("ListMembersByOrgID scan error", zap.Error(err))
			continue
		}
		m.Status = model.ProjectMembershipStatus(persistenceStatus)
		members = append(members, m)
	}

	if members == nil {
		members = []OrgMemberWithUser{}
	}

	return members, total, nil
}

// ==================== Audit Logging ====================

// LogAudit writes an audit log entry asynchronously
func (r *MemberLifecycleRepository) LogAudit(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string) {
	r.userRepo.LogAudit(ctx, operatorID, operatorName, action, resourceType, resourceID, detail, ip)
}

// ==================== Member Role Update ====================

// FindOrgByType 在同租户下查找指定类型的活跃组织（用于角色切换）
func (r *MemberLifecycleRepository) FindOrgByType(ctx context.Context, tx pgx.Tx, tenantID int64, orgType string) (int64, error) {
	var orgID int64
	err := tx.QueryRow(ctx, `
		SELECT id FROM organizations
		WHERE root_tenant_id = $1 AND org_type = $2 AND status = 'active' AND deleted_at IS NULL
		ORDER BY id LIMIT 1
	`, tenantID, orgType).Scan(&orgID)
	if err == pgx.ErrNoRows {
		return 0, nil
	}
	return orgID, err
}

// CreateOrgForRole 创建指定类型的组织（角色切换时自动补齐缺失的组织层级）
func (r *MemberLifecycleRepository) CreateOrgForRole(ctx context.Context, tx pgx.Tx, tenantID, parentID int64, orgType, name string) (int64, error) {
	var orgID int64
	err := tx.QueryRow(ctx, `
		INSERT INTO organizations (root_tenant_id, parent_id, org_type, name, status, version)
		VALUES ($1, $2, $3, $4, 'active', 1)
		RETURNING id
	`, tenantID, parentID, orgType, name).Scan(&orgID)
	return orgID, err
}

// UpdateMembershipOrg 更新成员关系所属组织并切换角色（单一身份）：
// organization_memberships 被 membership_role_assignments / role_permission_grants /
// resource_grants 以复合键（root_tenant_id, organization_id, id）外键引用，直接 UPDATE
// organization_id 会因引用旧三元组而违反外键（且双向同步必然存在中间态）。
// 因此按“先删旧引用 → 切换组织 → 重建新引用”的顺序在同一事务内完成：
// 删除旧角色分配及其授权、切换 membership 组织、创建目标角色分配并写入默认授权。
func (r *MemberLifecycleRepository) UpdateMembershipOrg(ctx context.Context, tx pgx.Tx, membershipID, orgID int64, role string) error {
	// 1. 删除该成员关系的显式资源授权（切换组织后旧组织授权作废）
	if _, err := tx.Exec(ctx, `
		DELETE FROM resource_grants WHERE subject_membership_id = $1
	`, membershipID); err != nil {
		return fmt.Errorf("drop resource grants: %w", err)
	}

	// 2. 删除旧活跃角色分配的授权（role_permission_grants 引用 role_assignment）
	if _, err := tx.Exec(ctx, `
		DELETE FROM role_permission_grants g
		USING membership_role_assignments ra
		WHERE g.role_assignment_id = ra.id AND ra.membership_id = $1 AND ra.status = 'active'
	`, membershipID); err != nil {
		return fmt.Errorf("drop old role grants: %w", err)
	}

	// 3. 删除旧活跃角色分配（释放对 membership 旧组织三元组的引用）
	if _, err := tx.Exec(ctx, `
		DELETE FROM membership_role_assignments
		WHERE membership_id = $1 AND status = 'active'
	`, membershipID); err != nil {
		return fmt.Errorf("drop old role assignments: %w", err)
	}

	// 4. membership 组织切换 + 授权版本提升（使已签发 JWT 的授权上下文失效）
	if _, err := tx.Exec(ctx, `
		UPDATE organization_memberships
		SET organization_id = $1, updated_at = NOW(), version = version + 1,
		    authorization_version = authorization_version + 1
		WHERE id = $2
	`, orgID, membershipID); err != nil {
		return fmt.Errorf("switch membership org: %w", err)
	}

	// 5. 创建目标角色分配（role_code 对应目标组织类型）
	var rootTenantID, assignmentID int64
	if err := tx.QueryRow(ctx, `
		INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status, version)
		SELECT m.root_tenant_id, $1, m.id, $2, 'active', 1
		FROM organization_memberships m WHERE m.id = $3
		RETURNING id, root_tenant_id
	`, orgID, role, membershipID).Scan(&assignmentID, &rootTenantID); err != nil {
		return fmt.Errorf("create role assignment: %w", err)
	}

	// 6. 写入目标角色默认授权（幂等：已存在的授权保持不变）
	return EnsureRoleDefaultGrants(ctx, tx, rootTenantID, orgID, assignmentID, role)
}

// RevokeOtherMemberships 撤销同一用户的其他活跃成员关系（保证单一身份），返回撤销数量
func (r *MemberLifecycleRepository) RevokeOtherMemberships(ctx context.Context, tx pgx.Tx, userID, keepMembershipID int64) (int64, error) {
	tag, err := tx.Exec(ctx, `
		UPDATE organization_memberships
		SET status = 'revoked', updated_at = NOW(), version = version + 1
		WHERE user_id = $1 AND id != $2 AND status = 'active'
	`, userID, keepMembershipID)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
