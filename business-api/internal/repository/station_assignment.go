package repository

import (
	"context"
	"errors"
	"fmt"
	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5"
)

var ErrAssignmentOutOfScope = errors.New("device or station outside assignment scope")

func (r *DeviceRepository) HasScopedAccess(ctx context.Context, sn string, plan model.ScopePlan, systemAdmin bool) (bool, error) {
	filter, args := OverviewScopeFilter(plan, systemAdmin, "d", 2)
	args = append([]any{sn}, args...)
	var allowed bool
	err := r.db.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM devices d WHERE d.sn=$1 AND d.deleted_at IS NULL AND "+filter+")", args...).Scan(&allowed)
	return allowed, err
}

// AssignToStationScoped checks edit grants for both resources and retains their
// owners. Row locks and the optional unassigned guard prevent stale selections
// or concurrent additions from moving an existing station assignment.
func (r *DeviceRepository) AssignToStationScoped(ctx context.Context, sn string, stationID int64, devicePlan, stationPlan model.ScopePlan, systemAdmin, onlyUnassigned bool) (bool, error) {
	if devicePlan.PermissionCode != "devices:edit" || stationPlan.PermissionCode != "stations:edit" || devicePlan.Actor != stationPlan.Actor {
		return false, ErrAssignmentOutOfScope
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin scoped station assignment: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var timezone string
	err = tx.QueryRow(ctx, `SELECT COALESCE(timezone,'Asia/Shanghai') FROM stations WHERE id=$1 AND deleted_at IS NULL FOR UPDATE`, stationID).Scan(&timezone)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("lock scoped assignment station: %w", err)
	}
	var previousStationID int64
	err = tx.QueryRow(ctx, `SELECT COALESCE(station_id,0) FROM devices WHERE sn=$1 AND deleted_at IS NULL FOR UPDATE`, sn).Scan(&previousStationID)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("lock scoped assignment device: %w", err)
	}

	stationFilter, args := OverviewScopeFilter(stationPlan, systemAdmin, "s", 3)
	deviceFilter, deviceArgs := OverviewScopeFilter(devicePlan, systemAdmin, "d", 3+len(args))
	args = append([]any{sn, stationID}, append(args, deviceArgs...)...)
	where := `d.sn=$1 AND s.id=$2 AND d.deleted_at IS NULL AND s.deleted_at IS NULL AND ` + stationFilter + " AND " + deviceFilter
	var allowed bool
	if err := tx.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM devices d CROSS JOIN stations s WHERE "+where+")", args...).Scan(&allowed); err != nil {
		return false, fmt.Errorf("authorize scoped station assignment: %w", err)
	}
	if !allowed {
		return false, ErrAssignmentOutOfScope
	}
	if onlyUnassigned && previousStationID != 0 {
		return false, nil
	}
	if onlyUnassigned {
		where += " AND d.station_id IS NULL"
	}
	timezoneArg := len(args) + 1
	args = append(args, timezone)
	result, err := tx.Exec(ctx, fmt.Sprintf("UPDATE devices d SET station_id=$2, timezone=$%d, updated_at=NOW() FROM stations s WHERE ", timezoneArg)+where, args...)
	if err != nil {
		return false, fmt.Errorf("assign scoped device to station: %w", err)
	}
	if result.RowsAffected() == 0 {
		return false, ErrAssignmentOutOfScope
	}
	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit scoped station assignment: %w", err)
	}
	r.invalidateDeviceCache(ctx, sn)
	r.updateStationCapacity(ctx, stationID)
	if previousStationID > 0 && previousStationID != stationID {
		r.updateStationCapacity(ctx, previousStationID)
	}
	// The assignment is committed; status reconciliation is best effort.
	_ = r.SyncStationStatus(ctx)
	return true, nil
}

// AssignUnassignedToStation never moves an existing assignment or changes ownership.
func (r *DeviceRepository) AssignUnassignedToStation(ctx context.Context, sn string, stationID, userID int64) (bool, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin station assignment: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Hold the station row while checking ownership and updating the device.
	var timezone string
	err = tx.QueryRow(ctx, `SELECT COALESCE(timezone, 'Asia/Shanghai') FROM stations
		WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL FOR UPDATE`, stationID, userID).Scan(&timezone)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("lock assignment station: %w", err)
	}
	result, err := tx.Exec(ctx, `UPDATE devices SET station_id=$1, timezone=$2, updated_at=NOW()
		WHERE sn=$3 AND user_id=$4 AND station_id IS NULL AND deleted_at IS NULL`, stationID, timezone, sn, userID)
	if err != nil {
		return false, fmt.Errorf("assign unassigned device: %w", err)
	}
	if result.RowsAffected() == 0 {
		return false, nil
	}
	if err := tx.Commit(ctx); err != nil {
		return false, fmt.Errorf("commit station assignment: %w", err)
	}
	r.invalidateDeviceCache(ctx, sn)
	r.updateStationCapacity(ctx, stationID)
	// The assignment is committed; status reconciliation is best effort.
	_ = r.SyncStationStatus(ctx)
	return true, nil
}
