package handler

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// OrganizationHandler handles organization management operations
type OrganizationHandler struct {
	db          *pgxpool.Pool
	permChecker interface{} // Will be set when service layer is available
}

// CreateOrganizationRequest represents a request to create a new organization unit
type CreateOrganizationRequest struct {
	Name       string  `json:"name" binding:"required"`
	Type       string  `json:"type" binding:"required"`
	ParentID   *int64  `json:"parent_id"`             // nil = direct child of root tenant
	Code       *string `json:"code,omitempty"`        // optional org code
	AdminEmail *string `json:"admin_email,omitempty"` // optional: assign existing user as org admin
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
	isSystemAdmin := middleware.GetIsSystemAdmin(c)

	var req CreateOrganizationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	// Debug log
	logger.Info("CreateOrganization request",
			zap.String("name", req.Name),
			zap.String("type", req.Type),
			zap.Bool("isSystemAdmin", isSystemAdmin))

	// Only system admins can create orgs during migration period
	if !isSystemAdmin {
		response.Error(c, 403, "end users cannot create organizations")
		return
	}

	// Validate organization type.
	// "manufacturer" cannot be created via the API — the root manufacturer
	// org is provisioned automatically by ensure_tenant_root().
	// Channel hierarchy: manufacturer -> agent -> distributor -> installer -> customer
	validTypes := map[string]bool{
		"agent":           true,
		"distributor":     true,
		"installer":       true,
		"customer":        true,
		"service_partner": true,
	}
	if !validTypes[req.Type] {
		logger.Warn("invalid organization type", zap.String("type", req.Type))
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

	// If ParentID provided, validate it belongs to same root_tenant and check hierarchy
	var parentID *int64
	var parentType string
	if req.ParentID != nil {
		var checkTenantID int64
		err = tx.QueryRow(ctx, `
			SELECT root_tenant_id, org_type FROM organizations WHERE id = $1 AND deleted_at IS NULL
		`, *req.ParentID).Scan(&checkTenantID, &parentType)
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
		parentType = "manufacturer"
	}

	// Validate hierarchy: enforce strict parent-child type rules
	hierarchyRules := map[string]string{
		"agent":           "manufacturer",
		"distributor":     "agent",
		"installer":       "distributor",
		"customer":        "installer",
		"service_partner": "manufacturer",
	}
	if expectedParent, ok := hierarchyRules[req.Type]; ok {
		if req.Type == "customer" {
			// customer can also be directly under manufacturer (unassigned pool)
			if parentType != "installer" && parentType != "manufacturer" {
				tx.Rollback(ctx)
				response.Error(c, 400, fmt.Sprintf("customer must be under installer or manufacturer, but parent is %s", parentType))
				return
			}
		} else if req.Type == "service_partner" {
			if parentType != "manufacturer" && parentType != "agent" {
				tx.Rollback(ctx)
				response.Error(c, 400, fmt.Sprintf("service_partner must be under manufacturer or agent, but parent is %s", parentType))
				return
			}
		} else if parentType != expectedParent {
			tx.Rollback(ctx)
			response.Error(c, 400, fmt.Sprintf("%s must be under %s, but parent is %s", req.Type, expectedParent, parentType))
			return
		}
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

	var orgCode *string
	if req.Code != nil && *req.Code != "" {
		orgCode = req.Code
	}

	err = tx.QueryRow(ctx, `
		INSERT INTO organizations (root_tenant_id, parent_id, org_type, code, name, status, version)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, created_at, updated_at
	`, org.RootTenantID, org.ParentID, org.Type, orgCode, org.Name, org.Status, org.Version).
		Scan(&org.ID, &org.CreatedAt, &org.UpdatedAt)
	if err != nil {
		tx.Rollback(ctx)
		log.Printf("[CreateOrg] insert error: user_id=%d, tenant_id=%d, parent_id=%v, type=%s, err=%v", userID, tenantID, parentID, req.Type, err)
		response.Error(c, 500, fmt.Sprintf("create organization failed: %v", err))
		return
	}

	// If admin_email provided, find user and create membership
	if req.AdminEmail != nil && *req.AdminEmail != "" {
		var adminUserID int64
		err = tx.QueryRow(ctx, `
			SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL
		`, *req.AdminEmail).Scan(&adminUserID)
		if err != nil {
			if err == pgx.ErrNoRows {
				tx.Rollback(ctx)
				response.Error(c, 404, fmt.Sprintf("user with email %s not found", *req.AdminEmail))
				return
			}
			tx.Rollback(ctx)
			log.Printf("[CreateOrg] query admin user error: err=%v", err)
			response.Error(c, 500, "query admin user failed")
			return
		}

		// Create membership
		var membershipID int64
		err = tx.QueryRow(ctx, `
			INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
			VALUES ($1, $2, $3, 'active')
			RETURNING id
		`, tenantID, org.ID, adminUserID).Scan(&membershipID)
		if err != nil {
			tx.Rollback(ctx)
			log.Printf("[CreateOrg] create membership error: org_id=%d, user_id=%d, err=%v", org.ID, adminUserID, err)
			response.Error(c, 500, fmt.Sprintf("create membership failed: %v", err))
			return
		}
		// Assign org_admin role
		_, err = tx.Exec(ctx, `
			INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, assigned_by)
			VALUES ($1, $2, $3, 'org_admin', $4)
		`, tenantID, org.ID, membershipID, userID)
		if err != nil {
			tx.Rollback(ctx)
			log.Printf("[CreateOrg] assign role error: membership_id=%d, err=%v", membershipID, err)
			response.Error(c, 500, fmt.Sprintf("assign admin role failed: %v", err))
			return
		}
	}

	// Initialize default quotas for the new org (inherit from parent if exists)
	defaultQuotas := []struct {
		resourceType string
		limit        int64
	}{
		{"members", 100},
		{"direct_child_organizations", 50},
		{"descendant_organizations", 200},
		{"inventory_devices", 1000},
		{"claimed_devices", 500},
		{"stations", 200},
		{"pending_invitations", 20},
	}
	for _, q := range defaultQuotas {
		_, err = tx.Exec(ctx, `
			INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (root_tenant_id, organization_id, resource_type) DO NOTHING
		`, tenantID, org.ID, q.resourceType, q.limit, parentID)
		if err != nil {
			log.Printf("[CreateOrg] init quota warning: resource_type=%s, err=%v", q.resourceType, err)
			// Don't fail for quota init issues
		}
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

// List handles GET /api/v1/organizations - List organizations (returns array for frontend compatibility)
func (h *OrganizationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isSystemAdmin := middleware.GetIsSystemAdmin(c)

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

	// System admin sees all organizations
	_ = isSystemAdmin
	
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

	query += ` GROUP BY o.id ORDER BY o.created_at DESC`

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

	if err = tx.Commit(ctx); err != nil {
		log.Printf("[ListOrg] commit error: err=%v", err)
		response.Error(c, 500, "query failed")
		return
	}

	// Return as array for frontend compatibility (OrganizationTree expects array)
	if orgs == nil {
		orgs = []OrganizationWithChildren{}
	}
	response.Success(c, orgs)
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

// ── GetOrgHierarchy: GET /api/v1/organizations/hierarchy ──
// Returns the full org tree with member_count and device_count per node.
func (h *OrganizationHandler) GetOrgHierarchy(c *gin.Context) {
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	ctx := c.Request.Context()

	type HierarchyNode struct {
		ID           int64            `json:"id"`
		ParentID     *int64           `json:"parent_id"`
		Name         string           `json:"name"`
		Type         string           `json:"type"`
		Code         string           `json:"code"`
		Status       string           `json:"status"`
		MemberCount  int              `json:"member_count"`
		DeviceCount  int              `json:"device_count"`
		ChildCount   int              `json:"children_count"`
		Children     []*HierarchyNode `json:"children,omitempty"`
	}

	rows, err := h.db.Query(ctx, `
		SELECT o.id, o.parent_id, o.name, o.org_type, COALESCE(o.code, ''), o.status,
			(SELECT COUNT(*) FROM organization_memberships m
				WHERE m.organization_id = o.id AND m.status = 'active') AS member_count,
			(SELECT COUNT(*) FROM authorization_resources ar
				WHERE ar.organization_id = o.id AND ar.resource_type = 'device' AND ar.status = 'active') AS device_count,
			(SELECT COUNT(*) FROM organizations c
				WHERE c.parent_id = o.id AND c.deleted_at IS NULL) AS child_count
		FROM organizations o
		WHERE o.root_tenant_id = $1 AND o.deleted_at IS NULL
		ORDER BY o.created_at
	`, tenantID)
	if err != nil {
		log.Printf("[GetOrgHierarchy] query error: err=%v", err)
		response.Error(c, 500, "query hierarchy failed")
		return
	}
	defer rows.Close()

	nodeMap := make(map[int64]*HierarchyNode)
	var roots []*HierarchyNode
	for rows.Next() {
		n := &HierarchyNode{}
		if err := rows.Scan(&n.ID, &n.ParentID, &n.Name, &n.Type, &n.Code, &n.Status,
			&n.MemberCount, &n.DeviceCount, &n.ChildCount); err != nil {
			continue
		}
		nodeMap[n.ID] = n
	}
	for _, n := range nodeMap {
		if n.ParentID == nil || nodeMap[*n.ParentID] == nil {
			roots = append(roots, n)
		} else {
			parent := nodeMap[*n.ParentID]
			parent.Children = append(parent.Children, n)
		}
	}

	response.Success(c, roots)
}

// ── GetOrgQuota: GET /api/v1/organizations/:id/quota ──
func (h *OrganizationHandler) GetOrgQuota(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	ctx := c.Request.Context()

	// Verify org belongs to tenant
	var orgName string
	err = h.db.QueryRow(ctx,
		`SELECT name FROM organizations WHERE id = $1 AND root_tenant_id = $2 AND deleted_at IS NULL`,
		id, tenantID).Scan(&orgName)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}
	if err != nil {
		response.Error(c, 500, "query failed")
		return
	}

	type QuotaItem struct {
		ResourceType string `json:"resource_type"`
		QuotaLimit   int64  `json:"quota_limit"`
		UsedCount    int64  `json:"used_count"`
		ReservedCount int64 `json:"reserved_count"`
		InheritedFrom *int64 `json:"inherited_from_organization_id,omitempty"`
	}

	rows, err := h.db.Query(ctx, `
		SELECT q.resource_type, q.quota_limit,
			COALESCE(u.used_count, 0), COALESCE(u.reserved_count, 0),
			q.inherited_from_organization_id
		FROM organization_quotas q
		LEFT JOIN organization_quota_usage u
			ON u.root_tenant_id = q.root_tenant_id
			AND u.organization_id = q.organization_id
			AND u.resource_type = q.resource_type
		WHERE q.root_tenant_id = $1 AND q.organization_id = $2
		ORDER BY q.resource_type
	`, tenantID, id)
	if err != nil {
		log.Printf("[GetOrgQuota] query error: err=%v", err)
		response.Error(c, 500, "query quota failed")
		return
	}
	defer rows.Close()

	var quotas []QuotaItem
	for rows.Next() {
		var q QuotaItem
		if err := rows.Scan(&q.ResourceType, &q.QuotaLimit, &q.UsedCount, &q.ReservedCount, &q.InheritedFrom); err != nil {
			continue
		}
		quotas = append(quotas, q)
	}
	if quotas == nil {
		quotas = []QuotaItem{}
	}
	response.Success(c, quotas)
}

// ── SetOrgQuota: PUT /api/v1/organizations/:id/quota ──
func (h *OrganizationHandler) SetOrgQuota(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	var req struct {
		Quotas []struct {
			ResourceType string `json:"resource_type" binding:"required"`
			QuotaLimit   int64  `json:"quota_limit" binding:"required"`
		} `json:"quotas" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	ctx := c.Request.Context()

	// Verify org exists
	var orgType string
	err = h.db.QueryRow(ctx,
		`SELECT org_type FROM organizations WHERE id = $1 AND root_tenant_id = $2 AND deleted_at IS NULL`,
		id, tenantID).Scan(&orgType)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}

	for _, q := range req.Quotas {
		_, err = h.db.Exec(ctx, `
			INSERT INTO organization_quotas (root_tenant_id, organization_id, resource_type, quota_limit, inherited_from_organization_id)
			VALUES ($1, $2, $3, $4, (SELECT parent_id FROM organizations WHERE id = $2))
			ON CONFLICT (root_tenant_id, organization_id, resource_type)
			DO UPDATE SET quota_limit = $4, updated_at = NOW()
		`, tenantID, id, q.ResourceType, q.QuotaLimit)
		if err != nil {
			log.Printf("[SetOrgQuota] upsert error: resource=%s, err=%v", q.ResourceType, err)
		}
	}

	response.SuccessWithMessage(c, "quota updated", gin.H{"organization_id": id})
}

// ── JoinOrg: POST /api/v1/organizations/:id/join ──
// User requests to join an organization (creates pending invitation).
func (h *OrganizationHandler) JoinOrg(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	ctx := c.Request.Context()

	// Check org exists
	var orgName string
	err = h.db.QueryRow(ctx,
		`SELECT name FROM organizations WHERE id = $1 AND root_tenant_id = $2 AND deleted_at IS NULL`,
		id, tenantID).Scan(&orgName)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "organization not found")
		return
	}

	// Check if already a member
	var existingID int64
	err = h.db.QueryRow(ctx,
		`SELECT id FROM organization_memberships WHERE organization_id = $1 AND user_id = $2 AND status = 'active'`,
		id, userID).Scan(&existingID)
	if err == nil {
		response.Error(c, 409, "already a member of this organization")
		return
	}

	// Check if already has pending invitation
	err = h.db.QueryRow(ctx,
		`SELECT id FROM invitations WHERE organization_id = $1 AND recipient = (SELECT email FROM users WHERE id = $2) AND status = 'pending'`,
		id, userID).Scan(&existingID)
	if err == nil {
		response.Error(c, 409, "join request already pending")
		return
	}

	// Create invitation (pending join request)
	var userEmail string
	h.db.QueryRow(ctx, `SELECT email FROM users WHERE id = $1`, userID).Scan(&userEmail)

	_, err = h.db.Exec(ctx, `
		INSERT INTO invitations (root_tenant_id, organization_id, recipient, token_key_id, token_digest, role_assignments, invited_by, expires_at)
		VALUES ($1, $2, $3, 'join_request', decode(md5(random()::text), 'hex'), '[{"role_code": "viewer"}]'::jsonb, $4, NOW() + INTERVAL '72 hours')
	`, tenantID, id, userEmail, userID)
	if err != nil {
		log.Printf("[JoinOrg] insert error: err=%v", err)
		response.Error(c, 500, "join request failed")
		return
	}

	response.SuccessWithMessage(c, "join request submitted", gin.H{
		"organization_id": id,
		"organization_name": orgName,
		"status": "pending",
	})
}

// ── ApproveJoin: POST /api/v1/organizations/:id/approve-join ──
// Admin approves a join request (accepts invitation and creates membership).
func (h *OrganizationHandler) ApproveJoin(c *gin.Context) {
	adminUserID := middleware.GetUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid organization id")
		return
	}

	var req struct {
		UserID int64  `json:"user_id" binding:"required"`
		Action string `json:"action" binding:"required"` // approve / reject
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}

	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	ctx := c.Request.Context()

	if req.Action == "approve" {
		// Create membership
		var membershipID int64
		err = h.db.QueryRow(ctx, `
			INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status)
			VALUES ($1, $2, $3, 'active')
			ON CONFLICT (root_tenant_id, organization_id, user_id) WHERE status = 'active'
			DO NOTHING
			RETURNING id
		`, tenantID, id, req.UserID).Scan(&membershipID)
		if err != nil && err != pgx.ErrNoRows {
			log.Printf("[ApproveJoin] create membership error: err=%v", err)
			response.Error(c, 500, "approve failed")
			return
		}

		// Update invitation status
		_, _ = h.db.Exec(ctx, `
			UPDATE invitations SET status = 'accepted', accepted_at = NOW(), updated_at = NOW()
			WHERE organization_id = $1 AND recipient = (SELECT email FROM users WHERE id = $2) AND status = 'pending'
		`, id, req.UserID)

		response.SuccessWithMessage(c, "join approved", gin.H{"user_id": req.UserID, "organization_id": id})
	} else {
		// Reject
		_, _ = h.db.Exec(ctx, `
			UPDATE invitations SET status = 'rejected', updated_at = NOW()
			WHERE organization_id = $1 AND recipient = (SELECT email FROM users WHERE id = $2) AND status = 'pending'
		`, id, req.UserID)

		response.SuccessWithMessage(c, "join rejected", gin.H{"user_id": req.UserID, "organization_id": id})
	}
	_ = adminUserID
}

// ── MyOrganizations: GET /api/v1/my/organizations ──
// Returns organizations the current user belongs to.
func (h *OrganizationHandler) MyOrganizations(c *gin.Context) {
	userID := middleware.GetUserID(c)
	tenantID := middleware.GetRootTenantID(c)
	if tenantID == 0 {
		response.Error(c, 403, "tenant context missing")
		return
	}

	ctx := c.Request.Context()

	type MyOrg struct {
		ID       int64  `json:"id"`
		Name     string `json:"name"`
		Type     string `json:"type"`
		Status   string `json:"status"`
		Role     string `json:"role"`
		JoinedAt string `json:"joined_at"`
	}

	rows, err := h.db.Query(ctx, `
		SELECT o.id, o.name, o.org_type, o.status,
			COALESCE((SELECT string_agg(ra.role_code, ',') FROM membership_role_assignments ra
				WHERE ra.membership_id = m.id AND ra.status = 'active'), 'viewer') AS role,
			m.joined_at
		FROM organization_memberships m
		JOIN organizations o ON o.id = m.organization_id AND o.deleted_at IS NULL
		WHERE m.user_id = $1 AND m.root_tenant_id = $2 AND m.status = 'active'
		ORDER BY m.joined_at DESC
	`, userID, tenantID)
	if err != nil {
		log.Printf("[MyOrganizations] query error: err=%v", err)
		response.Error(c, 500, "query failed")
		return
	}
	defer rows.Close()

	var orgs []MyOrg
	for rows.Next() {
		var o MyOrg
		if err := rows.Scan(&o.ID, &o.Name, &o.Type, &o.Status, &o.Role, &o.JoinedAt); err != nil {
			continue
		}
		orgs = append(orgs, o)
	}
	if orgs == nil {
		orgs = []MyOrg{}
	}
	response.Success(c, orgs)
}
