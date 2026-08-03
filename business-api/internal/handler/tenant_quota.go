package handler

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ensureTenantDeviceCapacity checks organization_quotas for the user's organization
// to enforce device quota limits. Replaces the old users.device_limit + parent_id
// recursive query with organization-based quota lookups.
func ensureTenantDeviceCapacity(ctx context.Context, db *pgxpool.Pool, userID int64) error {
	var limit *int
	var used int
	err := db.QueryRow(ctx, `
		WITH RECURSIVE user_org AS (
			SELECT om.root_tenant_id, om.organization_id
			FROM organization_memberships om
			WHERE om.user_id = $1 AND om.status = 'active'
			LIMIT 1
		), org_tree AS (
			SELECT o.id
			FROM organizations o, user_org uo
			WHERE o.root_tenant_id = uo.root_tenant_id AND o.deleted_at IS NULL
			  AND o.id = uo.organization_id
			UNION ALL
			SELECT child.id
			FROM organizations child
			JOIN org_tree parent ON child.parent_id = parent.id
			WHERE child.deleted_at IS NULL
		), quota AS (
			SELECT q.quota_limit
			FROM organization_quotas q, user_org uo
			WHERE q.root_tenant_id = uo.root_tenant_id
			  AND q.organization_id = uo.organization_id
			  AND q.resource_type = 'claimed_devices'
			LIMIT 1
		)
		SELECT
			(SELECT quota_limit FROM quota),
			(SELECT COUNT(*) FROM devices d
			 JOIN organization_memberships om ON om.user_id = d.user_id AND om.status = 'active'
			 WHERE om.organization_id IN (SELECT id FROM org_tree)
			   AND d.deleted_at IS NULL)
	`, userID).Scan(&limit, &used)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if limit != nil && used >= *limit {
		return fmt.Errorf("organization device quota reached (%d/%d)", used, *limit)
	}
	return nil
}

// ensureTenantUserCapacity checks organization_quotas for the user's organization
// to enforce member quota limits. Replaces the old users.user_limit + parent_id
// recursive query with organization-based quota lookups.
func ensureTenantUserCapacity(ctx context.Context, db *pgxpool.Pool, parentID, movingUserID int64) error {
	var limit *int
	var used int
	var alreadyMember bool
	err := db.QueryRow(ctx, `
		WITH RECURSIVE user_org AS (
			SELECT om.root_tenant_id, om.organization_id
			FROM organization_memberships om
			WHERE om.user_id = $1 AND om.status = 'active'
			LIMIT 1
		), org_tree AS (
			SELECT o.id
			FROM organizations o, user_org uo
			WHERE o.root_tenant_id = uo.root_tenant_id AND o.deleted_at IS NULL
			  AND o.id = uo.organization_id
			UNION ALL
			SELECT child.id
			FROM organizations child
			JOIN org_tree parent ON child.parent_id = parent.id
			WHERE child.deleted_at IS NULL
		), quota AS (
			SELECT q.quota_limit
			FROM organization_quotas q, user_org uo
			WHERE q.root_tenant_id = uo.root_tenant_id
			  AND q.organization_id = uo.organization_id
			  AND q.resource_type = 'members'
			LIMIT 1
		)
		SELECT
			(SELECT quota_limit FROM quota),
			(SELECT COUNT(*) FROM organization_memberships om
			 WHERE om.organization_id IN (SELECT id FROM org_tree)
			   AND om.status = 'active'),
			EXISTS(SELECT 1 FROM organization_memberships om2
			 WHERE om2.organization_id IN (SELECT id FROM org_tree)
			   AND om2.user_id = $2 AND om2.status = 'active')
	`, parentID, movingUserID).Scan(&limit, &used, &alreadyMember)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if limit != nil && !alreadyMember && used >= *limit {
		return fmt.Errorf("organization member quota reached (%d/%d)", used, *limit)
	}
	return nil
}
