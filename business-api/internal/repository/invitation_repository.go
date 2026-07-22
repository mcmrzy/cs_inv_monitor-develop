package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"inv-api-server/internal/model"
)

// InvitationRepository handles database operations for invitations
type InvitationRepository struct {
}

// NewInvitationRepository creates a new InvitationRepository instance.
func NewInvitationRepository() *InvitationRepository {
	return &InvitationRepository{}
}

// GetById retrieves an invitation by ID
func (r *InvitationRepository) GetById(ctx context.Context, db *pgxpool.Pool, id int64) (*model.Invitation, error) {
	query := `
		SELECT id, root_tenant_id, organization_id, inviter_user_id, email, role_id,
			   token_digest, expires_at, used_at, status, created_at, updated_at
		FROM invitations WHERE id = $1
	`

	var invitation model.Invitation
	var usedAt sql.NullTime

	err := db.QueryRow(ctx, query, id).Scan(
		&invitation.ID, &invitation.RootTenantID, &invitation.OrganizationID,
		&invitation.InviterUserID, &invitation.Email, &invitation.RoleID,
		&invitation.TokenDigest, &invitation.ExpiresAt, &usedAt, 
		&invitation.Status, &invitation.CreatedAt, &invitation.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if usedAt.Valid {
		invitation.UsedAt = &usedAt.Time
	}

	return &invitation, nil
}

// FindByTokenDigest finds an invitation by its SHA-256 token digest
func (r *InvitationRepository) FindByTokenDigest(ctx context.Context, db *pgxpool.Pool, digestHex string) (*model.Invitation, error) {
	query := `
		SELECT id, root_tenant_id, organization_id, inviter_user_id, email, role_id,
			   token_digest, expires_at, used_at, status, created_at, updated_at
		FROM invitations WHERE token_digest = $1 AND status = 'pending'
	`

	var invitation model.Invitation
	var usedAt sql.NullTime

	err := db.QueryRow(ctx, query, digestHex).Scan(
		&invitation.ID, &invitation.RootTenantID, &invitation.OrganizationID,
		&invitation.InviterUserID, &invitation.Email, &invitation.RoleID,
		&invitation.TokenDigest, &invitation.ExpiresAt, &usedAt,
		&invitation.Status, &invitation.CreatedAt, &invitation.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if usedAt.Valid {
		invitation.UsedAt = &usedAt.Time
	}

	return &invitation, nil
}

// UpdateStatus updates the status of an invitation
func (r *InvitationRepository) UpdateStatus(ctx context.Context, db *pgxpool.Pool, id int64, status string) error {
	query := `UPDATE invitations SET status = $1, updated_at = NOW() WHERE id = $2`
	_, err := db.Exec(ctx, query, status, id)
	return err
}

// Revoke marks an invitation as revoked
func (r *InvitationRepository) Revoke(ctx context.Context, db *pgxpool.Pool, id int64) error {
	query := `UPDATE invitations SET status = 'revoked', updated_at = NOW() WHERE id = $1 AND status = 'pending'`
	result, err := db.Exec(ctx, query, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("no pending invitation found with ID %d", id)
	}
	return nil
}

// MarkUsed marks an invitation as used and records the user ID
func (r *InvitationRepository) MarkUsed(ctx context.Context, tx any, id int64, userID int64) error {
	switch db := tx.(type) {
	case *pgxpool.Pool:
		return r.markUsedWithPool(ctx, db, id, userID)
	case pgx.Tx:
		return r.markUsedWithTx(ctx, db, id, userID)
	default:
		return fmt.Errorf("invalid transaction type")
	}
}

func (r *InvitationRepository) markUsedWithPool(ctx context.Context, pool *pgxpool.Pool, id int64, userID int64) error {
	query := `
		UPDATE invitations 
		SET status = 'used', used_at = NOW(), updated_at = NOW()
		WHERE id = $1 AND status = 'pending'
	`
	result, err := pool.Exec(ctx, query, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("invitation already used or not found")
	}
	return nil
}

func (r *InvitationRepository) markUsedWithTx(ctx context.Context, tx pgx.Tx, id int64, userID int64) error {
	query := `
		UPDATE invitations 
		SET status = 'used', used_at = NOW(), updated_at = NOW()
		WHERE id = $1 AND status = 'pending'
	`
	result, err := tx.Exec(ctx, query, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("invitation already used or not found")
	}
	return nil
}

// ListInvitationsFilter represents filter criteria for listing invitations
type ListInvitationsFilter struct {
	RootTenantID     int64
	OrganizationID   int64
	Email            string
	Status           string
}

// ListInvitationsResponseItem represents a list item with details
type ListInvitationsResponseItem struct {
	model.Invitation
	InviterName string
	OrgName     *string
}

// ListWithDetails lists invitations with pagination and joins
func (r *InvitationRepository) ListWithDetails(ctx context.Context, db *pgxpool.Pool, filter ListInvitationsFilter, page, pageSize int) (int64, []ListInvitationsResponseItem, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	// Count total
	countQuery := `SELECT COUNT(*) FROM invitations WHERE root_tenant_id = $1`
	args := []interface{}{filter.RootTenantID}

	if filter.OrganizationID > 0 {
		countQuery += " AND organization_id = $2"
		args = append(args, filter.OrganizationID)
	}
	if filter.Email != "" {
		countQuery += " AND LOWER(email) = LOWER($" + strconv.Itoa(len(args)+1) + ")"
		args = append(args, filter.Email)
	}
	if filter.Status != "" {
		countQuery += " AND status = $" + strconv.Itoa(len(args)+1)
		args = append(args, filter.Status)
	}

	var total int64
	if err := db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return 0, nil, err
	}

	// Fetch paginated results
	offset := (page - 1) * pageSize
	listQuery := `
		SELECT i.id, i.root_tenant_id, i.organization_id, i.inviter_user_id, i.email, i.role_id,
			   i.token_digest, i.expires_at, i.used_at, i.status, i.created_at, i.updated_at,
			   COALESCE(u.nickname, 'Unknown') as inviter_name,
			   COALESCE(o.name, NULL) as org_name
		FROM invitations i
		LEFT JOIN users u ON i.inviter_user_id = u.id
		LEFT JOIN organizations o ON i.organization_id = o.id AND o.root_tenant_id = i.root_tenant_id
		WHERE i.root_tenant_id = $1
	`
	listArgs := []interface{}{filter.RootTenantID}

	if filter.OrganizationID > 0 {
		listQuery += " AND i.organization_id = $2"
		listArgs = append(listArgs, filter.OrganizationID)
	}
	if filter.Email != "" {
		listQuery += " AND LOWER(i.email) = LOWER($" + strconv.Itoa(len(listArgs)+1) + ")"
		listArgs = append(listArgs, filter.Email)
	}
	if filter.Status != "" {
		listQuery += " AND i.status = $" + strconv.Itoa(len(listArgs)+1)
		listArgs = append(listArgs, filter.Status)
	}

	listQuery += " ORDER BY i.created_at DESC LIMIT $" + strconv.Itoa(len(listArgs)+1) + " OFFSET $" + strconv.Itoa(len(listArgs)+2)
	listArgs = append(listArgs, pageSize, offset)

	rows, err := db.Query(ctx, listQuery, listArgs...)
	if err != nil {
		return 0, nil, err
	}
	defer rows.Close()

	var items []ListInvitationsResponseItem
	for rows.Next() {
		var item ListInvitationsResponseItem
		var usedAt sql.NullTime
		var inviterName, orgName string
		var hasOrgName bool

		err := rows.Scan(
			&item.ID, &item.RootTenantID, &item.OrganizationID, &item.InviterUserID,
			&item.Email, &item.RoleID, &item.TokenDigest, &item.ExpiresAt, 
			&usedAt, &item.Status, &item.CreatedAt, &item.UpdatedAt,
			&inviterName, &orgName, &hasOrgName,
		)
		if err != nil {
			return 0, nil, err
		}

		if usedAt.Valid {
			item.UsedAt = &usedAt.Time
		}
		item.InviterName = inviterName
		if hasOrgName {
			item.OrgName = &orgName
		}

		items = append(items, item)
	}

	return total, items, nil
}

// CountByStatus counts invitations by status
func (r *InvitationRepository) CountByStatus(ctx context.Context, db *pgxpool.Pool, rootTenantID, organizationID int64, status string) (int64, error) {
	query := `
		SELECT COUNT(*) FROM invitations
		WHERE root_tenant_id = $1 AND organization_id = $2 AND status = $3
	`
	var count int64
	err := db.QueryRow(ctx, query, rootTenantID, organizationID, status).Scan(&count)
	return count, err
}

// Insert creates a new invitation record within a transaction
func (r *InvitationRepository) Insert(ctx context.Context, tx pgx.Tx, invitation *model.Invitation) error {
	query := `
		INSERT INTO invitations (root_tenant_id, organization_id, inviter_user_id, email, role_id,
								 token_digest, expires_at, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING id
	`
	return tx.QueryRow(ctx, query,
		invitation.RootTenantID, invitation.OrganizationID, invitation.InviterUserID,
		invitation.Email, invitation.RoleID, invitation.TokenDigest,
		invitation.ExpiresAt, invitation.Status, invitation.CreatedAt, invitation.UpdatedAt,
	).Scan(&invitation.ID)
}

// roleNames maps legacy role IDs to human-readable names
var roleNames = map[int]string{
	1: "org_admin",
	2: "channel_manager",
	3: "channel_manager",
	4: "operator",
	5: "viewer",
}

// roleCodes maps legacy role IDs to role code strings
var roleCodes = map[int]string{
	1: "org_admin",
	2: "channel_manager",
	3: "channel_manager",
	4: "operator",
	5: "viewer",
}

// GetRoleName returns the human-readable name for a legacy role ID
func GetRoleName(roleID int) string {
	if name, ok := roleNames[roleID]; ok {
		return name
	}
	return fmt.Sprintf("role_%d", roleID)
}

// GetRoleCode returns the role code string for a legacy role ID
func GetRoleCode(roleID int) string {
	if code, ok := roleCodes[roleID]; ok {
		return code
	}
	return fmt.Sprintf("role_%d", roleID)
}
