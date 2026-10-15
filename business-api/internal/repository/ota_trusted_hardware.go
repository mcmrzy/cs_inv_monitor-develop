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

type otaDeviceMetadata struct {
	Model, IdentityState, ModuleState, BoardCode, BoardUID, ProtectionLevel string
	IdentityRevision, ModuleRevision                                        int64
	Frozen                                                                  bool
}

type otaQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

// Device model is authoritative for OTA. Registry and module values are optional
// historical metadata; their absence must not prevent ordinary upgrades.
func queryOTADeviceMetadata(ctx context.Context, q otaQuerier, sn, target string, lock bool) (otaDeviceMetadata, error) {
	var v otaDeviceMetadata
	sql := `SELECT COALESCE(d.model,''),COALESCE(r.identity_state,'unverified'),COALESCE(r.identity_revision,0),COALESCE(r.frozen,FALSE),
 COALESCE(m.board_code,''),COALESCE(m.board_uid,''),COALESCE(m.state,''),COALESCE(m.module_revision,0),COALESCE(m.protection_level,'')
 FROM devices d LEFT JOIN device_hardware_registry r ON r.sn=d.sn
 LEFT JOIN device_hardware_modules m ON m.sn=d.sn AND m.target_chip=$2
 WHERE d.sn=$1 AND d.deleted_at IS NULL`
	if lock {
		sql += ` FOR SHARE OF d`
	}
	err := q.QueryRow(ctx, sql, sn, target).Scan(&v.Model, &v.IdentityState, &v.IdentityRevision, &v.Frozen, &v.BoardCode, &v.BoardUID, &v.ModuleState, &v.ModuleRevision, &v.ProtectionLevel)
	if errors.Is(err, pgx.ErrNoRows) {
		return v, ErrDeviceNotFound
	}
	return v, err
}

func validateFirmwareForDevice(ctx context.Context, q otaQuerier, sn string, f *model.Firmware, lock bool) (otaDeviceMetadata, error) {
	v, err := queryOTADeviceMetadata(ctx, q, sn, f.TargetChip, lock)
	if err != nil {
		return v, err
	}
	return v, evaluateFirmwareForDevice(v, f, sn)
}

// One model/target/release/rollout verdict is shared by listing and dispatch.
func evaluateFirmwareForDevice(v otaDeviceMetadata, f *model.Firmware, sn string) error {
	if _, ok := otaTargetVersionColumn(f.TargetChip); !ok {
		return &OTAEligibilityError{"firmware_incompatible"}
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
	targetPlaceholder, modelPlaceholder := fmt.Sprintf("$%d", next), fmt.Sprintf("$%d", next+1)
	args = append(args, f.TargetChip, f.Model)
	query := fmt.Sprintf(`SELECT d.sn,COALESCE(d.alias,''),COALESCE(d.model,''),COALESCE(d.%[2]s,''),
 COALESCE(r.verified_model,''),COALESCE(r.identity_state,'unverified'),COALESCE(m.board_code,''),COALESCE(m.state,''),COALESCE(m.protection_level,'')
 FROM devices d LEFT JOIN device_hardware_registry r ON r.sn=d.sn
 LEFT JOIN device_hardware_modules m ON m.sn=d.sn AND m.target_chip=%[3]s
 WHERE d.deleted_at IS NULL AND d.model=%[4]s AND %[1]s ORDER BY d.sn LIMIT 2000`, filter, column, targetPlaceholder, modelPlaceholder)
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := &model.OTATaskCandidateList{TargetChip: f.TargetChip, FirmwareID: f.ID, Items: []model.OTATaskCandidate{}}
	for rows.Next() {
		var c model.OTATaskCandidate
		if err = rows.Scan(&c.SN, &c.Alias, &c.Model, &c.CurrentVersion, &c.VerifiedModel, &c.IdentityState, &c.BoardCode, &c.ModuleState, &c.ProtectionLevel); err != nil {
			return nil, err
		}
		verdict := otaDeviceMetadata{Model: c.Model}
		if err = evaluateFirmwareForDevice(verdict, f, c.SN); err == nil {
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

// ValidateUpgradeSnapshot preserves task/device/firmware binding at dispatch.
// Historical hardware revisions no longer control whether the task can run.
func (r *OTARepository) ValidateUpgradeSnapshot(ctx context.Context, id int64, sn string, fid int64) error {
	var matches bool
	err := r.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM device_upgrades u JOIN firmware_versions f ON f.id=u.firmware_id
 WHERE u.id=$1 AND u.device_sn=$2 AND u.firmware_id=$3 AND u.target_chip=f.target_chip)`, id, sn, fid).Scan(&matches)
	if err != nil {
		return err
	}
	if !matches {
		return &OTAEligibilityError{"firmware_incompatible"}
	}
	_, _, err = r.ValidateFirmwareForDevice(ctx, sn, fid)
	return err
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
	v, err := queryOTADeviceMetadata(ctx, r.db, sn, target, false)
	out := model.FirmwareModuleOverview{BoardCode: v.BoardCode, BoardUID: v.BoardUID, ModuleRevision: v.ModuleRevision, ProtectionLevel: v.ProtectionLevel}
	if err != nil {
		out.CompatibilityReason = OTAEligibilityReason(err)
		return out, err
	}
	return out, nil
}
