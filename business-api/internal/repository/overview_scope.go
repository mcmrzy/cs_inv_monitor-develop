package repository

import (
	"context"
	"fmt"
	"strings"

	"inv-api-server/internal/model"
)

func IsSyntheticOverviewActor(actor model.ActorContext) bool {
	return actor.Valid() && actor.RootTenantID == actor.UserID &&
		actor.OrganizationID == actor.UserID && actor.MembershipID == actor.UserID && actor.MembershipVersion == 1
}

// A synthetic session cannot replace any real membership, including a revoked one.
const syntheticOverviewAdminSQL = `EXISTS (
	SELECT 1 FROM users u WHERE u.id=@2 AND u.status=1 AND u.deleted_at IS NULL AND u.is_system_admin
	AND NOT EXISTS (SELECT 1 FROM organization_memberships m WHERE m.user_id=u.id)
)`

func (r *AuthorizationRepository) ValidateSyntheticOverviewAdmin(ctx context.Context, actor model.ActorContext) (bool, error) {
	if !IsSyntheticOverviewActor(actor) {
		return false, nil
	}
	var allowed bool
	// This query uses only the user parameter; the final scope filter also rechecks it.
	err := r.db.QueryRow(ctx, "SELECT "+strings.ReplaceAll(syntheticOverviewAdminSQL, "@2", "$1"), actor.UserID).Scan(&allowed)
	return allowed, err
}

// OverviewScopeFilter rechecks the selected membership and grant pair at query
// time, including on a long-lived SSE connection. Registered resource ownership
// is authoritative; legacy assets without a registration use owner memberships.
func OverviewScopeFilter(plan model.ScopePlan, systemAdmin bool, alias string, offset int) (string, []any) {
	if !plan.Actor.Valid() || offset < 1 || plan.DenyReason != "" ||
		(plan.ResourceType != "device" && plan.ResourceType != "station") ||
		(alias != "d" && alias != "s") || (!systemAdmin && len(plan.Grants) == 0) {
		return "FALSE", nil
	}
	id := alias + ".sn"
	if plan.ResourceType == "station" {
		id = alias + ".id::text"
	}
	grantIDs := make([]int64, 0, len(plan.Grants))
	for _, grant := range plan.Grants {
		if grant.PermissionCode == plan.PermissionCode && grant.Scope.Valid() {
			grantIDs = append(grantIDs, grant.ID)
		}
	}
	a := plan.Actor
	args := []any{a.RootTenantID, a.UserID, a.OrganizationID, a.MembershipID, a.MembershipVersion}
	active := `EXISTS (
		SELECT 1 FROM organization_memberships actor_m
		JOIN organizations actor_o ON actor_o.root_tenant_id=actor_m.root_tenant_id AND actor_o.id=actor_m.organization_id
		JOIN users actor_u ON actor_u.id=actor_m.user_id
		WHERE actor_m.root_tenant_id=@1 AND actor_m.user_id=@2 AND actor_m.organization_id=@3
		  AND actor_m.id=@4 AND actor_m.version=@5 AND actor_m.status='active'
		  AND (actor_m.expires_at IS NULL OR actor_m.expires_at>NOW())
		  AND actor_o.status='active' AND actor_o.deleted_at IS NULL
		  AND actor_u.status=1 AND actor_u.deleted_at IS NULL
		  AND NOT EXISTS (
			SELECT 1 FROM organization_closure path
			JOIN organizations ancestor ON ancestor.root_tenant_id=path.root_tenant_id AND ancestor.id=path.ancestor_id
			WHERE path.root_tenant_id=actor_m.root_tenant_id AND path.descendant_id=actor_m.organization_id
			  AND (ancestor.status<>'active' OR ancestor.deleted_at IS NOT NULL))
		  AND `
	if systemAdmin {
		filter := active + "actor_u.is_system_admin)"
		if IsSyntheticOverviewActor(a) {
			filter = "(" + filter + " OR " + syntheticOverviewAdminSQL + ")"
		}
		return overviewPlaceholders(filter, offset), args
	}
	if len(grantIDs) == 0 {
		return "FALSE", nil
	}
	args = append(args, plan.PermissionCode, grantIDs, plan.ResourceType)
	// The owner projection is constrained to this tenant before any scope applies.
	owners := fmt.Sprintf(`(
		SELECT ar.organization_id FROM authorization_resources ar
		WHERE ar.resource_type=@8 AND ar.resource_id=%s AND ar.root_tenant_id=@1 AND ar.status='active'
		UNION
		SELECT owner_m.organization_id FROM organization_memberships owner_m
		WHERE owner_m.root_tenant_id=@1 AND owner_m.user_id=%s.user_id AND owner_m.status='active'
		  AND (owner_m.expires_at IS NULL OR owner_m.expires_at>NOW())
		  AND NOT EXISTS (SELECT 1 FROM authorization_resources registered
			WHERE registered.resource_type=@8 AND registered.resource_id=%s)
	)`, id, alias, id)
	filter := active + fmt.Sprintf(`EXISTS (
		SELECT 1 FROM membership_role_assignments ra
		JOIN role_permission_grants pg ON pg.root_tenant_id=ra.root_tenant_id
		  AND pg.organization_id=ra.organization_id AND pg.role_assignment_id=ra.id
		JOIN %s owner ON TRUE
		JOIN organizations owner_o ON owner_o.root_tenant_id=actor_m.root_tenant_id AND owner_o.id=owner.organization_id
		WHERE ra.root_tenant_id=actor_m.root_tenant_id AND ra.organization_id=actor_m.organization_id
		  AND ra.membership_id=actor_m.id AND ra.status='active'
		  AND pg.permission_code=@6 AND pg.id=ANY(@7)
		  AND owner_o.status='active' AND owner_o.deleted_at IS NULL
		  AND NOT EXISTS (
			SELECT 1 FROM organization_closure path
			JOIN organizations ancestor ON ancestor.root_tenant_id=path.root_tenant_id AND ancestor.id=path.ancestor_id
			WHERE path.root_tenant_id=actor_m.root_tenant_id AND path.descendant_id=owner.organization_id
			  AND (ancestor.status<>'active' OR ancestor.deleted_at IS NOT NULL))
		  AND CASE
			WHEN pg.data_scope='self' THEN %s.user_id=actor_m.user_id AND owner.organization_id=actor_m.organization_id
			WHEN pg.data_scope='organization' THEN owner.organization_id=actor_m.organization_id
			WHEN pg.data_scope='organization_and_descendants' THEN EXISTS (
				SELECT 1 FROM organization_closure oc WHERE oc.root_tenant_id=actor_m.root_tenant_id
				  AND oc.ancestor_id=actor_m.organization_id AND oc.descendant_id=owner.organization_id)
			WHEN pg.data_scope IN ('assigned_resources', 'explicit_resources') THEN EXISTS (
				SELECT 1 FROM resource_grants rg WHERE rg.root_tenant_id=actor_m.root_tenant_id
				  AND rg.organization_id=owner.organization_id AND rg.resource_type=@8 AND rg.resource_id=%s
				  AND rg.status='active' AND rg.valid_from<=NOW()
				  AND (rg.expires_at IS NULL OR rg.expires_at>NOW())
				  AND split_part(@6,':',2)=ANY(rg.permissions)
				  AND (rg.subject_organization_id=actor_m.organization_id
				    OR (rg.subject_user_id=actor_m.user_id AND rg.subject_membership_id=actor_m.id)))
			ELSE FALSE
		  END
		  AND CASE
			WHEN NOT (pg.scope_definition ? 'organization_ids') THEN TRUE
			WHEN jsonb_typeof(pg.scope_definition->'organization_ids')<>'array' THEN FALSE
			ELSE EXISTS (
				SELECT 1 FROM jsonb_array_elements_text(pg.scope_definition->'organization_ids') scoped(value)
				WHERE scoped.value=owner.organization_id::text AND EXISTS (
					SELECT 1 FROM organization_closure oc WHERE oc.root_tenant_id=actor_m.root_tenant_id
					  AND oc.ancestor_id=actor_m.organization_id AND oc.descendant_id=owner.organization_id))
		  END
	))`, owners, alias, id)
	return overviewPlaceholders(filter, offset), args
}

func overviewPlaceholders(sql string, offset int) string {
	for i := 8; i >= 1; i-- {
		sql = strings.ReplaceAll(sql, fmt.Sprintf("@%d", i), fmt.Sprintf("$%d", offset+i-1))
	}
	return sql
}

// ListOverview uses the same filter for totals and rows. pageSize=0 returns the
// complete collection for summary aggregation without a fixed station cap.
func (r *StationRepository) ListOverview(ctx context.Context, plan model.ScopePlan, systemAdmin bool, page, pageSize int) ([]*model.Station, int64, error) {
	filter, args := OverviewScopeFilter(plan, systemAdmin, "s", 1)
	where := " FROM stations s WHERE s.deleted_at IS NULL AND " + filter
	var total int64
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*)"+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	query := "SELECT " + stationListSelectColumns + where + " ORDER BY sort_order, created_at DESC, id"
	if pageSize > 0 {
		query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
		args = append(args, pageSize, (page-1)*pageSize)
	}
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	stations := make([]*model.Station, 0)
	for rows.Next() {
		var st model.Station
		if err := rows.Scan(&st.ID, &st.UserID, &st.Name, &st.Country, &st.Province, &st.City, &st.District,
			&st.Address, &st.Capacity, &st.PanelCount, &st.Latitude, &st.Longitude, &st.Timezone,
			&st.Status, &st.CardImageURL, &st.CreatedAt, &st.UpdatedAt); err != nil {
			return nil, 0, err
		}
		stations = append(stations, &st)
	}
	return stations, total, rows.Err()
}
