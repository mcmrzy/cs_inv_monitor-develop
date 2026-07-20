package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"inv-api-server/internal/model"
)

type authorizationDB interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type AuthorizationRepository struct{ db authorizationDB }

func NewAuthorizationRepository(db *pgxpool.Pool) *AuthorizationRepository {
	return newAuthorizationRepository(db)
}

func newAuthorizationRepository(db authorizationDB) *AuthorizationRepository {
	return &AuthorizationRepository{db: db}
}

func (r *AuthorizationRepository) ValidateContext(ctx context.Context, actor model.ActorContext) (bool, error) {
	var active bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM organization_memberships m
			JOIN organizations o
			  ON o.root_tenant_id=m.root_tenant_id AND o.id=m.organization_id
			JOIN users u ON u.id=m.user_id
			WHERE m.root_tenant_id=$1 AND m.user_id=$2 AND m.organization_id=$3
			  AND m.id=$4 AND m.version=$5
			  AND m.status='active' AND (m.expires_at IS NULL OR m.expires_at>NOW())
			  AND o.status='active' AND o.deleted_at IS NULL
			  AND u.status=1 AND u.deleted_at IS NULL
			  AND NOT EXISTS (
				SELECT 1 FROM organization_closure c
				JOIN organizations ancestor
				  ON ancestor.root_tenant_id=c.root_tenant_id AND ancestor.id=c.ancestor_id
				WHERE c.root_tenant_id=m.root_tenant_id AND c.descendant_id=m.organization_id
				  AND (ancestor.status<>'active' OR ancestor.deleted_at IS NOT NULL)
			  )
		)
	`, actor.RootTenantID, actor.UserID, actor.OrganizationID, actor.MembershipID, actor.MembershipVersion).Scan(&active)
	return active, err
}

func (r *AuthorizationRepository) LoadPermissionGrants(ctx context.Context, actor model.ActorContext, permissionCode string) ([]model.PermissionGrant, error) {
	rows, err := r.db.Query(ctx, `
		SELECT pg.id,ra.id,ra.role_code,pg.permission_code,pg.data_scope,pg.scope_definition
		FROM organization_memberships m
		JOIN organizations o
		  ON o.root_tenant_id=m.root_tenant_id AND o.id=m.organization_id
		JOIN users u ON u.id=m.user_id
		JOIN membership_role_assignments ra
		  ON ra.root_tenant_id=m.root_tenant_id
		 AND ra.organization_id=m.organization_id
		 AND ra.membership_id=m.id
		JOIN role_permission_grants pg
		  ON pg.root_tenant_id=ra.root_tenant_id
		 AND pg.organization_id=ra.organization_id
		 AND pg.role_assignment_id=ra.id
		WHERE m.root_tenant_id=$1 AND m.user_id=$2 AND m.organization_id=$3
		  AND m.id=$4 AND m.version=$5
		  AND m.status='active' AND (m.expires_at IS NULL OR m.expires_at > NOW())
		  AND o.status='active' AND o.deleted_at IS NULL
		  AND u.status=1 AND u.deleted_at IS NULL
		  AND ra.status='active'
		  AND pg.permission_code=$6
		  AND NOT EXISTS (
			SELECT 1 FROM organization_closure c
			JOIN organizations ancestor
			  ON ancestor.root_tenant_id=c.root_tenant_id AND ancestor.id=c.ancestor_id
			WHERE c.root_tenant_id=m.root_tenant_id AND c.descendant_id=m.organization_id
			  AND (ancestor.status<>'active' OR ancestor.deleted_at IS NOT NULL)
		  )
		ORDER BY pg.id
	`, actor.RootTenantID, actor.UserID, actor.OrganizationID, actor.MembershipID, actor.MembershipVersion, permissionCode)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	grants := make([]model.PermissionGrant, 0)
	for rows.Next() {
		var grant model.PermissionGrant
		if err := rows.Scan(&grant.ID, &grant.RoleAssignmentID, &grant.RoleCode, &grant.PermissionCode, &grant.Scope, &grant.ScopeDefinition); err != nil {
			return nil, err
		}
		grants = append(grants, grant)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return grants, nil
}

func (r *AuthorizationRepository) OrganizationCoveredByGrant(ctx context.Context, actor model.ActorContext, grant model.PermissionGrant, targetOrganizationID int64) (bool, error) {
	var covered bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM organizations target
			WHERE target.root_tenant_id=$1 AND target.id=$2
			  AND target.status='active' AND target.deleted_at IS NULL
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
				FROM organization_memberships m
				JOIN organizations active_org
				  ON active_org.root_tenant_id=m.root_tenant_id AND active_org.id=m.organization_id
				JOIN users actor_user ON actor_user.id=m.user_id
				JOIN membership_role_assignments ra
				  ON ra.root_tenant_id=m.root_tenant_id AND ra.organization_id=m.organization_id
				 AND ra.membership_id=m.id
				JOIN role_permission_grants pg
				  ON pg.root_tenant_id=ra.root_tenant_id AND pg.organization_id=ra.organization_id
				 AND pg.role_assignment_id=ra.id
				WHERE m.root_tenant_id=$1 AND m.organization_id=$3 AND m.user_id=$5
				  AND m.id=$6 AND m.version=$7 AND m.status='active'
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
				  AND ra.id=$9 AND ra.status='active'
				  AND pg.id=$8 AND pg.permission_code=$4
				  AND CASE pg.data_scope
					WHEN 'organization' THEN target.id=m.organization_id
					WHEN 'organization_and_descendants' THEN EXISTS (
						SELECT 1 FROM organization_closure c
						WHERE c.root_tenant_id=m.root_tenant_id
						  AND c.ancestor_id=m.organization_id AND c.descendant_id=target.id
					)
					WHEN 'assigned_resources' THEN EXISTS (
						SELECT 1 FROM authorization_resources ar
						JOIN resource_grants rg
						  ON rg.root_tenant_id=ar.root_tenant_id AND rg.organization_id=ar.organization_id
						 AND rg.resource_type=ar.resource_type AND rg.resource_id=ar.resource_id
						WHERE ar.root_tenant_id=m.root_tenant_id AND ar.resource_type='organization'
						  AND ar.resource_id=target.id::TEXT AND ar.status='active'
						  AND rg.status='active' AND rg.valid_from<=NOW()
						  AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
						  AND split_part($4,':',2)=ANY(rg.permissions)
						  AND (rg.subject_organization_id=m.organization_id
						       OR (rg.subject_user_id=m.user_id AND rg.subject_membership_id=m.id))
					)
					WHEN 'explicit_resources' THEN EXISTS (
						SELECT 1 FROM resource_grants rg
						WHERE rg.root_tenant_id=m.root_tenant_id AND rg.resource_type='organization'
						  AND rg.resource_id=target.id::TEXT AND rg.status='active'
						  AND rg.valid_from<=NOW() AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
						  AND split_part($4,':',2)=ANY(rg.permissions)
						  AND (rg.subject_organization_id=m.organization_id
						       OR (rg.subject_user_id=m.user_id AND rg.subject_membership_id=m.id))
					)
					ELSE FALSE
				  END
				  AND CASE
					WHEN NOT (pg.scope_definition ? 'organization_ids') THEN TRUE
					WHEN jsonb_typeof(pg.scope_definition->'organization_ids') <> 'array' THEN FALSE
					ELSE EXISTS (
						SELECT 1 FROM jsonb_array_elements_text(pg.scope_definition->'organization_ids') scoped(value)
						WHERE scoped.value=target.id::TEXT
						  AND EXISTS (
							SELECT 1 FROM organization_closure scoped_closure
							WHERE scoped_closure.root_tenant_id=m.root_tenant_id
							  AND scoped_closure.ancestor_id=m.organization_id
							  AND scoped_closure.descendant_id=target.id
						  )
					)
				  END
			  )
		)
	`, actor.RootTenantID, targetOrganizationID, actor.OrganizationID, grant.PermissionCode,
		actor.UserID, actor.MembershipID, actor.MembershipVersion, grant.ID, grant.RoleAssignmentID).Scan(&covered)
	return covered, err
}
