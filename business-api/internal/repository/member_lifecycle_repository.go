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

// PendingTransfer represents a pending transfer record
type PendingTransfer struct {
	ID           int64
	MembershipID int64
	UserID       int64
	FromOrgID    int64
	ToOrgID      int64
	InitiatorID  int64
	Status       string
	Reason       string
	CreatedAt    time.Time
	UpdatedAt    time.Time
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

// GetTransferRequestStatus retrieves the status of a transfer request
func (r *MemberLifecycleRepository) GetTransferRequestStatus(ctx context.Context, transferID int64) (string, error) {
	var status string
	err := r.db.QueryRow(ctx, `
		SELECT status FROM member_transfer_requests
		WHERE id = $1
	`, transferID).Scan(&status)
	if err != nil {
		return "", err
	}
	return status, nil
}

// AcceptTransferRequest marks a transfer request as accepted
func (r *MemberLifecycleRepository) AcceptTransferRequest(ctx context.Context, transferID int64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE member_transfer_requests
		SET status = 'accepted', updated_at = NOW()
		WHERE id = $1
	`, transferID)
	return err
}

// RejectTransferRequest marks a transfer request as rejected
func (r *MemberLifecycleRepository) RejectTransferRequest(ctx context.Context, transferID int64, reason string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE member_transfer_requests
		SET status = 'rejected', reason = $2, updated_at = NOW()
		WHERE id = $1
	`, transferID, reason)
	return err
}

// ListPendingTransfers lists pending transfers for a user
func (r *MemberLifecycleRepository) ListPendingTransfers(ctx context.Context, userID int64) ([]PendingTransfer, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, membership_id, from_org_id, to_org_id, initiator_id,
		       status, reason, created_at, updated_at
		FROM pending_transfers
		WHERE user_id = $1 AND status = 'initiated'
		ORDER BY created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var transfers []PendingTransfer
	for rows.Next() {
		var t PendingTransfer
		if err := rows.Scan(
			&t.ID, &t.MembershipID, &t.FromOrgID, &t.ToOrgID,
			&t.InitiatorID, &t.Status, &t.Reason, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			logger.Error("ListPendingTransfers scan error", zap.Error(err))
			continue
		}
		transfers = append(transfers, t)
	}

	return transfers, nil
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

// ==================== Audit Logging ====================

// LogAudit writes an audit log entry asynchronously
func (r *MemberLifecycleRepository) LogAudit(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string) {
	r.userRepo.LogAudit(ctx, operatorID, operatorName, action, resourceType, resourceID, detail, ip)
}
