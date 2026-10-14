package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/apperr"
)

type HardwareRegistryRepository struct{ db *pgxpool.Pool }

func NewHardwareRegistryRepository(db *pgxpool.Pool) *HardwareRegistryRepository {
	return &HardwareRegistryRepository{db: db}
}

type hardwareQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

func (r *HardwareRegistryRepository) ListBoardTypes(ctx context.Context, modelName, target string) ([]model.HardwareBoardType, error) {
	rows, err := r.db.Query(ctx, `SELECT model,target_chip,board_code,description,created_at FROM hardware_board_types WHERE ($1='' OR model=$1) AND ($2='' OR target_chip=$2) ORDER BY model,target_chip,board_code`, modelName, target)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []model.HardwareBoardType{}
	for rows.Next() {
		var b model.HardwareBoardType
		if err := rows.Scan(&b.Model, &b.TargetChip, &b.BoardCode, &b.Description, &b.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, b)
	}
	return result, rows.Err()
}
func (r *HardwareRegistryRepository) CreateBoardType(ctx context.Context, b model.HardwareBoardType) error {
	tag, err := r.db.Exec(ctx, `INSERT INTO hardware_board_types(model,target_chip,board_code,description) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, b.Model, b.TargetChip, b.BoardCode, b.Description)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return apperr.Conflict("board type already exists; stable codes cannot be reused")
	}
	return nil
}
func getHardwareRegistry(ctx context.Context, q hardwareQuerier, sn string, lock bool) (*model.HardwareRegistry, error) {
	v := &model.HardwareRegistry{Modules: []model.HardwareModule{}, Observations: []model.HardwareObservation{}}
	sql := `SELECT sn,verified_model,identity_state,identity_revision,frozen,source,evidence_ref,verified_by,verified_at FROM device_hardware_registry WHERE sn=$1`
	if lock {
		sql += " FOR UPDATE"
	}
	if err := q.QueryRow(ctx, sql, sn).Scan(&v.SN, &v.VerifiedModel, &v.IdentityState, &v.IdentityRevision, &v.Frozen, &v.Source, &v.EvidenceRef, &v.VerifiedBy, &v.VerifiedAt); err != nil {
		return nil, err
	}
	rows, err := q.Query(ctx, `SELECT target_chip,COALESCE(board_code,''),board_uid,state,module_revision,protection_level FROM device_hardware_modules WHERE sn=$1 ORDER BY target_chip`, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var m model.HardwareModule
		if err := rows.Scan(&m.TargetChip, &m.BoardCode, &m.BoardUID, &m.State, &m.ModuleRevision, &m.ProtectionLevel); err != nil {
			return nil, err
		}
		v.Modules = append(v.Modules, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	return v, nil
}
func (r *HardwareRegistryRepository) Get(ctx context.Context, sn string) (*model.HardwareRegistry, error) {
	// A read transaction prevents a registry from being combined with modules from another revision.
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	v, err := getHardwareRegistry(ctx, tx, sn, false)
	if errors.Is(err, pgx.ErrNoRows) {
		v = &model.HardwareRegistry{SN: sn, IdentityState: "unverified", Modules: []model.HardwareModule{}, Observations: []model.HardwareObservation{}}
	} else if err != nil {
		return nil, err
	}
	rows, err := tx.Query(ctx, `SELECT DISTINCT ON(scope) id,sn,reported_model,scope,reported_board_code,reported_board_uid,source,reported_at FROM device_hardware_observations WHERE sn=$1 ORDER BY scope,LEAST(reported_at,received_at) DESC,id DESC`, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var o model.HardwareObservation
		if err := rows.Scan(&o.ID, &o.SN, &o.ReportedModel, &o.Scope, &o.ReportedBoardCode, &o.ReportedBoardUID, &o.Source, &o.ReportedAt); err != nil {
			return nil, err
		}
		v.Observations = append(v.Observations, o)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return v, nil
}
func hardwareAudit(ctx context.Context, tx pgx.Tx, before, after *model.HardwareRegistry, action, reason, evidence string, actor int64) error {
	b, err := json.Marshal(before)
	if err != nil {
		return err
	}
	a, err := json.Marshal(after)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO device_hardware_history(sn,action,previous_revision,identity_revision,actor,reason,evidence_ref,before_snapshot,after_snapshot) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, after.SN, action, before.IdentityRevision, after.IdentityRevision, actor, reason, evidence, b, a)
	return err
}
func mutateHardware(ctx context.Context, tx pgx.Tx, sn, action string, req model.HardwareMutation, actor int64) (*model.HardwareRegistry, error) {
	// Registry lifetime is independent from devices/account binding.
	_, err := tx.Exec(ctx, `INSERT INTO device_hardware_registry(sn) VALUES($1) ON CONFLICT DO NOTHING`, sn)
	if err != nil {
		return nil, err
	}
	before, err := getHardwareRegistry(ctx, tx, sn, true)
	if err != nil {
		return nil, err
	}
	if before.IdentityRevision != req.ExpectedRevision {
		return nil, apperr.Conflict("identity_changed: reload hardware record")
	}
	if action == "verify" || action == "import" {
		if before.IdentityState != "unverified" {
			return nil, apperr.Conflict("verified identity requires correction or service change")
		}
	}
	if action == "correction" || action == "service_change" {
		if before.IdentityRevision == 0 || before.IdentityState == "retired" {
			return nil, apperr.Conflict("identity is not eligible for correction")
		}
	}
	if action == "service_change" && !before.Frozen {
		return nil, apperr.Conflict("freeze identity before replacing modules")
	}
	next := *before
	next.IdentityRevision++
	next.Source = req.Source
	next.EvidenceRef = req.EvidenceRef
	next.VerifiedBy = actor
	now := time.Now().UTC()
	next.VerifiedAt = &now
	if action == "freeze" {
		if !req.Frozen && before.IdentityState != "verified" {
			return nil, apperr.Conflict("resolve identity conflict before unfreezing")
		}
		next.Frozen = req.Frozen
		_, err = tx.Exec(ctx, `UPDATE device_hardware_registry SET frozen=$2,identity_revision=$3,source=$4,evidence_ref=$5,verified_by=$6,verified_at=$7,updated_at=NOW() WHERE sn=$1`, sn, next.Frozen, next.IdentityRevision, next.Source, next.EvidenceRef, actor, now)
	} else {
		// Validate references before any destructive replacement; a transaction still guards all writes.
		for _, m := range req.Modules {
			if m.State == "absent" {
				continue
			}
			var found bool
			err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM hardware_board_types WHERE model=$1 AND target_chip=$2 AND board_code=$3)`, req.VerifiedModel, m.TargetChip, m.BoardCode).Scan(&found)
			if err != nil {
				return nil, err
			}
			if !found {
				return nil, apperr.BadRequest("unknown board type for model and target")
			}
		}
		_, err = tx.Exec(ctx, `DELETE FROM device_hardware_modules WHERE sn=$1`, sn)
		if err != nil {
			return nil, err
		}
		next.VerifiedModel = req.VerifiedModel
		next.IdentityState = "verified"
		next.Modules = []model.HardwareModule{}
		_, err = tx.Exec(ctx, `UPDATE device_hardware_registry SET verified_model=$2,identity_state='verified',identity_revision=$3,source=$4,evidence_ref=$5,verified_by=$6,verified_at=$7,updated_at=NOW() WHERE sn=$1`, sn, next.VerifiedModel, next.IdentityRevision, next.Source, next.EvidenceRef, actor, now)
		if err != nil {
			return nil, err
		}
		for _, m := range req.Modules {
			m.ModuleRevision = 1
			for _, old := range before.Modules {
				if old.TargetChip == m.TargetChip {
					m.ModuleRevision = old.ModuleRevision + 1
				}
			}
			m.ProtectionLevel = "registry_verified" // Manual record edits cannot certify device enforcement.
			var code any = m.BoardCode
			if m.State == "absent" {
				code = nil
			}
			_, err = tx.Exec(ctx, `INSERT INTO device_hardware_modules(sn,verified_model,target_chip,board_code,board_uid,state,module_revision,protection_level) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, sn, next.VerifiedModel, m.TargetChip, code, m.BoardUID, m.State, m.ModuleRevision, m.ProtectionLevel)
			if err != nil {
				return nil, err
			}
			next.Modules = append(next.Modules, m)
		}
	}
	if err != nil {
		return nil, err
	}
	if err := hardwareAudit(ctx, tx, before, &next, action, req.Reason, req.EvidenceRef, actor); err != nil {
		return nil, err
	}
	return &next, nil
}
func (r *HardwareRegistryRepository) Mutate(ctx context.Context, sn, action string, req model.HardwareMutation, actor int64) (*model.HardwareRegistry, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	v, err := mutateHardware(ctx, tx, sn, action, req, actor)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return v, nil
}
func (r *HardwareRegistryRepository) History(ctx context.Context, sn string, page, size int) ([]model.HardwareHistory, int64, error) {
	var total int64
	if err := r.db.QueryRow(ctx, `SELECT count(*) FROM device_hardware_history WHERE sn=$1`, sn).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := r.db.Query(ctx, `SELECT id,sn,action,previous_revision,identity_revision,actor,reason,evidence_ref,before_snapshot,after_snapshot,created_at FROM device_hardware_history WHERE sn=$1 ORDER BY id DESC LIMIT $2 OFFSET $3`, sn, size, (page-1)*size)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	result := []model.HardwareHistory{}
	for rows.Next() {
		var h model.HardwareHistory
		if err := rows.Scan(&h.ID, &h.SN, &h.Action, &h.PreviousRevision, &h.IdentityRevision, &h.Actor, &h.Reason, &h.EvidenceRef, &h.Before, &h.After, &h.CreatedAt); err != nil {
			return nil, 0, err
		}
		result = append(result, h)
	}
	return result, total, rows.Err()
}

// Observe retains reports verbatim and never creates verified module identities.
func (r *HardwareRegistryRepository) Observe(ctx context.Context, o model.HardwareObservation) error {
	// Retain raw report time while comparing at most server receipt time: an
	// untrusted future clock must not suppress subsequent identity checks.
	if o.ReportedAt.IsZero() {
		o.ReportedAt = time.Now().UTC()
	}
	effectiveAt := o.ReportedAt
	if effectiveAt.After(time.Now().UTC()) {
		effectiveAt = time.Now().UTC()
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `INSERT INTO device_hardware_registry(sn) VALUES($1) ON CONFLICT DO NOTHING`, o.SN)
	if err != nil {
		return err
	}
	before, err := getHardwareRegistry(ctx, tx, o.SN, true)
	if err != nil {
		return err
	}
	var latest *time.Time
	err = tx.QueryRow(ctx, `SELECT MAX(LEAST(reported_at,received_at)) FROM device_hardware_observations WHERE sn=$1 AND scope=$2`, o.SN, o.Scope).Scan(&latest)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO device_hardware_observations(sn,reported_model,scope,reported_board_code,reported_board_uid,source,reported_at) VALUES($1,$2,$3,$4,$5,$6,$7)`, o.SN, o.ReportedModel, o.Scope, o.ReportedBoardCode, o.ReportedBoardUID, o.Source, o.ReportedAt)
	if err != nil {
		return err
	}
	conflict := false
	if before.IdentityState == "verified" && (latest == nil || effectiveAt.After(*latest)) {
		conflict = o.ReportedModel != "" && before.VerifiedModel != "" && o.ReportedModel != before.VerifiedModel
		if o.Scope != "legacy_system" {
			foundTarget := false
			for _, m := range before.Modules {
				if m.TargetChip == o.Scope {
					foundTarget = true
					conflict = conflict || (m.State == "absent" && (o.ReportedBoardCode != "" || o.ReportedBoardUID != "")) || (o.ReportedBoardCode != "" && o.ReportedBoardCode != m.BoardCode) || (o.ReportedBoardUID != "" && m.BoardUID != "" && o.ReportedBoardUID != m.BoardUID)
				}
			}
			if !foundTarget && (o.ReportedBoardCode != "" || o.ReportedBoardUID != "") {
				conflict = true
			}
		}
	}
	if conflict {
		next := *before
		next.IdentityState = "conflict"
		next.IdentityRevision++
		_, err = tx.Exec(ctx, `UPDATE device_hardware_registry SET identity_state='conflict',identity_revision=$2,updated_at=NOW() WHERE sn=$1`, o.SN, next.IdentityRevision)
		if err != nil {
			return err
		}
		if err := hardwareAudit(ctx, tx, before, &next, "observation_conflict", "reported identity differs from verified identity", o.Source, 0); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (r *HardwareRegistryRepository) RecordIdentityConflict(ctx context.Context, sn, reason, evidence string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `INSERT INTO device_hardware_registry(sn) VALUES($1) ON CONFLICT DO NOTHING`, sn)
	if err != nil {
		return err
	}
	before, err := getHardwareRegistry(ctx, tx, sn, true)
	if err != nil {
		return err
	}
	if before.IdentityState == "conflict" {
		return tx.Commit(ctx)
	}
	after := *before
	after.IdentityState = "conflict"
	after.IdentityRevision++
	_, err = tx.Exec(ctx, `UPDATE device_hardware_registry SET identity_state='conflict',identity_revision=$2,updated_at=NOW() WHERE sn=$1`, sn, after.IdentityRevision)
	if err != nil {
		return err
	}
	if err := hardwareAudit(ctx, tx, before, &after, "session_identity_conflict", reason, evidence, 0); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func sameHardware(r *model.HardwareRegistry, in model.HardwareImportInput) bool {
	if r.VerifiedModel != in.VerifiedModel || len(r.Modules) != len(in.Modules) {
		return false
	}
	for _, m := range in.Modules {
		found := false
		for _, old := range r.Modules {
			if m.TargetChip == old.TargetChip && m.BoardCode == old.BoardCode && m.BoardUID == old.BoardUID && m.State == old.State {
				found = true
			}
		}
		if !found {
			return false
		}
	}
	return true
}
func (r *HardwareRegistryRepository) StageImport(ctx context.Context, inputs []model.HardwareImportInput, actor int64) (*model.HardwareImportBatch, error) {
	data, err := json.Marshal(inputs)
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(data)
	digest := hex.EncodeToString(sum[:])
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	var id int64
	err = tx.QueryRow(ctx, `INSERT INTO hardware_import_batches(actor,file_sha256) VALUES($1,$2) ON CONFLICT(actor,file_sha256) DO UPDATE SET file_sha256=EXCLUDED.file_sha256 RETURNING id`, actor, digest).Scan(&id)
	if err != nil {
		return nil, err
	}
	var count int
	err = tx.QueryRow(ctx, `SELECT count(*) FROM hardware_import_rows WHERE batch_id=$1`, id).Scan(&count)
	if err != nil {
		return nil, err
	}
	if count == 0 {
		seen := map[string]bool{}
		for i, in := range inputs {
			row := model.HardwareImportRow{RowIndex: i + 1, Data: in, Valid: true, Errors: []string{}, Status: "new"}
			if err := model.ValidateHardwareMutation(in.SN, "import", in.HardwareMutation); err != nil {
				row.Errors = append(row.Errors, err.Error())
			}
			if seen[in.SN] {
				row.Errors = append(row.Errors, "duplicate SN in batch")
			}
			seen[in.SN] = true
			for _, m := range in.Modules {
				if m.State == "absent" {
					continue
				}
				var exists bool
				err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM hardware_board_types WHERE model=$1 AND target_chip=$2 AND board_code=$3)`, in.VerifiedModel, m.TargetChip, m.BoardCode).Scan(&exists)
				if err != nil {
					return nil, err
				}
				if !exists {
					row.Errors = append(row.Errors, "unknown board type: "+m.TargetChip+"/"+m.BoardCode)
				}
			}
			current, err := getHardwareRegistry(ctx, tx, in.SN, false)
			if err != nil && !errors.Is(err, pgx.ErrNoRows) {
				return nil, err
			}
			if current != nil && current.IdentityState != "unverified" {
				if sameHardware(current, in) {
					row.Status = "same"
				} else {
					row.Status = "conflict"
					row.Errors = append(row.Errors, "existing identity requires correction; import cannot overwrite")
				}
			}
			if len(row.Errors) > 0 {
				row.Valid = false
				if row.Status != "conflict" {
					row.Status = "invalid"
				}
			}
			encoded, _ := json.Marshal(in)
			errs, _ := json.Marshal(row.Errors)
			_, err = tx.Exec(ctx, `INSERT INTO hardware_import_rows(batch_id,row_index,row_data,valid,errors,status) VALUES($1,$2,$3,$4,$5,$6)`, id, i+1, encoded, row.Valid, errs, row.Status)
			if err != nil {
				return nil, err
			}
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return r.ImportBatch(ctx, id, actor)
}
func (r *HardwareRegistryRepository) ImportBatch(ctx context.Context, id, actor int64) (*model.HardwareImportBatch, error) {
	var owned bool
	if err := r.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM hardware_import_batches WHERE id=$1 AND actor=$2)`, id, actor).Scan(&owned); err != nil {
		return nil, err
	}
	if !owned {
		return nil, apperr.NotFound("import batch not found")
	}
	rows, err := r.db.Query(ctx, `SELECT row_index,row_data,valid,errors,status FROM hardware_import_rows WHERE batch_id=$1 ORDER BY row_index`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := &model.HardwareImportBatch{ID: id, Rows: []model.HardwareImportRow{}}
	for rows.Next() {
		var row model.HardwareImportRow
		var data, errs []byte
		if err := rows.Scan(&row.RowIndex, &data, &row.Valid, &errs, &row.Status); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(data, &row.Data); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(errs, &row.Errors); err != nil {
			return nil, err
		}
		out.Rows = append(out.Rows, row)
	}
	return out, rows.Err()
}
func (r *HardwareRegistryRepository) CommitImport(ctx context.Context, id, actor int64, req model.HardwareImportCommit) (*model.HardwareImportBatch, error) {
	batch, err := r.ImportBatch(ctx, id, actor)
	if err != nil {
		return nil, err
	}
	sort.Ints(req.RowIndexes)
	encoded, _ := json.Marshal(req.RowIndexes)
	sum := sha256.Sum256(encoded)
	digest := hex.EncodeToString(sum[:])
	selected := map[int]bool{}
	for _, index := range req.RowIndexes {
		if selected[index] || index < 1 || index > len(batch.Rows) {
			return nil, apperr.BadRequest("invalid row selection")
		}
		selected[index] = true
		if !batch.Rows[index-1].Valid {
			return nil, apperr.BadRequest("only valid rows can be committed")
		}
	}
	var saved string
	err = r.db.QueryRow(ctx, `INSERT INTO hardware_import_commits(batch_id,idempotency_key,request_digest) VALUES($1,$2,$3) ON CONFLICT(batch_id,idempotency_key) DO UPDATE SET request_digest=hardware_import_commits.request_digest RETURNING request_digest`, id, req.IdempotencyKey, digest).Scan(&saved)
	if err != nil {
		return nil, err
	}
	if saved != digest {
		return nil, apperr.Conflict("idempotency key has different row selection")
	}
	// The selection is resumable. Each <=500-row chunk owns an atomic transaction.
	for start := 0; start < len(req.RowIndexes); start += 500 {
		end := start + 500
		if end > len(req.RowIndexes) {
			end = len(req.RowIndexes)
		}
		if err := r.commitImportChunk(ctx, id, actor, req.RowIndexes[start:end]); err != nil {
			return nil, err
		}
	}
	return r.ImportBatch(ctx, id, actor)
}
func (r *HardwareRegistryRepository) commitImportChunk(ctx context.Context, id, actor int64, indexes []int) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	// Lock batch before registry keys so simultaneous selected submissions cannot deadlock.
	var locked int64
	if err := tx.QueryRow(ctx, `SELECT id FROM hardware_import_batches WHERE id=$1 AND actor=$2 FOR UPDATE`, id, actor).Scan(&locked); err != nil {
		return err
	}
	for _, i := range indexes {
		var data []byte
		var valid bool
		var status string
		err = tx.QueryRow(ctx, `SELECT row_data,valid,status FROM hardware_import_rows WHERE batch_id=$1 AND row_index=$2 FOR UPDATE`, id, i).Scan(&data, &valid, &status)
		if err != nil {
			return err
		}
		if status == "committed" {
			continue
		}
		if !valid {
			return apperr.BadRequest("import row invalid")
		}
		var in model.HardwareImportInput
		if err := json.Unmarshal(data, &in); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO device_hardware_registry(sn) VALUES($1) ON CONFLICT DO NOTHING`, in.SN)
		if err != nil {
			return err
		}
		current, err := getHardwareRegistry(ctx, tx, in.SN, true)
		if err != nil {
			return err
		}
		if current.IdentityState != "unverified" {
			if !sameHardware(current, in) {
				return apperr.Conflict("identity changed since preview; import cannot overwrite")
			}
		} else {
			in.ExpectedRevision = current.IdentityRevision
			if _, err := mutateHardware(ctx, tx, in.SN, "import", in.HardwareMutation, actor); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, `UPDATE hardware_import_rows SET status='committed' WHERE batch_id=$1 AND row_index=$2`, id, i)
		if err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (r *HardwareRegistryRepository) SetFirmwareBoards(ctx context.Context, id, actor int64, codes []string, reason, evidence string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var modelName, target, version, status string
	err = tx.QueryRow(ctx, `SELECT model,target_chip,version,release_status FROM firmware_versions WHERE id=$1 FOR UPDATE`, id).Scan(&modelName, &target, &version, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return apperr.NotFound("firmware not found")
	}
	if err != nil {
		return err
	}
	rows, err := tx.Query(ctx, `SELECT board_code FROM firmware_board_types WHERE firmware_id=$1 ORDER BY board_code`, id)
	if err != nil {
		return err
	}
	old := []string{}
	for rows.Next() {
		var code string
		if err := rows.Scan(&code); err != nil {
			rows.Close()
			return err
		}
		old = append(old, code)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	sort.Strings(codes)
	before, _ := json.Marshal(old)
	after, _ := json.Marshal(codes)
	if string(before) == string(after) {
		return tx.Commit(ctx)
	}
	if status != "draft" && len(old) > 0 {
		return apperr.Conflict("published board scope is immutable")
	}
	if status != "draft" && status != "published" {
		return apperr.Conflict("firmware cannot receive board scope")
	}
	for _, code := range codes {
		var valid bool
		err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM hardware_board_types WHERE model=$1 AND target_chip=$2 AND board_code=$3)`, modelName, target, code).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return apperr.BadRequest("board type does not match firmware model and target")
		}
	}
	_, err = tx.Exec(ctx, `DELETE FROM firmware_board_types WHERE firmware_id=$1`, id)
	if err != nil {
		return err
	}
	for _, code := range codes {
		_, err = tx.Exec(ctx, `INSERT INTO firmware_board_types(firmware_id,model,target_chip,firmware_version,board_code) VALUES($1,$2,$3,$4,$5)`, id, modelName, target, version, code)
		if err != nil {
			var dbErr *pgconn.PgError
			if errors.As(err, &dbErr) && dbErr.Code == "23505" {
				return apperr.Conflict("firmware version already assigned to board type")
			}
			return err
		}
	}
	_, err = tx.Exec(ctx, `INSERT INTO firmware_board_scope_audits(firmware_id,actor,reason,evidence_ref,before_codes,after_codes) VALUES($1,$2,$3,$4,$5,$6)`, id, actor, reason, evidence, before, after)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func (r *HardwareRegistryRepository) CreateCompatibilityWindow(ctx context.Context, w model.OTACompatibilityWindow, actor int64) (*model.OTACompatibilityWindow, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	identity, err := getHardwareRegistry(ctx, tx, w.SN, true)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, apperr.Conflict("identity_unverified")
	}
	if err != nil {
		return nil, err
	}
	if identity.IdentityState != "verified" || identity.Frozen {
		return nil, apperr.Conflict("identity_unverified or identity_conflict")
	}
	if identity.IdentityRevision != w.IdentityRevision {
		return nil, apperr.Conflict("identity_changed")
	}
	eligible := false
	for _, m := range identity.Modules {
		if m.TargetChip == w.TargetChip && m.State == "verified" {
			err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM firmware_versions f JOIN firmware_board_types b ON b.firmware_id=f.id WHERE f.id=$1 AND f.model=$2 AND f.target_chip=$3 AND f.file_sha256=$4 AND f.release_status='published' AND f.status=1 AND b.board_code=$5)`, w.FirmwareID, identity.VerifiedModel, w.TargetChip, w.FileSHA256, m.BoardCode).Scan(&eligible)
			if err != nil {
				return nil, err
			}
		}
	}
	if !eligible {
		return nil, apperr.BadRequest("firmware_incompatible or firmware_scope_missing")
	}
	w.Actor = actor
	err = tx.QueryRow(ctx, `INSERT INTO ota_compatibility_windows(sn,target_chip,firmware_id,file_sha256,expires_at,identity_revision,reason,actor,evidence_ref) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`, w.SN, w.TargetChip, w.FirmwareID, w.FileSHA256, w.ExpiresAt, w.IdentityRevision, w.Reason, actor, w.EvidenceRef).Scan(&w.ID)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &w, nil
}
func (r *HardwareRegistryRepository) ListCompatibilityWindows(ctx context.Context, sn string) ([]model.OTACompatibilityWindow, error) {
	rows, err := r.db.Query(ctx, `SELECT id,sn,target_chip,firmware_id,file_sha256,identity_revision,expires_at,reason,evidence_ref,actor FROM ota_compatibility_windows WHERE ($1='' OR sn=$1) ORDER BY id DESC LIMIT 500`, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []model.OTACompatibilityWindow{}
	for rows.Next() {
		var w model.OTACompatibilityWindow
		if err := rows.Scan(&w.ID, &w.SN, &w.TargetChip, &w.FirmwareID, &w.FileSHA256, &w.IdentityRevision, &w.ExpiresAt, &w.Reason, &w.EvidenceRef, &w.Actor); err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

func (r *HardwareRegistryRepository) FirmwareBoards(ctx context.Context, id int64) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT board_code FROM firmware_board_types WHERE firmware_id=$1 ORDER BY board_code`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var code string
		if err := rows.Scan(&code); err != nil {
			return nil, err
		}
		out = append(out, code)
	}
	return out, rows.Err()
}
