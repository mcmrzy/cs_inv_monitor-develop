package migration

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const reconcileDiffType = "organization_backfill_reconcile"

type closureFact struct {
	AncestorID int64 `json:"ancestor_id"`
	Depth      int   `json:"depth"`
}

type roleFact struct {
	RoleCode string `json:"role_code"`
	Status   string `json:"status"`
}

type quotaFact struct {
	ResourceType  string `json:"resource_type"`
	Limit         int64  `json:"limit"`
	InheritedFrom *int64 `json:"inherited_from,omitempty"`
}

type organizationBackfillState struct {
	Exists             bool          `json:"exists"`
	OrganizationID     int64         `json:"organization_id"`
	RootTenantID       int64         `json:"root_tenant_id"`
	ParentID           *int64        `json:"parent_id,omitempty"`
	OrganizationType   string        `json:"organization_type"`
	OrganizationCode   string        `json:"organization_code"`
	OrganizationName   string        `json:"organization_name"`
	OrganizationStatus string        `json:"organization_status"`
	MembershipUserID   int64         `json:"membership_user_id"`
	MembershipRootID   int64         `json:"membership_root_id"`
	MembershipOrgID    int64         `json:"membership_organization_id"`
	MembershipStatus   string        `json:"membership_status"`
	Roles              []roleFact    `json:"roles"`
	Quotas             []quotaFact   `json:"quotas"`
	Closure            []closureFact `json:"closure"`
	EntityTargetID     int64         `json:"entity_target_id"`
	MappingDigest      string        `json:"mapping_digest"`
	SourceFingerprint  string        `json:"source_fingerprint"`
}

func ReconcileChannelBackfill(ctx context.Context, db *pgxpool.Pool, runID uuid.UUID) (int64, error) {
	var mappingDigest string
	if err := db.QueryRow(ctx, `SELECT mapping_digest FROM channel_migration_runs WHERE id=$1`, runID).Scan(&mappingDigest); err != nil {
		return 0, fmt.Errorf("load run mapping digest: %w", err)
	}
	rows, err := db.Query(ctx, `
		SELECT expected FROM channel_migration_items
		WHERE run_id=$1 AND source_table='users'
		ORDER BY ordinal
	`, runID)
	if err != nil {
		return 0, fmt.Errorf("load expected backfill states: %w", err)
	}
	var operations []BackfillOperation
	for rows.Next() {
		var expectedJSON []byte
		if err := rows.Scan(&expectedJSON); err != nil {
			rows.Close()
			return 0, err
		}
		var operation BackfillOperation
		if err := json.Unmarshal(expectedJSON, &operation); err != nil {
			rows.Close()
			return 0, fmt.Errorf("decode expected operation: %w", err)
		}
		operations = append(operations, operation)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	opByID := make(map[int64]BackfillOperation, len(operations))
	for _, operation := range operations {
		opByID[operation.OrganizationID] = operation
	}

	tx, err := db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `DELETE FROM channel_migration_shadow_diffs WHERE run_id=$1 AND diff_type=$2`, runID, reconcileDiffType); err != nil {
		return 0, err
	}
	var diffCount int64
	for _, operation := range operations {
		expected := expectedBackfillState(operation, opByID, mappingDigest)
		actual, err := loadActualBackfillState(ctx, tx, operation.SourceUserID)
		if err != nil {
			return 0, err
		}
		expectedFingerprint, _ := fingerprintJSON(expected)
		actualFingerprint, _ := fingerprintJSON(actual)
		if expectedFingerprint == actualFingerprint {
			continue
		}
		expectedJSON, _ := json.Marshal(expected)
		actualJSON, _ := json.Marshal(actual)
		diffFingerprint, _ := fingerprintJSON(map[string]string{"expected": expectedFingerprint, "actual": actualFingerprint})
		if _, err := tx.Exec(ctx, `
			INSERT INTO channel_migration_shadow_diffs(
				run_id,diff_type,source_table,source_key,reason_code,
				expected,actual,details,diff_fingerprint
			) VALUES($1,$2,'users',$3,'TARGET_STATE_MISMATCH',$4,$5,'{}'::jsonb,$6)
		`, runID, reconcileDiffType, fmt.Sprint(operation.SourceUserID), expectedJSON, actualJSON, diffFingerprint); err != nil {
			return 0, fmt.Errorf("persist organization reconciliation diff: %w", err)
		}
		diffCount++
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return diffCount, nil
}

func expectedBackfillState(operation BackfillOperation, operations map[int64]BackfillOperation, mappingDigest string) organizationBackfillState {
	membershipStatus := "active"
	if operation.Status != "active" {
		membershipStatus = "disabled"
	}
	roleStatus := membershipStatusForRole(membershipStatus)
	roles := make([]roleFact, 0, len(operation.RoleCodes))
	for _, roleCode := range operation.RoleCodes {
		roles = append(roles, roleFact{RoleCode: roleCode, Status: roleStatus})
	}
	quotas := make([]quotaFact, 0, len(operation.QuotaDefaults))
	for resourceType, limit := range operation.QuotaDefaults {
		var inheritedFrom *int64
		if operation.OrganizationType != "manufacturer" {
			ancestorID := operation.ParentID
			for ancestorID != nil {
				ancestor := operations[*ancestorID]
				if _, exists := ancestor.QuotaDefaults[resourceType]; exists {
					value := ancestor.OrganizationID
					inheritedFrom = &value
					break
				}
				ancestorID = ancestor.ParentID
			}
		}
		quotas = append(quotas, quotaFact{ResourceType: resourceType, Limit: limit, InheritedFrom: inheritedFrom})
	}
	sort.Slice(quotas, func(i, j int) bool { return quotas[i].ResourceType < quotas[j].ResourceType })
	closure := []closureFact{{AncestorID: operation.OrganizationID, Depth: 0}}
	depth := 1
	ancestorID := operation.ParentID
	for ancestorID != nil {
		closure = append(closure, closureFact{AncestorID: *ancestorID, Depth: depth})
		ancestor := operations[*ancestorID]
		ancestorID = ancestor.ParentID
		depth++
	}
	sort.Slice(closure, func(i, j int) bool { return closure[i].AncestorID < closure[j].AncestorID })
	return organizationBackfillState{
		Exists: true, OrganizationID: operation.OrganizationID, RootTenantID: operation.RootTenantID,
		ParentID: operation.ParentID, OrganizationType: operation.OrganizationType,
		OrganizationCode: operation.OrganizationCode, OrganizationName: operation.OrganizationName,
		OrganizationStatus: operation.Status, MembershipUserID: operation.SourceUserID,
		MembershipRootID: operation.RootTenantID, MembershipOrgID: operation.OrganizationID,
		MembershipStatus: membershipStatus, Roles: roles, Quotas: quotas, Closure: closure,
		EntityTargetID: operation.OrganizationID, MappingDigest: mappingDigest,
		SourceFingerprint: operation.SourceFingerprint,
	}
}

func loadActualBackfillState(ctx context.Context, tx pgx.Tx, sourceUserID int64) (organizationBackfillState, error) {
	state := organizationBackfillState{
		Roles: []roleFact{}, Quotas: []quotaFact{}, Closure: []closureFact{},
	}
	err := tx.QueryRow(ctx, `
		SELECT o.id,o.root_tenant_id,o.parent_id,o.org_type,o.code,o.name,o.status,
		       m.user_id,m.root_tenant_id,m.organization_id,m.status
		FROM channel_migration_entity_map em
		JOIN organizations o ON o.id=em.target_id
		JOIN organization_memberships m ON m.id=$1
		WHERE em.source_table='users' AND em.source_key=$2 AND em.target_type='organization'
	`, sourceUserID, fmt.Sprint(sourceUserID)).Scan(
		&state.OrganizationID, &state.RootTenantID, &state.ParentID, &state.OrganizationType,
		&state.OrganizationCode, &state.OrganizationName, &state.OrganizationStatus,
		&state.MembershipUserID, &state.MembershipRootID, &state.MembershipOrgID, &state.MembershipStatus,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return state, nil
	}
	if err != nil {
		return state, fmt.Errorf("load actual organization state for user %d: %w", sourceUserID, err)
	}
	state.Exists = true
	roleRows, err := tx.Query(ctx, `SELECT role_code,status FROM membership_role_assignments WHERE membership_id=$1 ORDER BY role_code,status`, sourceUserID)
	if err != nil {
		return state, err
	}
	for roleRows.Next() {
		var fact roleFact
		if err := roleRows.Scan(&fact.RoleCode, &fact.Status); err != nil {
			roleRows.Close()
			return state, err
		}
		state.Roles = append(state.Roles, fact)
	}
	roleRows.Close()
	quotaRows, err := tx.Query(ctx, `
		SELECT resource_type,quota_limit,inherited_from_organization_id
		FROM organization_quotas WHERE root_tenant_id=$1 AND organization_id=$2 ORDER BY resource_type
	`, state.RootTenantID, state.OrganizationID)
	if err != nil {
		return state, err
	}
	for quotaRows.Next() {
		var fact quotaFact
		if err := quotaRows.Scan(&fact.ResourceType, &fact.Limit, &fact.InheritedFrom); err != nil {
			quotaRows.Close()
			return state, err
		}
		state.Quotas = append(state.Quotas, fact)
	}
	quotaRows.Close()
	closureRows, err := tx.Query(ctx, `
		SELECT ancestor_id,depth FROM organization_closure
		WHERE root_tenant_id=$1 AND descendant_id=$2 ORDER BY ancestor_id
	`, state.RootTenantID, state.OrganizationID)
	if err != nil {
		return state, err
	}
	for closureRows.Next() {
		var fact closureFact
		if err := closureRows.Scan(&fact.AncestorID, &fact.Depth); err != nil {
			closureRows.Close()
			return state, err
		}
		state.Closure = append(state.Closure, fact)
	}
	closureRows.Close()
	if err := tx.QueryRow(ctx, `
		SELECT target_id,mapping_digest,source_fingerprint
		FROM channel_migration_entity_map
		WHERE source_table='users' AND source_key=$1 AND target_type='organization'
	`, fmt.Sprint(sourceUserID)).Scan(&state.EntityTargetID, &state.MappingDigest, &state.SourceFingerprint); err != nil {
		return state, err
	}
	return state, nil
}
