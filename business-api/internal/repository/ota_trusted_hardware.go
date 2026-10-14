package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"inv-api-server/internal/model"
)

// OTAEligibilityError exposes one stable reason across query, creation and dispatch.
var ErrFirmwareOutsideRollout = errors.New("firmware_outside_rollout")

type OTAEligibilityError struct{ Reason string }

func (e *OTAEligibilityError) Error() string { return e.Reason }
func OTAEligibilityReason(err error) string {
	var e *OTAEligibilityError
	if errors.As(err, &e) {
		return e.Reason
	}
	if errors.Is(err, ErrFirmwareNotPublished) {
		return "firmware_not_published"
	}
	if errors.Is(err, ErrFirmwareOutsideRollout) {
		return "firmware_outside_rollout"
	}
	return "verification_pending"
}

type trustedOTAIdentity struct {
	Model, IdentityState, ModuleState, BoardCode, BoardUID, ProtectionLevel string
	IdentityRevision, ModuleRevision                                        int64
	Frozen, HasScope, Compatible, WindowValid                               bool
}

func (v trustedOTAIdentity) reason(channel string) string {
	if v.Frozen || v.IdentityState == "conflict" || v.IdentityState == "service_pending" {
		return "identity_conflict"
	}
	if v.IdentityState != "verified" || v.Model == "" {
		return "identity_unverified"
	}
	if v.ModuleState == "absent" {
		return "module_absent"
	}
	if v.ModuleState == "conflict" || v.ModuleState == "service_pending" {
		return "identity_conflict"
	}
	if v.ModuleState != "verified" || v.BoardCode == "" {
		return "module_identity_missing"
	}
	if !v.HasScope {
		return "firmware_scope_missing"
	}
	if !v.Compatible {
		return "firmware_incompatible"
	}
	// Full enforcement needs V2 manifest, device identity and durable authorization.
	// This rollout has no such verified protocol implementation; never grant it
	// merely because a database capability string claims device_enforced.
	if channel != "cloud" || !v.WindowValid {
		return "device_protection_required"
	}
	return ""
}

type otaQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func queryTrustedOTAIdentity(ctx context.Context, q otaQuerier, sn, target string, fid int64, lock bool) (trustedOTAIdentity, error) {
	var v trustedOTAIdentity
	sql := `SELECT verified_model,identity_state,identity_revision,frozen FROM device_hardware_registry WHERE sn=$1`
	if lock {
		sql += ` FOR SHARE`
	}
	err := q.QueryRow(ctx, sql, sn).Scan(&v.Model, &v.IdentityState, &v.IdentityRevision, &v.Frozen)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, &OTAEligibilityError{"identity_unverified"}
	}
	if err != nil {
		return v, err
	}
	if v.Frozen || v.IdentityState == "conflict" || v.IdentityState == "service_pending" {
		return v, &OTAEligibilityError{"identity_conflict"}
	}
	if v.IdentityState != "verified" || v.Model == "" {
		return v, &OTAEligibilityError{"identity_unverified"}
	}
	sql = `SELECT COALESCE(board_code,''),COALESCE(board_uid,''),state,module_revision,protection_level FROM device_hardware_modules WHERE sn=$1 AND target_chip=$2`
	if lock {
		sql += ` FOR SHARE`
	}
	err = q.QueryRow(ctx, sql, sn, target).Scan(&v.BoardCode, &v.BoardUID, &v.ModuleState, &v.ModuleRevision, &v.ProtectionLevel)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, &OTAEligibilityError{"module_identity_missing"}
	}
	if err != nil {
		return v, err
	}
	err = q.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM firmware_board_types WHERE firmware_id=$1),
 EXISTS(SELECT 1 FROM firmware_board_types WHERE firmware_id=$1 AND model=$2 AND target_chip=$3 AND board_code=$4),
 EXISTS(SELECT 1 FROM ota_compatibility_windows w JOIN firmware_versions f ON f.id=w.firmware_id
 WHERE w.sn=$5 AND w.target_chip=$3 AND w.firmware_id=$1 AND w.identity_revision=$6
 AND w.expires_at>NOW() AND length(f.file_sha256)=64 AND w.file_sha256=f.file_sha256)`, fid, v.Model, target, v.BoardCode, sn, v.IdentityRevision).Scan(&v.HasScope, &v.Compatible, &v.WindowValid)
	return v, err
}

func validateTrustedFirmware(ctx context.Context, q otaQuerier, sn string, f *model.Firmware, channel string, lock bool) (trustedOTAIdentity, error) {
	v, err := queryTrustedOTAIdentity(ctx, q, sn, f.TargetChip, f.ID, lock)
	if err != nil {
		return v, err
	}
	return v, evaluateTrustedFirmware(v, f, sn, channel)
}

// evaluateTrustedFirmware owns the firmware-side verdict so batch listing and
// per-device dispatch cannot drift apart.
func evaluateTrustedFirmware(v trustedOTAIdentity, f *model.Firmware, sn, channel string) error {
	if reason := v.reason(channel); reason != "" {
		return &OTAEligibilityError{reason}
	}
	if f.Model != v.Model {
		return &OTAEligibilityError{"firmware_incompatible"}
	}
	if f.ReleaseStatus != model.FirmwareReleasePublished || f.Status != 1 {
		return ErrFirmwareNotPublished
	}
	if !firmwareEligibleForDevice(f, sn) {
		return ErrFirmwareOutsideRollout
	}
	return nil
}

// otaTargetVersionColumn maps a module target to its devices column. The returned
// name is interpolated into SQL, so unknown targets must never pass through.
func otaTargetVersionColumn(target string) (string, bool) {
	switch target {
	case "arm":
		return "firmware_arm", true
	case "esp":
		return "firmware_esp", true
	case "dsp":
		return "firmware_dsp", true
	case "bms":
		return "firmware_bms", true
	}
	return "", false
}

// ListTaskCandidates returns every device of the firmware's model the operator
// can see, each carrying the same verdict the dispatch path will apply. Devices
// that cannot be upgraded stay listed with a reason: silently hiding them hides
// why a task cannot start.
func (r *OTARepository) ListTaskCandidates(ctx context.Context, f *model.Firmware, plan model.ScopePlan, systemAdmin bool) (*model.OTATaskCandidateList, error) {
	column, ok := otaTargetVersionColumn(f.TargetChip)
	if !ok {
		return nil, &OTAEligibilityError{"firmware_incompatible"}
	}
	filter, args := OverviewScopeFilter(plan, systemAdmin, "d", 1)
	next := len(args) + 1
	targetPlaceholder, firmwarePlaceholder, modelPlaceholder := fmt.Sprintf("$%d", next), fmt.Sprintf("$%d", next+1), fmt.Sprintf("$%d", next+2)
	args = append(args, f.TargetChip, f.ID, f.Model)

	query := fmt.Sprintf(`
		SELECT d.sn, COALESCE(d.alias,''), COALESCE(d.model,''), COALESCE(d.%[2]s,''),
		       COALESCE(r.verified_model,''), COALESCE(r.identity_state,'unverified'), COALESCE(r.identity_revision,0), COALESCE(r.frozen,FALSE),
		       COALESCE(m.board_code,''), COALESCE(m.state,''), COALESCE(m.protection_level,''),
		       EXISTS(SELECT 1 FROM firmware_board_types b WHERE b.firmware_id=%[4]s),
		       EXISTS(SELECT 1 FROM firmware_board_types b WHERE b.firmware_id=%[4]s AND b.model=r.verified_model
		              AND b.target_chip=m.target_chip AND b.board_code=m.board_code),
		       EXISTS(SELECT 1 FROM ota_compatibility_windows w JOIN firmware_versions fv ON fv.id=w.firmware_id
		              WHERE w.sn=d.sn AND w.target_chip=%[3]s AND w.firmware_id=%[4]s
		                AND w.identity_revision=COALESCE(r.identity_revision,0) AND w.expires_at>NOW()
		                AND length(fv.file_sha256)=64 AND w.file_sha256=fv.file_sha256)
		FROM devices d
		LEFT JOIN device_hardware_registry r ON r.sn=d.sn
		LEFT JOIN device_hardware_modules m ON m.sn=d.sn AND m.target_chip=%[3]s
		WHERE d.deleted_at IS NULL AND (d.model=%[5]s OR r.verified_model=%[5]s) AND %[1]s
		ORDER BY d.sn LIMIT 2000`, filter, column, targetPlaceholder, firmwarePlaceholder, modelPlaceholder)
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := &model.OTATaskCandidateList{TargetChip: f.TargetChip, FirmwareID: f.ID, Items: []model.OTATaskCandidate{}}
	for rows.Next() {
		var (
			c                              model.OTATaskCandidate
			identityRevision               int64
			frozen                         bool
			hasScope, compatible, windowOK bool
		)
		if err = rows.Scan(&c.SN, &c.Alias, &c.Model, &c.CurrentVersion,
			&c.VerifiedModel, &c.IdentityState, &identityRevision, &frozen,
			&c.BoardCode, &c.ModuleState, &c.ProtectionLevel,
			&hasScope, &compatible, &windowOK); err != nil {
			return nil, err
		}
		verdict := trustedOTAIdentity{
			Model: c.VerifiedModel, IdentityState: c.IdentityState, IdentityRevision: identityRevision, Frozen: frozen,
			ModuleState: c.ModuleState, BoardCode: c.BoardCode, ProtectionLevel: c.ProtectionLevel,
			HasScope: hasScope, Compatible: compatible, WindowValid: windowOK,
		}
		if err = evaluateTrustedFirmware(verdict, f, c.SN, "cloud"); err == nil {
			c.Eligible = true
			result.EligibleCount++
		} else {
			c.Reason = OTAEligibilityReason(err)
			result.ExcludedCount++
		}
		result.Items = append(result.Items, c)
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	result.Total = len(result.Items)
	return result, nil
}

// ValidateUpgradeSnapshot rejects every queued/retried task after a registry edit.
func (r *OTARepository) ValidateUpgradeSnapshot(ctx context.Context, id int64, sn string, fid int64) error {
	var matches bool
	err := r.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM device_upgrades u
 JOIN device_hardware_registry r ON r.sn=u.device_sn
 JOIN device_hardware_modules m ON m.sn=r.sn AND m.target_chip=u.target_chip
 WHERE u.id=$1 AND u.device_sn=$2 AND u.firmware_id=$3
 AND u.identity_revision=r.identity_revision AND u.module_revision=m.module_revision
 AND u.board_code=m.board_code AND COALESCE(u.board_uid,'')=COALESCE(m.board_uid,''))`, id, sn, fid).Scan(&matches)
	if err != nil {
		return err
	}
	if !matches {
		return &OTAEligibilityError{"identity_changed"}
	}
	return nil
}

func (r *OTARepository) validateRetryCandidates(ctx context.Context, firmwareID int64, sns []string, taskID int64) error {
	rows, err := r.db.Query(ctx, `SELECT id,device_sn,firmware_id FROM device_upgrades WHERE status='failed'
 AND ($1::bigint=0 OR firmware_id=$1) AND ($2::text[] IS NULL OR device_sn=ANY($2)) AND ($3::bigint=0 OR task_id=$3)`, firmwareID, sns, taskID)
	if err != nil {
		return err
	}
	type candidate struct {
		id, fid int64
		sn      string
	}
	items := []candidate{}
	for rows.Next() {
		var c candidate
		if err = rows.Scan(&c.id, &c.sn, &c.fid); err != nil {
			rows.Close()
			return err
		}
		items = append(items, c)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, c := range items {
		if err = r.ValidateUpgradeSnapshot(ctx, c.id, c.sn, c.fid); err != nil {
			return err
		}
		if _, _, err = r.ValidateFirmwareForDevice(ctx, c.sn, c.fid); err != nil {
			return err
		}
	}
	return nil
}

func (r *OTARepository) GetTrustedModuleOverview(ctx context.Context, sn, target string) (model.FirmwareModuleOverview, error) {
	v, err := queryTrustedOTAIdentity(ctx, r.db, sn, target, 0, false)
	out := model.FirmwareModuleOverview{BoardCode: v.BoardCode, BoardUID: v.BoardUID, ModuleRevision: v.ModuleRevision, ProtectionLevel: v.ProtectionLevel}
	if err != nil {
		out.CompatibilityReason = OTAEligibilityReason(err)
		return out, err
	}
	if v.IdentityState != "verified" || v.Frozen {
		out.CompatibilityReason = "identity_unverified"
	} else if v.ModuleState != "verified" {
		out.CompatibilityReason = "module_identity_missing"
	}
	if out.CompatibilityReason == "" {
		var f model.Firmware
		err = scanFirmware(r.db.QueryRow(ctx, `SELECT `+firmwareSelectCols("f")+` FROM firmware_versions f
 JOIN firmware_board_types b ON b.firmware_id=f.id WHERE b.model=$1 AND b.target_chip=$2 AND b.board_code=$3
 AND f.release_status='published' ORDER BY f.published_at DESC NULLS LAST,f.id DESC LIMIT 1`, v.Model, target, v.BoardCode), &f)
		if errors.Is(err, pgx.ErrNoRows) {
			out.CompatibilityReason = "no_compatible_firmware"
		} else if err != nil {
			return out, err
		} else if _, err = validateTrustedFirmware(ctx, r.db, sn, &f, "cloud", false); err != nil {
			out.CompatibilityReason = OTAEligibilityReason(err)
		}
	}
	return out, nil
}
