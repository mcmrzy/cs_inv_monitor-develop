package migration

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresOrganizationBackfillStore struct {
	db            *pgxpool.Pool
	runID         uuid.UUID
	workerID      string
	mappingDigest string
	sourceDigest  string
}

func NewPostgresOrganizationBackfillStore(db *pgxpool.Pool, runID uuid.UUID, workerID string) *PostgresOrganizationBackfillStore {
	if runID == uuid.Nil {
		runID = uuid.New()
	}
	if workerID == "" {
		workerID = "channel-migrate-single-worker"
	}
	return &PostgresOrganizationBackfillStore{db: db, runID: runID, workerID: workerID}
}

func LoadLegacyChannelSnapshot(ctx context.Context, db *pgxpool.Pool) ([]LegacyUser, []LegacyOwnershipFact, error) {
	rows, err := db.Query(ctx, `
		SELECT id, phone, COALESCE(email,''), COALESCE(nickname,''), role, parent_id,
		       status, deleted_at IS NOT NULL
		FROM users
		ORDER BY id
	`)
	if err != nil {
		return nil, nil, fmt.Errorf("load legacy users: %w", err)
	}
	defer rows.Close()
	var users []LegacyUser
	for rows.Next() {
		var user LegacyUser
		if err := rows.Scan(&user.ID, &user.Phone, &user.Email, &user.Nickname, &user.Role, &user.ParentID, &user.Status, &user.Deleted); err != nil {
			return nil, nil, fmt.Errorf("scan legacy user: %w", err)
		}
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, fmt.Errorf("iterate legacy users: %w", err)
	}

	ownerRows, err := db.Query(ctx, `
		SELECT 'device'::TEXT, d.sn::TEXT, d.user_id
		FROM devices d
		JOIN users du ON du.id=d.user_id AND du.deleted_at IS NULL
		WHERE d.deleted_at IS NULL AND d.user_id > 0
		UNION ALL
		SELECT 'device'::TEXT, d.sn::TEXT, s.user_id
		FROM devices d
		JOIN stations s ON s.id=d.station_id AND s.deleted_at IS NULL
		JOIN users su ON su.id=s.user_id AND su.deleted_at IS NULL
		WHERE d.deleted_at IS NULL AND s.user_id > 0 AND s.user_id <> d.user_id
		ORDER BY 1,2,3
	`)
	if err != nil {
		return nil, nil, fmt.Errorf("load legacy ownership facts: %w", err)
	}
	defer ownerRows.Close()
	var ownership []LegacyOwnershipFact
	for ownerRows.Next() {
		var fact LegacyOwnershipFact
		if err := ownerRows.Scan(&fact.ResourceType, &fact.ResourceKey, &fact.OwnerUserID); err != nil {
			return nil, nil, fmt.Errorf("scan legacy ownership fact: %w", err)
		}
		ownership = append(ownership, fact)
	}
	if err := ownerRows.Err(); err != nil {
		return nil, nil, fmt.Errorf("iterate legacy ownership facts: %w", err)
	}
	return users, ownership, nil
}

func RequireChannelBackfillSchema(ctx context.Context, db *pgxpool.Pool) error {
	var missing []string
	for _, table := range []string{
		"organizations", "channel_migration_runs", "channel_migration_checkpoints",
		"channel_migration_items", "channel_migration_entity_map", "channel_migration_shadow_diffs",
	} {
		var exists bool
		if err := db.QueryRow(ctx, `SELECT to_regclass('public.' || $1) IS NOT NULL`, table).Scan(&exists); err != nil {
			return fmt.Errorf("check required channel table %s: %w", table, err)
		}
		if !exists {
			missing = append(missing, table)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("channel backfill schema is incomplete; missing %v (apply migrations through 066)", missing)
	}
	return nil
}

func (s *PostgresOrganizationBackfillStore) Prepare(ctx context.Context, mappingDigest string, report PreflightReport, sourceWatermark int64) (uuid.UUID, error) {
	sourceDigest, err := fingerprintJSON(report)
	if err != nil {
		return uuid.Nil, fmt.Errorf("fingerprint channel preflight: %w", err)
	}
	s.mappingDigest = mappingDigest
	s.sourceDigest = sourceDigest
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return uuid.Nil, fmt.Errorf("begin channel preflight persistence: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := tx.QueryRow(ctx, `
		INSERT INTO channel_migration_runs(id,job_name,mapping_digest,source_digest,source_watermark,status,summary)
		VALUES($1,$2,$3,$4,$5,'prepared',$6)
		ON CONFLICT(job_name,mapping_digest,source_digest) DO UPDATE
		SET status=CASE
		        WHEN channel_migration_runs.status='failed' THEN 'prepared'
		        ELSE channel_migration_runs.status
		    END,
		    completed_at=CASE
		        WHEN channel_migration_runs.status='failed' THEN NULL
		        ELSE channel_migration_runs.completed_at
		    END,
		    updated_at=NOW()
		RETURNING id
	`, s.runID, organizationBackfillJob, mappingDigest, sourceDigest, sourceWatermark, summaryJSON(report)).Scan(&s.runID); err != nil {
		return uuid.Nil, fmt.Errorf("upsert channel migration run: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO channel_migration_checkpoints(run_id,job_name,partition_key,mapping_digest,next_ordinal)
		VALUES($1,$2,'organizations',$3,0)
		ON CONFLICT(run_id,partition_key) DO NOTHING
	`, s.runID, organizationBackfillJob, mappingDigest); err != nil {
		return uuid.Nil, fmt.Errorf("create organization checkpoint: %w", err)
	}

	for ordinal, operation := range report.Operations {
		expected, err := json.Marshal(operation)
		if err != nil {
			return uuid.Nil, fmt.Errorf("marshal expected operation: %w", err)
		}
		var parentKey *string
		if operation.ParentID != nil {
			value := fmt.Sprint(*operation.ParentID)
			parentKey = &value
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO channel_migration_items(
				run_id,source_table,source_key,source_user_id,ordinal,depth,parent_source_key,
				source_fingerprint,expected,status
			) VALUES($1,'users',$2,$3,$4,$5,$6,$7,$8,'pending')
			ON CONFLICT(run_id,source_table,source_key) DO UPDATE
			SET ordinal=EXCLUDED.ordinal, depth=EXCLUDED.depth,
			    parent_source_key=EXCLUDED.parent_source_key,
			    source_fingerprint=EXCLUDED.source_fingerprint,expected=EXCLUDED.expected,
			    updated_at=NOW()
			WHERE channel_migration_items.status IN ('pending','failed')
		`, s.runID, fmt.Sprint(operation.SourceUserID), operation.SourceUserID, ordinal, operation.Depth, parentKey, operation.SourceFingerprint, expected); err != nil {
			return uuid.Nil, fmt.Errorf("upsert channel migration item for user %d: %w", operation.SourceUserID, err)
		}
	}

	allQuarantine := append(append([]QuarantineEntry(nil), report.Quarantine...), report.OwnershipQuarantine...)
	sort.Slice(allQuarantine, func(i, j int) bool {
		if allQuarantine[i].SourceTable != allQuarantine[j].SourceTable {
			return allQuarantine[i].SourceTable < allQuarantine[j].SourceTable
		}
		if allQuarantine[i].SourceKey != allQuarantine[j].SourceKey {
			return allQuarantine[i].SourceKey < allQuarantine[j].SourceKey
		}
		return allQuarantine[i].ReasonCode < allQuarantine[j].ReasonCode
	})
	for _, entry := range allQuarantine {
		payload := []byte("{}")
		if entry.Payload != nil {
			payload, _ = json.Marshal(entry.Payload)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO channel_migration_quarantine(
				source_table,source_key,reason_code,reason_detail,payload,
				first_run_id,last_seen_run_id,occurrence_count
			) VALUES($1,$2,$3,$4,$5,$6,$6,1)
			ON CONFLICT(source_table,source_key,reason_code) DO UPDATE
			SET reason_detail=EXCLUDED.reason_detail,
			    payload=EXCLUDED.payload,
			    last_seen_run_id=EXCLUDED.last_seen_run_id,
			    occurrence_count=channel_migration_quarantine.occurrence_count+
			        CASE WHEN channel_migration_quarantine.last_seen_run_id IS DISTINCT FROM EXCLUDED.last_seen_run_id THEN 1 ELSE 0 END
		`, entry.SourceTable, entry.SourceKey, entry.ReasonCode, entry.Detail, payload, s.runID); err != nil {
			return uuid.Nil, fmt.Errorf("upsert quarantine %s/%s/%s: %w", entry.SourceTable, entry.SourceKey, entry.ReasonCode, err)
		}
		fingerprint, _ := fingerprintJSON(entry)
		if _, err := tx.Exec(ctx, `
			INSERT INTO channel_migration_shadow_diffs(
				run_id,diff_type,source_table,source_key,reason_code,details,diff_fingerprint
			) VALUES($1,'preflight',$2,$3,$4,$5,$6)
			ON CONFLICT(run_id,diff_type,source_table,source_key,reason_code) DO UPDATE
			SET details=EXCLUDED.details,diff_fingerprint=EXCLUDED.diff_fingerprint
		`, s.runID, entry.SourceTable, entry.SourceKey, entry.ReasonCode, payload, fingerprint); err != nil {
			return uuid.Nil, fmt.Errorf("upsert preflight shadow diff: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return uuid.Nil, fmt.Errorf("commit channel preflight persistence: %w", err)
	}
	return s.runID, nil
}

func (s *PostgresOrganizationBackfillStore) LoadCheckpoint(ctx context.Context, jobName, mappingDigest string) (int, error) {
	var checkpoint int64
	err := s.db.QueryRow(ctx, `
		SELECT c.next_ordinal
		FROM channel_migration_checkpoints c
		JOIN channel_migration_runs r ON r.id=c.run_id
		WHERE c.run_id=$1 AND c.job_name=$2 AND c.mapping_digest=$3
	`, s.runID, jobName, mappingDigest).Scan(&checkpoint)
	if err != nil {
		return 0, err
	}
	return int(checkpoint), nil
}

func (s *PostgresOrganizationBackfillStore) ApplyBatch(ctx context.Context, jobName, mappingDigest string, after int, operations []BackfillOperation) (int, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return after, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='60s'`); err != nil {
		return after, err
	}
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))`, jobName, mappingDigest); err != nil {
		return after, fmt.Errorf("lock channel backfill: %w", err)
	}
	if _, err := tx.Exec(ctx, `LOCK TABLE users IN SHARE MODE`); err != nil {
		return after, fmt.Errorf("freeze legacy users for batch verification: %w", err)
	}
	var expectedWatermark, actualWatermark int64
	if err := tx.QueryRow(ctx, `SELECT source_watermark FROM channel_migration_runs WHERE id=$1 FOR UPDATE`, s.runID).Scan(&expectedWatermark); err != nil {
		return after, fmt.Errorf("load source watermark: %w", err)
	}
	if err := tx.QueryRow(ctx, `SELECT COALESCE(MAX(id),0) FROM users`).Scan(&actualWatermark); err != nil {
		return after, fmt.Errorf("read source watermark: %w", err)
	}
	if actualWatermark != expectedWatermark {
		return after, fmt.Errorf("legacy users changed after preflight: watermark %d, expected %d", actualWatermark, expectedWatermark)
	}

	end := after + len(operations)
	rows, err := tx.Query(ctx, `
		SELECT source_user_id
		FROM channel_migration_items
		WHERE run_id=$1 AND ordinal >= $2 AND ordinal < $3 AND status IN ('pending','failed')
		ORDER BY ordinal
		FOR UPDATE SKIP LOCKED
	`, s.runID, after, end)
	if err != nil {
		return after, fmt.Errorf("claim channel migration items: %w", err)
	}
	claimed := make(map[int64]struct{})
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return after, err
		}
		claimed[id] = struct{}{}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return after, err
	}
	if len(claimed) != len(operations) {
		return after, fmt.Errorf("non-contiguous work claim: got %d items, expected %d; checkpoint not advanced", len(claimed), len(operations))
	}

	ids := make([]int64, 0, len(operations))
	for _, operation := range operations {
		ids = append(ids, operation.SourceUserID)
		if _, ok := claimed[operation.SourceUserID]; !ok {
			return after, fmt.Errorf("claimed work does not contain source user %d", operation.SourceUserID)
		}
	}
	lockedRows, err := tx.Query(ctx, `
		SELECT id,phone,COALESCE(email,''),COALESCE(nickname,''),role,parent_id,status,deleted_at IS NOT NULL
		FROM users WHERE id=ANY($1) ORDER BY id FOR UPDATE SKIP LOCKED
	`, ids)
	if err != nil {
		return after, fmt.Errorf("lock legacy source users: %w", err)
	}
	lockedCount := 0
	currentFingerprints := make(map[int64]string, len(ids))
	for lockedRows.Next() {
		var user LegacyUser
		if err := lockedRows.Scan(&user.ID, &user.Phone, &user.Email, &user.Nickname, &user.Role, &user.ParentID, &user.Status, &user.Deleted); err != nil {
			lockedRows.Close()
			return after, fmt.Errorf("scan locked legacy user: %w", err)
		}
		fingerprint, err := fingerprintJSON(user)
		if err != nil {
			lockedRows.Close()
			return after, err
		}
		currentFingerprints[user.ID] = fingerprint
		lockedCount++
	}
	lockedRows.Close()
	if lockedCount != len(ids) {
		return after, fmt.Errorf("locked %d of %d source users; checkpoint not advanced", lockedCount, len(ids))
	}
	for _, operation := range operations {
		if currentFingerprints[operation.SourceUserID] != operation.SourceFingerprint {
			return after, fmt.Errorf("legacy user %d changed after preflight; checkpoint not advanced", operation.SourceUserID)
		}
	}
	if _, err := tx.Exec(ctx, `
		UPDATE channel_migration_items
		SET status='processing',attempt_count=attempt_count+1,lease_owner=$4,
		    lease_until=NOW()+INTERVAL '2 minutes',updated_at=NOW()
		WHERE run_id=$1 AND ordinal >= $2 AND ordinal < $3
	`, s.runID, after, end, s.workerID); err != nil {
		return after, fmt.Errorf("lease channel migration items: %w", err)
	}

	for _, operation := range operations {
		if err := applyOrganizationOperation(ctx, tx, mappingDigest, operation); err != nil {
			return after, fmt.Errorf("apply legacy user %d: %w", operation.SourceUserID, err)
		}
		if _, err := tx.Exec(ctx, `
			UPDATE channel_migration_items
			SET status='succeeded',target_type='organization',target_id=$2,
			    lease_owner=NULL,lease_until=NULL,last_error=NULL,updated_at=NOW()
			WHERE run_id=$1 AND source_table='users' AND source_key=$3
		`, s.runID, operation.OrganizationID, fmt.Sprint(operation.SourceUserID)); err != nil {
			return after, fmt.Errorf("complete migration item: %w", err)
		}
	}
	checkpointTag, err := tx.Exec(ctx, `
		UPDATE channel_migration_checkpoints
		SET next_ordinal=$4::BIGINT,counters=jsonb_build_object('applied',$4::BIGINT),version=version+1,updated_at=NOW()
		WHERE run_id=$1 AND job_name=$2 AND mapping_digest=$3 AND next_ordinal=$5::BIGINT
	`, s.runID, jobName, mappingDigest, end, after)
	if err != nil {
		return after, fmt.Errorf("advance organization checkpoint: %w", err)
	}
	if checkpointTag.RowsAffected() != 1 {
		return after, fmt.Errorf("stale organization checkpoint after %d: updated %d rows", after, checkpointTag.RowsAffected())
	}
	batchAudit, _ := json.Marshal(map[string]any{
		"run_id": s.runID, "worker_id": s.workerID, "mapping_digest": mappingDigest,
		"source_digest": s.sourceDigest, "ordinal_start": after, "ordinal_end": end, "succeeded": len(operations),
	})
	if _, err := tx.Exec(ctx, `
		INSERT INTO audit_logs(
			action,resource_type,resource_id,request_id,result,after_data,event_schema_version
		) VALUES('channel_backfill_batch','channel_migration_run',$1,$2,'success',$3,'1.0')
	`, s.runID.String(), fmt.Sprintf("channel-migrate:%s:%d", s.runID, after), batchAudit); err != nil {
		return after, fmt.Errorf("write immutable backfill batch audit: %w", err)
	}
	if _, err := tx.Exec(ctx, `UPDATE channel_migration_runs SET status='running',updated_at=NOW() WHERE id=$1`, s.runID); err != nil {
		return after, err
	}
	if err := tx.Commit(ctx); err != nil {
		return after, err
	}
	return end, nil
}

func applyOrganizationOperation(ctx context.Context, tx pgx.Tx, mappingDigest string, operation BackfillOperation) error {
	if _, err := tx.Exec(ctx, `
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status)
		VALUES($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT(id) DO NOTHING
	`, operation.OrganizationID, operation.RootTenantID, operation.ParentID, operation.OrganizationType,
		operation.OrganizationCode, operation.OrganizationName, operation.Status); err != nil {
		return fmt.Errorf("insert organization: %w", err)
	}
	var matches bool
	if err := tx.QueryRow(ctx, `
		SELECT root_tenant_id=$2 AND parent_id IS NOT DISTINCT FROM $3 AND org_type=$4 AND code=$5
		FROM organizations WHERE id=$1
	`, operation.OrganizationID, operation.RootTenantID, operation.ParentID, operation.OrganizationType, operation.OrganizationCode).Scan(&matches); err != nil {
		return fmt.Errorf("verify organization identity: %w", err)
	}
	if !matches {
		return fmt.Errorf("organization id %d is already mapped to a different identity", operation.OrganizationID)
	}
	membershipStatus := "active"
	if operation.Status != "active" {
		membershipStatus = "disabled"
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status)
		VALUES($1,$2,$3,$1,$4)
		ON CONFLICT(id) DO NOTHING
	`, operation.SourceUserID, operation.RootTenantID, operation.OrganizationID, membershipStatus); err != nil {
		return fmt.Errorf("insert organization membership: %w", err)
	}
	if err := tx.QueryRow(ctx, `
		SELECT root_tenant_id=$2 AND organization_id=$3 AND user_id=$1 AND status=$4
		FROM organization_memberships WHERE id=$1
	`, operation.SourceUserID, operation.RootTenantID, operation.OrganizationID, membershipStatus).Scan(&matches); err != nil {
		return fmt.Errorf("verify membership identity: %w", err)
	}
	if !matches {
		return fmt.Errorf("membership id %d belongs to a different organization or user", operation.SourceUserID)
	}
	expectedRoleStatus := membershipStatusForRole(membershipStatus)
	for _, roleCode := range operation.RoleCodes {
		if _, err := tx.Exec(ctx, `
			INSERT INTO membership_role_assignments(root_tenant_id,organization_id,membership_id,role_code,status)
			SELECT $1::BIGINT,$2::BIGINT,$3::BIGINT,$4::VARCHAR(64),$5::VARCHAR(20)
			WHERE NOT EXISTS (
				SELECT 1 FROM membership_role_assignments
				WHERE membership_id=$3 AND role_code=$4::VARCHAR(64)
			)
		`, operation.RootTenantID, operation.OrganizationID, operation.SourceUserID, roleCode, expectedRoleStatus); err != nil {
			return fmt.Errorf("insert role assignment %s: %w", roleCode, err)
		}
	}
	roleRows, err := tx.Query(ctx, `SELECT role_code,status FROM membership_role_assignments WHERE membership_id=$1 ORDER BY role_code`, operation.SourceUserID)
	if err != nil {
		return fmt.Errorf("verify role assignments: %w", err)
	}
	actualRoles := make(map[string]string)
	for roleRows.Next() {
		var code, status string
		if err := roleRows.Scan(&code, &status); err != nil {
			roleRows.Close()
			return err
		}
		if _, duplicate := actualRoles[code]; duplicate {
			roleRows.Close()
			return fmt.Errorf("membership %d has duplicate role %s", operation.SourceUserID, code)
		}
		actualRoles[code] = status
	}
	roleRows.Close()
	if err := roleRows.Err(); err != nil {
		return err
	}
	if len(actualRoles) != len(operation.RoleCodes) {
		return fmt.Errorf("membership %d role set differs from explicit mapping", operation.SourceUserID)
	}
	for _, roleCode := range operation.RoleCodes {
		if actualRoles[roleCode] != expectedRoleStatus {
			return fmt.Errorf("membership %d role %s has status %s, expected %s", operation.SourceUserID, roleCode, actualRoles[roleCode], expectedRoleStatus)
		}
	}
	quotaTypes := make([]string, 0, len(operation.QuotaDefaults))
	for resourceType := range operation.QuotaDefaults {
		quotaTypes = append(quotaTypes, resourceType)
	}
	sort.Strings(quotaTypes)
	for _, resourceType := range quotaTypes {
		var inheritedFrom *int64
		if operation.OrganizationType != "manufacturer" {
			var ancestor int64
			if err := tx.QueryRow(ctx, `
				SELECT q.organization_id
				FROM organization_closure c
				JOIN organization_quotas q
				  ON q.root_tenant_id=c.root_tenant_id AND q.organization_id=c.ancestor_id
				 AND q.resource_type=$3
				WHERE c.root_tenant_id=$1 AND c.descendant_id=$2 AND c.depth>0
				ORDER BY c.depth ASC LIMIT 1
			`, operation.RootTenantID, operation.OrganizationID, resourceType).Scan(&ancestor); err != nil {
				return fmt.Errorf("find inherited %s quota: %w", resourceType, err)
			}
			inheritedFrom = &ancestor
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO organization_quotas(root_tenant_id,organization_id,resource_type,quota_limit,inherited_from_organization_id)
			VALUES($1,$2,$3,$4,$5)
			ON CONFLICT(root_tenant_id,organization_id,resource_type) DO UPDATE
			SET quota_limit=EXCLUDED.quota_limit,
			    inherited_from_organization_id=EXCLUDED.inherited_from_organization_id,
			    version=organization_quotas.version+1,updated_at=NOW()
		`, operation.RootTenantID, operation.OrganizationID, resourceType, operation.QuotaDefaults[resourceType], inheritedFrom); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO channel_migration_entity_map(
			source_table,source_key,target_type,target_id,mapping_digest,source_fingerprint
		) VALUES('users',$1,'organization',$2,$3,$4)
		ON CONFLICT(source_table,source_key,target_type) DO UPDATE
		SET target_id=EXCLUDED.target_id,mapping_digest=EXCLUDED.mapping_digest,
		    source_fingerprint=EXCLUDED.source_fingerprint,updated_at=NOW()
	`, fmt.Sprint(operation.SourceUserID), operation.OrganizationID, mappingDigest, operation.SourceFingerprint); err != nil {
		return err
	}
	return nil
}

func membershipStatusForRole(membershipStatus string) string {
	if membershipStatus == "active" {
		return "active"
	}
	return "revoked"
}

func (s *PostgresOrganizationBackfillStore) Complete(ctx context.Context, result BackfillResult) error {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `LOCK TABLE users IN SHARE MODE`); err != nil {
		return err
	}
	var expectedWatermark, actualWatermark int64
	var runStatus string
	if err := tx.QueryRow(ctx, `SELECT source_watermark,status FROM channel_migration_runs WHERE id=$1 FOR UPDATE`, s.runID).Scan(&expectedWatermark, &runStatus); err != nil {
		return err
	}
	if runStatus == "completed" {
		return tx.Commit(ctx)
	}
	if err := tx.QueryRow(ctx, `SELECT COALESCE(MAX(id),0) FROM users`).Scan(&actualWatermark); err != nil {
		return err
	}
	if actualWatermark != expectedWatermark {
		return fmt.Errorf("legacy users changed before completion: watermark %d, expected %d", actualWatermark, expectedWatermark)
	}
	sourceRows, err := tx.Query(ctx, `
		SELECT i.source_fingerprint,
		       u.id,u.phone,COALESCE(u.email,''),COALESCE(u.nickname,''),u.role,u.parent_id,u.status,u.deleted_at IS NOT NULL
		FROM channel_migration_items i
		JOIN users u ON u.id=i.source_user_id
		WHERE i.run_id=$1 AND i.source_table='users'
		ORDER BY i.ordinal
	`, s.runID)
	if err != nil {
		return err
	}
	verifiedSources := 0
	for sourceRows.Next() {
		var expectedFingerprint string
		var user LegacyUser
		if err := sourceRows.Scan(&expectedFingerprint, &user.ID, &user.Phone, &user.Email, &user.Nickname, &user.Role, &user.ParentID, &user.Status, &user.Deleted); err != nil {
			sourceRows.Close()
			return err
		}
		actualFingerprint, err := fingerprintJSON(user)
		if err != nil {
			sourceRows.Close()
			return err
		}
		if actualFingerprint != expectedFingerprint {
			sourceRows.Close()
			return fmt.Errorf("legacy user %d changed before completion", user.ID)
		}
		verifiedSources++
	}
	sourceRows.Close()
	if err := sourceRows.Err(); err != nil {
		return err
	}
	var expectedSources int
	if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM channel_migration_items WHERE run_id=$1 AND source_table='users'`, s.runID).Scan(&expectedSources); err != nil {
		return err
	}
	if verifiedSources != expectedSources {
		return fmt.Errorf("legacy source set changed before completion: verified %d of %d", verifiedSources, expectedSources)
	}
	for _, table := range []string{"organizations", "organization_memberships", "membership_role_assignments"} {
		query := fmt.Sprintf(`
			SELECT setval(
				pg_get_serial_sequence('%s','id'),
				GREATEST(COALESCE(MAX(id),1), nextval(pg_get_serial_sequence('%s','id'))),
				true
			) FROM %s
		`, table, table, table)
		if _, err := tx.Exec(ctx, query); err != nil {
			return fmt.Errorf("advance %s sequence: %w", table, err)
		}
	}
	summary, _ := json.Marshal(result)
	if _, err := tx.Exec(ctx, `
		INSERT INTO audit_logs(
			action,resource_type,resource_id,request_id,result,after_data,event_schema_version
		) VALUES('channel_backfill_complete','channel_migration_run',$1,$2,'success',$3,'1.0')
	`, s.runID.String(), "channel-migrate:"+s.runID.String()+":complete", summary); err != nil {
		return fmt.Errorf("write immutable backfill completion audit: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE channel_migration_runs
		SET status='completed',summary=summary || $2::jsonb,completed_at=NOW(),updated_at=NOW()
		WHERE id=$1
	`, s.runID, summary); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *PostgresOrganizationBackfillStore) Fail(ctx context.Context, cause error) error {
	detail := "unknown failure"
	if cause != nil {
		detail = cause.Error()
	}
	if len(detail) > 2000 {
		detail = detail[:2000]
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	payload, _ := json.Marshal(map[string]any{
		"run_id": s.runID, "worker_id": s.workerID,
		"mapping_digest": s.mappingDigest, "source_digest": s.sourceDigest, "error": detail,
	})
	if _, err := tx.Exec(ctx, `
		UPDATE channel_migration_runs
		SET status='failed',completed_at=NOW(),updated_at=NOW(),summary=summary || $2::jsonb
		WHERE id=$1 AND status IN ('prepared','running')
	`, s.runID, payload); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO audit_logs(
			action,resource_type,resource_id,request_id,result,failure_reason,after_data,event_schema_version
		) VALUES('channel_backfill_failed','channel_migration_run',$1,$2,'failed',$3,$4,'1.0')
	`, s.runID.String(), "channel-migrate:"+s.runID.String()+":failed", detail, payload); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

type ChannelShadowReport struct {
	RunID                  uuid.UUID `json:"run_id"`
	PlannedOrganizations   int64     `json:"planned_organizations"`
	SucceededOrganizations int64     `json:"succeeded_organizations"`
	PendingItems           int64     `json:"pending_items"`
	UnresolvedQuarantine   int64     `json:"unresolved_quarantine"`
	ShadowDiffs            int64     `json:"shadow_diffs"`
}

func LoadChannelShadowReport(ctx context.Context, db *pgxpool.Pool, runID uuid.UUID) (ChannelShadowReport, error) {
	report := ChannelShadowReport{RunID: runID}
	if _, err := ReconcileChannelBackfill(ctx, db, runID); err != nil {
		return report, err
	}
	err := db.QueryRow(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE source_table='users'),
			COUNT(*) FILTER (WHERE source_table='users' AND status='succeeded'),
			COUNT(*) FILTER (WHERE status IN ('pending','processing','failed'))
		FROM channel_migration_items WHERE run_id=$1
	`, runID).Scan(&report.PlannedOrganizations, &report.SucceededOrganizations, &report.PendingItems)
	if err != nil {
		return report, fmt.Errorf("load channel migration item summary: %w", err)
	}
	if err := db.QueryRow(ctx, `
		SELECT COUNT(*) FROM channel_migration_quarantine
		WHERE last_seen_run_id=$1 AND status='pending'
	`, runID).Scan(&report.UnresolvedQuarantine); err != nil {
		return report, err
	}
	if err := db.QueryRow(ctx, `SELECT COUNT(*) FROM channel_migration_shadow_diffs WHERE run_id=$1`, runID).Scan(&report.ShadowDiffs); err != nil {
		return report, err
	}
	return report, nil
}

func fingerprintJSON(value any) (string, error) {
	payload, err := json.Marshal(value)
	if err != nil {
		return "", fmt.Errorf("marshal fingerprint payload: %w", err)
	}
	digest := sha256.Sum256(payload)
	return hex.EncodeToString(digest[:]), nil
}

func summaryJSON(report PreflightReport) []byte {
	payload, _ := json.Marshal(map[string]int{
		"planned_organizations": len(report.Operations),
		"quarantine":            len(report.Quarantine),
		"ownership_conflicts":   len(report.OwnershipQuarantine),
	})
	return payload
}

var _ OrganizationBackfillStore = (*PostgresOrganizationBackfillStore)(nil)
