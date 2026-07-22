package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"inv-api-server/internal/model"
)

type OrganizationRepository struct{ db authorizationDB }

func NewOrganizationRepository(db *pgxpool.Pool) *OrganizationRepository {
	return newOrganizationRepository(db)
}

func newOrganizationRepository(db authorizationDB) *OrganizationRepository {
	return &OrganizationRepository{db: db}
}

const visibleOrganizationsSQL = `
	WITH active_context AS (
		SELECT m.root_tenant_id,m.organization_id,m.id AS membership_id,m.user_id
		FROM organization_memberships m
		JOIN organizations active_org
		  ON active_org.root_tenant_id=m.root_tenant_id AND active_org.id=m.organization_id
		JOIN users actor_user ON actor_user.id=m.user_id
		WHERE m.root_tenant_id=$1 AND m.user_id=$2 AND m.organization_id=$3
		  AND m.id=$4 AND m.version=$5 AND m.status='active'
		  AND (m.expires_at IS NULL OR m.expires_at>NOW())
		  AND active_org.status='active' AND active_org.deleted_at IS NULL
		  AND actor_user.status=1 AND actor_user.deleted_at IS NULL
		  AND NOT EXISTS (
			SELECT 1 FROM organization_closure active_path
			JOIN organizations active_ancestor
			  ON active_ancestor.root_tenant_id=active_path.root_tenant_id
			 AND active_ancestor.id=active_path.ancestor_id
			WHERE active_path.root_tenant_id=m.root_tenant_id
			  AND active_path.descendant_id=m.organization_id
			  AND (active_ancestor.status<>'active' OR active_ancestor.deleted_at IS NOT NULL)
		  )
	)
	SELECT target.id,target.root_tenant_id,target.parent_id,target.org_type,
	       COALESCE(target.code,''),target.name,target.status,target.version,
	       target.created_at,target.updated_at,target.deleted_at
	FROM organizations target
	WHERE target.root_tenant_id=$1 AND target.status='active' AND target.deleted_at IS NULL
	  AND NOT EXISTS (
		SELECT 1 FROM organization_closure target_path
		JOIN organizations target_ancestor
		  ON target_ancestor.root_tenant_id=target_path.root_tenant_id
		 AND target_ancestor.id=target_path.ancestor_id
		WHERE target_path.root_tenant_id=target.root_tenant_id
		  AND target_path.descendant_id=target.id
		  AND (target_ancestor.status<>'active' OR target_ancestor.deleted_at IS NOT NULL)
	  )
	  AND EXISTS (
		SELECT 1
		FROM active_context ac
		JOIN membership_role_assignments ra
		  ON ra.root_tenant_id=ac.root_tenant_id AND ra.organization_id=ac.organization_id
		 AND ra.membership_id=ac.membership_id AND ra.status='active'
		JOIN role_permission_grants pg
		  ON pg.root_tenant_id=ra.root_tenant_id AND pg.organization_id=ra.organization_id
		 AND pg.role_assignment_id=ra.id AND pg.permission_code=$6
		WHERE (
			CASE pg.data_scope
				WHEN 'organization' THEN target.id=ac.organization_id
				WHEN 'organization_and_descendants' THEN EXISTS (
					SELECT 1 FROM organization_closure c
					WHERE c.root_tenant_id=ac.root_tenant_id
					  AND c.ancestor_id=ac.organization_id AND c.descendant_id=target.id
				)
				WHEN 'assigned_resources' THEN EXISTS (
					SELECT 1 FROM authorization_resources ar
					JOIN resource_grants rg
					  ON rg.root_tenant_id=ar.root_tenant_id AND rg.organization_id=ar.organization_id
					 AND rg.resource_type=ar.resource_type AND rg.resource_id=ar.resource_id
					WHERE ar.root_tenant_id=ac.root_tenant_id AND ar.resource_type='organization'
					  AND ar.resource_id=target.id::TEXT AND ar.status='active'
					  AND rg.root_tenant_id=ac.root_tenant_id AND rg.status='active'
					  AND rg.valid_from<=NOW() AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
					  AND split_part($6,':',2)=ANY(rg.permissions)
					  AND (rg.subject_organization_id=ac.organization_id
					       OR (rg.subject_user_id=ac.user_id AND rg.subject_membership_id=ac.membership_id))
				)
				WHEN 'explicit_resources' THEN EXISTS (
					SELECT 1 FROM resource_grants rg
					WHERE rg.root_tenant_id=ac.root_tenant_id AND rg.resource_type='organization'
					  AND rg.resource_id=target.id::TEXT AND rg.status='active'
					  AND rg.valid_from<=NOW() AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
					  AND split_part($6,':',2)=ANY(rg.permissions)
					  AND (rg.subject_organization_id=ac.organization_id
					       OR (rg.subject_user_id=ac.user_id AND rg.subject_membership_id=ac.membership_id))
				)
				ELSE FALSE
			END
		)
		AND CASE
			WHEN NOT (pg.scope_definition ? 'organization_ids') THEN TRUE
			WHEN jsonb_typeof(pg.scope_definition->'organization_ids') <> 'array' THEN FALSE
			ELSE EXISTS (
				SELECT 1
				FROM jsonb_array_elements_text(pg.scope_definition->'organization_ids') scoped(value)
				WHERE scoped.value=target.id::TEXT
				  AND EXISTS (
					SELECT 1 FROM organization_closure scoped_closure
					WHERE scoped_closure.root_tenant_id=ac.root_tenant_id
					  AND scoped_closure.ancestor_id=ac.organization_id
					  AND scoped_closure.descendant_id=target.id
				  )
			)
		END
	)
	ORDER BY target.id
	LIMIT $7 OFFSET $8
`

const countVisibleOrganizationsSQL = `SELECT COUNT(*) FROM (` + visibleOrganizationsSQL + `) visible_organizations`
const existsVisibleOrganizationSQL = `SELECT EXISTS(SELECT 1 FROM (` + visibleOrganizationsSQL + `) visible_organizations WHERE visible_organizations.id=$9)`

func (r *OrganizationRepository) ListVisible(ctx context.Context, plan model.ScopePlan, limit, offset int) ([]model.Organization, error) {
	if plan.DenyReason != "" || plan.ResourceType != "organization" || !plan.Actor.Valid() || len(plan.Grants) == 0 || limit <= 0 || offset < 0 {
		return []model.Organization{}, nil
	}
	actor := plan.Actor
	rows, err := r.db.Query(ctx, visibleOrganizationsSQL,
		actor.RootTenantID, actor.UserID, actor.OrganizationID, actor.MembershipID, actor.MembershipVersion,
		plan.PermissionCode, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	organizations := make([]model.Organization, 0)
	for rows.Next() {
		var organization model.Organization
		var persistenceStatus string
		if err := rows.Scan(
			&organization.ID, &organization.RootTenantID, &organization.ParentID, &organization.Type,
			&organization.Code, &organization.Name, &persistenceStatus, &organization.Version,
			&organization.CreatedAt, &organization.UpdatedAt, &organization.DeletedAt,
		); err != nil {
			return nil, err
		}
		organization.Status = model.ProjectOrganizationStatus(persistenceStatus)
		organizations = append(organizations, organization)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return organizations, nil
}

func (r *OrganizationRepository) CountVisible(ctx context.Context, plan model.ScopePlan) (int64, error) {
	if plan.DenyReason != "" || plan.ResourceType != "organization" || !plan.Actor.Valid() || len(plan.Grants) == 0 {
		return 0, nil
	}
	actor := plan.Actor
	var count int64
	err := r.db.QueryRow(ctx, countVisibleOrganizationsSQL,
		actor.RootTenantID, actor.UserID, actor.OrganizationID, actor.MembershipID, actor.MembershipVersion,
		plan.PermissionCode, int64(^uint64(0)>>1), 0).Scan(&count)
	return count, err
}

func (r *OrganizationRepository) ExistsVisible(ctx context.Context, plan model.ScopePlan, organizationID int64) (bool, error) {
	if plan.DenyReason != "" || plan.ResourceType != "organization" || !plan.Actor.Valid() || len(plan.Grants) == 0 || organizationID <= 0 {
		return false, nil
	}
	actor := plan.Actor
	var exists bool
	err := r.db.QueryRow(ctx, existsVisibleOrganizationSQL,
		actor.RootTenantID, actor.UserID, actor.OrganizationID, actor.MembershipID, actor.MembershipVersion,
		plan.PermissionCode, int64(^uint64(0)>>1), 0, organizationID).Scan(&exists)
	return exists, err
}

func (r *OrganizationRepository) ListVisibleMemberships(ctx context.Context, plan model.ScopePlan, organizationID int64, limit, offset int) ([]model.OrganizationMembership, error) {
	if plan.DenyReason != "" || plan.ResourceType != "member" || !plan.Actor.Valid() || len(plan.Grants) == 0 || organizationID <= 0 || limit <= 0 || offset < 0 {
		return []model.OrganizationMembership{}, nil
	}
	actor := plan.Actor
	rows, err := r.db.Query(ctx, `
		WITH active_context AS (
			SELECT m.root_tenant_id,m.organization_id,m.id AS membership_id,m.user_id
			FROM organization_memberships m
			JOIN organizations o ON o.root_tenant_id=m.root_tenant_id AND o.id=m.organization_id
			JOIN users actor_user ON actor_user.id=m.user_id
			WHERE m.root_tenant_id=$1 AND m.user_id=$2 AND m.organization_id=$3
			  AND m.id=$4 AND m.version=$5 AND m.status='active'
			  AND (m.expires_at IS NULL OR m.expires_at>NOW())
			  AND o.status='active' AND o.deleted_at IS NULL
			  AND actor_user.status=1 AND actor_user.deleted_at IS NULL
			  AND NOT EXISTS (
				SELECT 1 FROM organization_closure active_path
				JOIN organizations active_ancestor
				  ON active_ancestor.root_tenant_id=active_path.root_tenant_id
				 AND active_ancestor.id=active_path.ancestor_id
				WHERE active_path.root_tenant_id=m.root_tenant_id
				  AND active_path.descendant_id=m.organization_id
				  AND (active_ancestor.status<>'active' OR active_ancestor.deleted_at IS NOT NULL)
			  )
		)
		SELECT candidate.id,candidate.root_tenant_id,candidate.organization_id,candidate.user_id,
		       candidate.status,candidate.version,candidate.expires_at
		FROM organization_memberships candidate
		JOIN organizations candidate_org
		  ON candidate_org.root_tenant_id=candidate.root_tenant_id AND candidate_org.id=candidate.organization_id
		WHERE candidate.root_tenant_id=$1 AND candidate.organization_id=$7
		  AND candidate_org.status='active' AND candidate_org.deleted_at IS NULL
		  AND NOT EXISTS (
			SELECT 1 FROM organization_closure candidate_path
			JOIN organizations candidate_ancestor
			  ON candidate_ancestor.root_tenant_id=candidate_path.root_tenant_id
			 AND candidate_ancestor.id=candidate_path.ancestor_id
			WHERE candidate_path.root_tenant_id=candidate.root_tenant_id
			  AND candidate_path.descendant_id=candidate.organization_id
			  AND (candidate_ancestor.status<>'active' OR candidate_ancestor.deleted_at IS NOT NULL)
		  )
		  AND EXISTS (
			SELECT 1 FROM active_context ac
			JOIN membership_role_assignments ra
			  ON ra.root_tenant_id=ac.root_tenant_id AND ra.organization_id=ac.organization_id
			 AND ra.membership_id=ac.membership_id AND ra.status='active'
			JOIN role_permission_grants pg
			  ON pg.root_tenant_id=ra.root_tenant_id AND pg.organization_id=ra.organization_id
			 AND pg.role_assignment_id=ra.id AND pg.permission_code=$6
			WHERE candidate.root_tenant_id=ac.root_tenant_id
			  AND CASE pg.data_scope
				WHEN 'self' THEN candidate.user_id=ac.user_id AND candidate.organization_id=ac.organization_id
				WHEN 'organization' THEN candidate.organization_id=ac.organization_id
				WHEN 'organization_and_descendants' THEN EXISTS (
					SELECT 1 FROM organization_closure c
					WHERE c.root_tenant_id=ac.root_tenant_id
					  AND c.ancestor_id=ac.organization_id AND c.descendant_id=candidate.organization_id
				)
				WHEN 'assigned_resources' THEN EXISTS (
					SELECT 1 FROM authorization_resources ar
					JOIN resource_grants rg
					  ON rg.root_tenant_id=ar.root_tenant_id AND rg.organization_id=ar.organization_id
					 AND rg.resource_type=ar.resource_type AND rg.resource_id=ar.resource_id
					WHERE ar.root_tenant_id=ac.root_tenant_id AND ar.resource_type='user'
					  AND ar.resource_id=candidate.user_id::TEXT AND ar.status='active'
					  AND rg.status='active' AND rg.valid_from<=NOW()
					  AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
					  AND split_part($6,':',2)=ANY(rg.permissions)
					  AND (rg.subject_organization_id=ac.organization_id
					       OR (rg.subject_user_id=ac.user_id AND rg.subject_membership_id=ac.membership_id))
				)
				WHEN 'explicit_resources' THEN EXISTS (
					SELECT 1 FROM resource_grants rg
					WHERE rg.root_tenant_id=ac.root_tenant_id AND rg.resource_type='user'
					  AND rg.resource_id=candidate.user_id::TEXT AND rg.status='active'
					  AND rg.valid_from<=NOW() AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
					  AND split_part($6,':',2)=ANY(rg.permissions)
					  AND (rg.subject_organization_id=ac.organization_id
					       OR (rg.subject_user_id=ac.user_id AND rg.subject_membership_id=ac.membership_id))
				)
				ELSE FALSE
			END
			  AND CASE
				WHEN NOT (pg.scope_definition ? 'organization_ids') THEN TRUE
				WHEN jsonb_typeof(pg.scope_definition->'organization_ids') <> 'array' THEN FALSE
				ELSE EXISTS (
					SELECT 1 FROM jsonb_array_elements_text(pg.scope_definition->'organization_ids') scoped(value)
					WHERE scoped.value=candidate.organization_id::TEXT
					  AND EXISTS (
						SELECT 1 FROM organization_closure scoped_closure
						WHERE scoped_closure.root_tenant_id=ac.root_tenant_id
						  AND scoped_closure.ancestor_id=ac.organization_id
						  AND scoped_closure.descendant_id=candidate.organization_id
					  )
				)
			  END
		  )
		ORDER BY candidate.id LIMIT $8 OFFSET $9
	`, actor.RootTenantID, actor.UserID, actor.OrganizationID, actor.MembershipID, actor.MembershipVersion,
		plan.PermissionCode, organizationID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	memberships := make([]model.OrganizationMembership, 0)
	for rows.Next() {
		var membership model.OrganizationMembership
		var persistenceStatus string
		if err := rows.Scan(&membership.ID, &membership.RootTenantID, &membership.OrganizationID, &membership.UserID,
			&persistenceStatus, &membership.Version, &membership.ExpiresAt); err != nil {
			return nil, err
		}
		membership.Status = model.ProjectMembershipStatus(persistenceStatus)
		memberships = append(memberships, membership)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return memberships, nil
}

// GetByID retrieves an organization by its ID
func (r *OrganizationRepository) GetByID(ctx context.Context, id int64) (*model.Organization, error) {
	query := `
		SELECT id, root_tenant_id, parent_id, org_type,
		       COALESCE(code, ''), name, status, version,
		       created_at, updated_at, deleted_at
		FROM organizations
		WHERE id = $1 AND deleted_at IS NULL
	`
	var org model.Organization
	var persistenceStatus string
	err := r.db.QueryRow(ctx, query, id).Scan(
		&org.ID, &org.RootTenantID, &org.ParentID, &org.Type,
		&org.Code, &org.Name, &persistenceStatus, &org.Version,
		&org.CreatedAt, &org.UpdatedAt, &org.DeletedAt,
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

// CreateMembership inserts a new organization membership within a transaction
func (r *OrganizationRepository) CreateMembership(ctx context.Context, tx pgx.Tx, membership *model.OrganizationMembership) error {
	query := `
		INSERT INTO organization_memberships (root_tenant_id, organization_id, user_id, status, version)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`
	return tx.QueryRow(ctx, query,
		membership.RootTenantID, membership.OrganizationID, membership.UserID,
		membership.Status, membership.Version,
	).Scan(&membership.ID)
}

// CreateRoleAssignment inserts a new membership role assignment within a transaction
func (r *OrganizationRepository) CreateRoleAssignment(ctx context.Context, tx pgx.Tx, ra *model.MembershipRoleAssignment) error {
	query := `
		INSERT INTO membership_role_assignments (root_tenant_id, organization_id, membership_id, role_code, status, version)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`
	return tx.QueryRow(ctx, query,
		ra.RootTenantID, ra.OrganizationID, ra.MembershipID,
		ra.RoleCode, ra.Status, ra.Version,
	).Scan(&ra.ID)
}
