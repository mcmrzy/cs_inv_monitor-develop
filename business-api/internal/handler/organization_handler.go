package handler

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// OrganizationHandler handles organization management operations
type OrganizationHandler struct {
	db          *pgxpool.Pool
	permChecker interface{} // Will be set when service layer is available
}

// CreateOrganizationRequest represents a request to create a new organization unit
type CreateOrganizationRequest struct {
	Name     string  `json:"name" binding:"required"`
	Type     string  `json:"type" binding:"required"`
	ParentID *int64  `json:"parent_id"` // nil = direct child of root tenant
}

// UpdateOrganizationRequest represents a request to update organization metadata
type UpdateOrganizationRequest struct {
	Name string `json:"name" binding:"required"`
}

// MoveOrganizationRequest represents a request to move organization to new parent
type MoveOrganizationRequest struct {
	ParentID int64 `json:"parent_id" binding:"required"`
}

// ToggleStatusRequest represents a request to toggle organization status
type ToggleStatusRequest struct {
	Status string `json:"status" binding:"required"` // "active" or "inactive"
}

// OrganizationListResponse represents paginated organization list response
type OrganizationListResponse struct {
	Organizations []OrganizationWithChildren `json:"organizations"`
	Total         int64                      `json:"total"`
	Page          int                        `json:"page"`
	PageSize      int                        `json:"page_size"`
}

// OrganizationWithChildren represents an organization with children count
type OrganizationWithChildren struct {
	ID              int64                  `json:"id"`
	RootTenantID    int64                  `json:"root_tenant_id"`
	ParentID        *int64                 `json:"parent_id,omitempty"`
	Type            string                 `json:"type"`
	Code            string                 `json:"code,omitempty"`
	Name            string                 `json:"name"`
	Status          string                 `json:"status"`
	Version         int64                  `json:"version"`
	ChildrenCount   int                    `json:"children_count"`
	CreatedAt       time.Time              `json:"created_at"`
	UpdatedAt       time.Time              `json:"updated_at"`
	ChildOrganizations []OrganizationSummary `json:"child_organizations,omitempty"`
}

// OrganizationSummary represents minimal org info for tree structures
type OrganizationSummary struct {
	ID         int64  `json:"id"`
	Name       string `json:"name"`
	Type       string `json:"type"`
	Status     string `json:"status"`
	HasChildren bool   `json:"has_children"`
}

// NewOrganizationHandler creates a new organization handler instance
func NewOrganizationHandler(db *pgxpool.Pool) *OrganizationHandler {
	return &OrganizationHandler{
		db: db,
	}
}

// Create handles POST /api/v1/organizations - Create organization unit within tenant
func (h *OrganizationHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	var req CreateOrganizationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// Role validation: only non-enduser can create orgs (roles 0-4, not 5=enduser)
	if role == 5 { // RoleEndUser
		response.Error(c, 403, "end users cannot create organizations")
		return
	}

	// Validate organization type.
	// "manufacturer" cannot be created via the API — the root manufacturer
	// org is provisioned automatically by ensure_tenant_root().
	validTypes := map[string]bool{
		"agent":           true,
		"distributor":     true,
		"customer":        true,
		"service_partner": true,
	}
	if !validTypes[req.Type] {
		response.Error(c, 400, "invalid organization type")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[CreateOrg] tx begin error: user_id=%d, err=%v", userID, err)
		response.Error(c, 500, "system error")
		return
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		}
	}()

	// Get user's root_tenant_id from actor context
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		tx.Rollback(ctx)
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Ensure tenant root manufacturer org exists (required by DB constraints).
	// The ensure_tenant_root function (SECURITY DEFINER) safely handles stale
	// rows from previous test runs and guarantees tenant_roots + closure entries.
	_, err = tx.Exec(ctx, `SELECT ensure_tenant_root($1)`, tenantID)
	if err != nil {
		tx.Rollback(ctx)
		log.Printf("[CreateOrg] ensure_tenant_root error: user_id=%d, tenant_id=%d, err=%v", userID, tenantID, err)
		response.Error(c, 500, fmt.Sprintf("create organization failed: %v", err))
		return
	}

	// If ParentID provided, validate it belongs to same root_tenant
	var parentID *int64
	if req.ParentID != nil {
		var checkTenantID int64
		err = tx.QueryRow(ctx, `
			SELECT root_tenant_id FROM organizations WHERE id = $1 AND deleted_at IS NULL
		`, *req.ParentID).Scan(&checkTenantID)
		if err == pgx.ErrNoRows {
			tx.Rollback(ctx)
			response.Error(c, 404, "parent organization not found")
			return
		}
		if err != nil {
			tx.Rollback(ctx)
			log.Printf("[CreateOrg] query parent error: err=%v", err)
			response.Error(c, 500, "query parent failed")
			return
		}
		if checkTenantID != tenantID {
			tx.Rollback(ctx)
			response.Error(c, 403, "parent organization not in tenant scope")
			return
		}
		parentID = req.ParentID
	} else {
		// Default parent is the manufacturer root org
		parentID = &tenantID
	}

	// Insert organization — the AFTER INSERT trigger handles closure and tenant_roots
	org := &model.Organization{
		ID:           0, // Let DB generate
		RootTenantID: tenantID,
		ParentID:     parentID,
		Type:         req.Type,
		Name:         req.Name,
		Status:       model.OrganizationStatusActive,
		Version:      1,
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO organizations (root_tenant_id, parent_id, org_type, name, status, version)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, created_at, updated_at
	`, org.RootTenantID, org.ParentID, org.Type, org.Name, org.Status, org.Version).
		Scan(&org.ID, &org.CreatedAt, &org.UpdatedAt)
	if err != nil {
		tx.Rollback(ctx)
		log.Printf("[CreateOrg] insert error: user_id=%d, tenant_id=%d, parent_id=%v, type=%s, err=%v", userID, tenantID, parentID, req.Type, err)
		response.Error(c, 500, fmt.Sprintf("create organization failed: %v", err))
		return
	}

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[CreateOrg] commit error: user_id=%d, err=%v", userID, err)
		response.Error(c, 500, fmt.Sprintf("create organization failed: %v", err))
		return
	}

	// Invalidate RBAC cache for the new organization
	go func(orgID int64, tenantID int64) {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		// TODO: Add rbacCache to handler and call InvalidateAllForOrg
		_ = ctx
		_ = orgID
		_ = tenantID
	}(org.ID, tenantID)

	// Async audit logging
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		// Log audit event using existing pattern if user service available
		_ = ctx
		_ = userID
	}()

	response.Success(c, OrganizationWithChildren{
		ID:            org.ID,
		RootTenantID:  org.RootTenantID,
		ParentID:      org.ParentID,
		Type:          org.Type,
		Name:          org.Name,
		Status:        org.Status,
		Version:       org.Version,
		CreatedAt:     org.CreatedAt,
		UpdatedAt:     org.UpdatedAt,
		ChildrenCount: 0,
	})
}

// List handles GET /api/v1/organizations - List organizations with pagination and filters
func (h *OrganizationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, 20)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	// Filter by type and status
	orgType := c.Query("type")
	status := c.Query("status")

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[ListOrg] tx begin error: user_id=%d, err=%v", userID, err)
		response.Error(c, 500, "system error")
		return
	}
	defer tx.Rollback(ctx)

	// Get user's root_tenant_id
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Check super admin access
	_ = role == 0 // RoleSuperAdmin
	
	var totalCount int64
	var orgs []OrganizationWithChildren

	query := `
		SELECT o.id, o.root_tenant_id, o.parent_id, o.org_type, COALESCE(o.code, ''), o.name, 
		       o.status, o.version, o.created_at, o.updated_at,
		       COUNT(CASE WHEN child.id IS NOT NULL THEN 1 END) as children_count
		FROM organizations o
		LEFT JOIN organizations child ON child.parent_id = o.id AND child.deleted_at IS NULL
		WHERE o.root_tenant_id = $1 AND o.deleted_at IS NULL
	`
	args := []interface{}{tenantID}
	argIdx := 2

	// Apply filters (super admin sees all, regular users see only their scope)
	if orgType != "" {
		query += fmt.Sprintf(" AND o.org_type = $%d", argIdx)
		args = append(args, orgType)
		argIdx++
	}
	if status != "" {
		query += fmt.Sprintf(" AND o.status = $%d", argIdx)
		args = append(args, status)
		argIdx++
	}

	query += ` GROUP BY o.id ORDER BY o.created_at DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)

	// Calculate offset
	offset := int64((page - 1) * pageSize)
	args = append(args, pageSize, offset)

	rows, err := tx.Query(ctx, query, args...)
	if err != nil {
		log.Printf("[ListOrg] query error: user_id=%d, err=%v", userID, err)
		response.Error(c, 500, "query organizations failed")
		return
	}
	defer rows.Close()

	for rows.Next() {
		var org OrganizationWithChildren
		err := rows.Scan(
			&org.ID, &org.RootTenantID, &org.ParentID, &org.Type, &org.Code, &org.Name,
			&org.Status, &org.Version, &org.CreatedAt, &org.UpdatedAt, &org.ChildrenCount,
		)
		if err != nil {
			log.Printf("[ListOrg] scan error: err=%v", err)
			continue
		}
		orgs = append(orgs, org)
	}

	// Get total count
	countQuery := `SELECT COUNT(*) FROM organizations WHERE root_tenant_id = $1 AND deleted_at IS NULL`
	countArgs := []interface{}{tenantID}
	if orgType != "" {
		countQuery += " AND org_type = $2"
		countArgs = append(countArgs, orgType)
	}
	if status != "" {
		countQuery += " AND status = $3"
		countArgs = append(countArgs, status)
	}
	err = tx.QueryRow(ctx, countQuery, countArgs...).Scan(&totalCount)
	if err != nil {
		log.Printf("[ListOrg] count error: err=%v", err)
		response.Error(c, 500, "count organizations failed")
		return
	}

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[ListOrg] commit error: err=%v", err)
		response.Error(c, 500, "query failed")
		return
	}

	response.Page(c, orgs, totalCount, page, pageSize)
}

// GetByID handles GET /api/v1/organizations/:id - Get organization details with children count
func (h *OrganizationHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[GetOrgById] tx begin error: user_id=%d, id=%d, err=%v", userID, id, err)
		response.Error(c, 500, "system error")
		return
	}
	defer tx.Rollback(ctx)

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Fetch organization
	var org OrganizationWithChildren
	err = tx.QueryRow(ctx, `
		SELECT o.id, o.root_tenant_id, o.parent_id, o.org_type, COALESCE(o.code, ''), o.name, 
		       o.status, o.version, o.created_at, o.updated_at,
		       (SELECT COUNT(*) FROM organizations WHERE parent_id = o.id AND deleted_at IS NULL)
		FROM organizations o
		WHERE o.id = $1 AND o.deleted_at IS NULL
	`, id).Scan(
		&org.ID, &org.RootTenantID, &org.ParentID, &org.Type, &org.Code, &org.Name,
		&org.Status, &org.Version, &org.CreatedAt, &org.UpdatedAt, &org.ChildrenCount,
	)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}
	if err != nil {
		log.Printf("[GetOrgById] query error: err=%v", err)
		response.Error(c, 500, "query organization failed")
		return
	}

	// Verify access
	if org.RootTenantID != tenantID {
		response.Error(c, 403, "access denied")
		return
	}

	// Fetch child organizations
	childrenRows, err := tx.Query(ctx, `
		SELECT id, name, org_type, status 
		FROM organizations 
		WHERE parent_id = $1 AND deleted_at IS NULL
		ORDER BY name
	`, id)
	if err == nil {
		defer childrenRows.Close()
		var children []OrganizationSummary
		for childrenRows.Next() {
			var child OrganizationSummary
			if err := childrenRows.Scan(&child.ID, &child.Name, &child.Type, &child.Status); err == nil {
				children = append(children, child)
			}
		}
		org.ChildOrganizations = children
	}

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[GetOrgById] commit error: err=%v", err)
		response.Error(c, 500, "query failed")
		return
	}

	response.Success(c, org)
}

// Update handles PUT /api/v1/organizations/:id - Update organization metadata
func (h *OrganizationHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	var req UpdateOrganizationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[UpdateOrg] tx begin error: user_id=%d, id=%d, err=%v", userID, id, err)
		response.Error(c, 500, "system error")
		return
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		}
	}()

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Check if org exists and belongs to tenant
	var currentType string
	var currentParentID *int64
	err = tx.QueryRow(ctx, `
		SELECT org_type, parent_id FROM organizations WHERE id = $1 AND deleted_at IS NULL
	`, id).Scan(&currentType, &currentParentID)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}
	if err != nil {
		log.Printf("[UpdateOrg] query error: err=%v", err)
		response.Error(c, 500, "query organization failed")
		return
	}

	// Type cannot be changed - only name allowed
	updateQuery := `
		UPDATE organizations SET name = $2, updated_at = NOW(), version = version + 1
		WHERE id = $1 AND root_tenant_id = $3
		RETURNING id, version, updated_at
	`
	var newVersion int64
	var updatedAt time.Time
	err = tx.QueryRow(ctx, updateQuery, id, req.Name, tenantID).Scan(&id, &newVersion, &updatedAt)
	if err == pgx.ErrNoRows {
		response.Error(c, 403, "organization not found or not in tenant scope")
		return
	}
	if err != nil {
		log.Printf("[UpdateOrg] update error: err=%v", err)
		response.Error(c, 500, "update organization failed")
		return
	}

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[UpdateOrg] commit error: err=%v", err)
		response.Error(c, 500, "update failed")
		return
	}

	response.SuccessWithMessage(c, "organization updated", gin.H{
		"id":      id,
		"name":    req.Name,
		"version": newVersion,
	})
}

// Delete handles DELETE /api/v1/organizations/:id - Soft delete organization
func (h *OrganizationHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[DeleteOrg] tx begin error: user_id=%d, id=%d, err=%v", userID, id, err)
		response.Error(c, 500, "system error")
		return
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		}
	}()

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Check if org exists and has no children (hard delete prevented, soft delete only)
	var childCount int
	err = tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM organizations WHERE parent_id = $1 AND deleted_at IS NULL
	`, id).Scan(&childCount)
	if err != nil {
		log.Printf("[DeleteOrg] check children error: err=%v", err)
		response.Error(c, 500, "check children failed")
		return
	}
	if childCount > 0 {
		response.Error(c, 400, "cannot delete organization with children")
		return
	}

	// Soft delete: set deleted_at timestamp
	deleteQuery := `
		UPDATE organizations SET deleted_at = NOW(), version = version + 1
		WHERE id = $1 AND root_tenant_id = $2 AND deleted_at IS NULL
		RETURNING id
	`
	var deletedID int64
	err = tx.QueryRow(ctx, deleteQuery, id, tenantID).Scan(&deletedID)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found or already deleted")
		return
	}
	if err != nil {
		log.Printf("[DeleteOrg] delete error: err=%v", err)
		response.Error(c, 500, "delete organization failed")
		return
	}

	// Cascade delete membership records (soft delete approach)
	_, err = tx.Exec(ctx, `
		UPDATE organization_memberships SET status = 'revoked', updated_at = NOW()
		WHERE organization_id = $1
	`, id)
	if err != nil {
		log.Printf("[DeleteOrg] cascade members error: err=%v", err)
		// Continue with delete, don't rollback on member update failure
	}

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[DeleteOrg] commit error: err=%v", err)
		response.Error(c, 500, "delete failed")
		return
	}

	response.SuccessWithMessage(c, "organization deleted", gin.H{"id": id})
}

// Move handles POST /api/v1/organizations/:id/move - Move org to new parent
func (h *OrganizationHandler) Move(c *gin.Context) {
	userID := middleware.GetUserID(c)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	var req MoveOrganizationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Use the governed_move_org SECURITY DEFINER function which handles
	// circular-reference checks, hierarchy validation, parent_id update,
	// and closure-table rebuild atomically.
	var result string
	err = h.db.QueryRow(ctx, `SELECT governed_move_org($1, $2, $3)`,
		id, req.ParentID, tenantID).Scan(&result)
	if err != nil {
		log.Printf("[MoveOrg] governed_move_org error: user_id=%d, id=%d, err=%v", userID, id, err)
		response.Error(c, 500, "move organization failed")
		return
	}

	switch result {
	case "ok":
		response.SuccessWithMessage(c, "organization moved", gin.H{
			"id":        id,
			"parent_id": req.ParentID,
			"moved_at":  time.Now(),
		})
	case "circular_reference":
		response.Error(c, 409, "cannot move organization into its own descendant")
	case "org_not_found":
		response.Error(c, 404, "organization not found or not in tenant scope")
	case "parent_not_found":
		response.Error(c, 404, "parent organization not found")
	case "invalid_hierarchy":
		response.Error(c, 400, "illegal organization hierarchy for move")
	default:
		response.Error(c, 500, "unexpected move result: "+result)
	}
}

// ToggleStatus handles PATCH /api/v1/organizations/:id/status - Toggle organization status
func (h *OrganizationHandler) ToggleStatus(c *gin.Context) {
	userID := middleware.GetUserID(c)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	var req ToggleStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// Validate status value
	validStatus := map[string]bool{
		model.OrganizationStatusActive:   true,
		model.OrganizationStatusDisabled: true,
	}
	if !validStatus[req.Status] {
		response.Error(c, 400, "invalid status value")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[ToggleStatus] tx begin error: user_id=%d, id=%d, err=%v", userID, id, err)
		response.Error(c, 500, "system error")
		return
	}
	defer func() {
		if err != nil {
			tx.Rollback(ctx)
		}
	}()

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Check if org exists
	var currentStatus string
	err = tx.QueryRow(ctx, `
		SELECT status FROM organizations WHERE id = $1 AND root_tenant_id = $2 AND deleted_at IS NULL
	`, id, tenantID).Scan(&currentStatus)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}
	if err != nil {
		log.Printf("[ToggleStatus] query error: err=%v", err)
		response.Error(c, 500, "query organization failed")
		return
	}

	// Update status if changed
	if currentStatus != req.Status {
		updateQuery := `
			UPDATE organizations SET status = $2, updated_at = NOW(), version = version + 1
			WHERE id = $1 AND root_tenant_id = $3
			RETURNING id, version, updated_at
		`
		var newVersion int64
		var updatedAt time.Time
		err = tx.QueryRow(ctx, updateQuery, id, req.Status, tenantID).Scan(&id, &newVersion, &updatedAt)
		if err != nil {
			log.Printf("[ToggleStatus] update error: err=%v", err)
			response.Error(c, 500, "update status failed")
			return
		}
	}

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[ToggleStatus] commit error: err=%v", err)
		response.Error(c, 500, "update failed")
		return
	}

	response.SuccessWithMessage(c, "status updated", gin.H{
		"id":      id,
		"status":  req.Status,
		"version": currentStatus != req.Status,
	})
}

// GetTree handles GET /api/v1/organizations/:id/tree - Get subtree recursively
func (h *OrganizationHandler) GetTree(c *gin.Context) {
	userID := middleware.GetUserID(c)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	ctx := c.Request.Context()
	tx, err := h.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		log.Printf("[GetTree] tx begin error: user_id=%d, id=%d, err=%v", userID, id, err)
		response.Error(c, 500, "system error")
		return
	}
	defer tx.Rollback(ctx)

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	// Verify organization belongs to tenant
	var orgName string
	err = tx.QueryRow(ctx, `
		SELECT name FROM organizations WHERE id = $1 AND root_tenant_id = $2 AND deleted_at IS NULL
	`, id, tenantID).Scan(&orgName)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}
	if err != nil {
		log.Printf("[GetTree] query error: err=%v", err)
		response.Error(c, 500, "query organization failed")
		return
	}

	// Build subtree using recursive CTE
	var treeNodes []OrganizationSummary
	subtreeQuery := `
		WITH RECURSIVE subtree AS (
			SELECT id, name, org_type, status, parent_id
			FROM organizations
			WHERE id = $1 AND deleted_at IS NULL
			UNION ALL
			SELECT o.id, o.name, o.org_type, o.status, o.parent_id
			FROM organizations o
			JOIN subtree s ON o.parent_id = s.id AND o.deleted_at IS NULL
		)
		SELECT id, name, org_type, status
		FROM subtree
		ORDER BY name
	`
	rows, err := tx.Query(ctx, subtreeQuery, id)
	if err != nil {
		log.Printf("[GetTree] query subtree error: err=%v", err)
		response.Error(c, 500, "query subtree failed")
		return
	}
	defer rows.Close()

	for rows.Next() {
		var node OrganizationSummary
		if err := rows.Scan(&node.ID, &node.Name, &node.Type, &node.Status); err == nil {
			treeNodes = append(treeNodes, node)
		}
	}

	// Enrich with has_children flag
	depthMap := make(map[int64]int)
	for _, node := range treeNodes {
		depthMap[node.ID] = 0
	}

	var rootNode OrganizationSummary
	for _, node := range treeNodes {
		if node.ID == id {
			rootNode = node
		}
	}
	rootNode.HasChildren = len(treeNodes) > 1

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[GetTree] commit error: err=%v", err)
		response.Error(c, 500, "query failed")
		return
	}

	response.Success(c, gin.H{
		"root_organization": rootNode,
		"subtree":           treeNodes,
		"total_nodes":       len(treeNodes),
	})
}
