package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// AssignUnassignedToStation never moves an existing assignment or changes ownership.
func (r *DeviceRepository) AssignUnassignedToStation(ctx context.Context, sn string, stationID, userID int64) (bool, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return false, fmt.Errorf("begin station assignment: %w", err)
	}
	defer tx.Rollback(ctx)

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
	r.SyncStationStatus(ctx)
	return true, nil
}
