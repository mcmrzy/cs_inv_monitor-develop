//go:build integration

package repository

import (
	"context"
	"github.com/stretchr/testify/require"
	"testing"
)

func TestTrustedOTAModuleWindowsAndSnapshots(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	f := seedHardwareFirmware(t, pool, "esp", "2.0", []string{"HW-1", "HW-2"}, true)
	r := NewOTARepository(pool)
	ctx := context.Background()
	// Device reports may even contain a wrong model without replacing the ledger.
	hardwareExec(t, pool, `UPDATE devices SET model='OTHER',hardware_version='HW-2' WHERE sn='one'`)
	fw, d, err := r.ValidateFirmwareForDevice(ctx, "one", f.ID)
	require.NoError(t, err)
	require.Equal(t, "MODEL", d.Model)
	require.Equal(t, f.ID, fw.ID)
	refs, err := r.CreateIndependentFirmwareTasks(ctx, 1, "one", []int64{f.ID}, "verified", "trigger", "")
	require.NoError(t, err)
	var id int64
	require.NoError(t, pool.QueryRow(ctx, `SELECT id FROM device_upgrades WHERE task_id=$1`, refs[0].TaskID).Scan(&id))
	require.NoError(t, r.ValidateUpgradeSnapshot(ctx, id, "one", f.ID))
	hardwareExec(t, pool, `UPDATE device_hardware_modules SET module_revision=2,board_code='HW-2',board_uid='replacement' WHERE sn='one' AND target_chip='esp'`)
	hardwareExec(t, pool, `UPDATE device_upgrades SET status='failed' WHERE id=$1`, id)
	require.Equal(t, "identity_changed", OTAEligibilityReason(r.RetryFailedUpgradesByTask(ctx, refs[0].TaskID)))
	// The new board is compatible, but the original task must never be retargeted.
	_, _, err = r.ValidateFirmwareForDevice(ctx, "one", f.ID)
	require.NoError(t, err)
	require.Equal(t, "identity_changed", OTAEligibilityReason(r.ValidateUpgradeSnapshot(ctx, id, "one", f.ID)))
	hardwareExec(t, pool, `UPDATE ota_compatibility_windows SET expires_at=NOW()-INTERVAL '1 second'`)
	_, _, err = r.ValidateFirmwareForDevice(ctx, "one", f.ID)
	require.Equal(t, "device_protection_required", OTAEligibilityReason(err))
	_, err = r.CreateIndependentFirmwareTasks(ctx, 1, "one", []int64{f.ID}, "forced", "trigger", "forced by admin")
	require.Equal(t, "device_protection_required", OTAEligibilityReason(err))
	list, err := r.ListPublishedFirmwareForDevice(ctx, "one", "esp")
	require.NoError(t, err)
	require.Empty(t, list)
	hardwareExec(t, pool, `UPDATE ota_compatibility_windows SET expires_at=NOW()+INTERVAL '1 hour',identity_revision=2`)
	_, _, err = r.ValidateFirmwareForDevice(ctx, "one", f.ID)
	require.Equal(t, "device_protection_required", OTAEligibilityReason(err))
	hardwareExec(t, pool, `UPDATE device_hardware_registry SET identity_state='conflict' WHERE sn='one'`)
	_, _, err = r.ValidateFirmwareForDevice(ctx, "one", f.ID)
	require.Equal(t, "identity_conflict", OTAEligibilityReason(err))
}

func TestTrustedOTADatabaseInsertCannotBypassGate(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	f := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	hardwareExec(t, pool, `DELETE FROM ota_compatibility_windows`)
	_, err := pool.Exec(context.Background(), `INSERT INTO device_upgrades(device_sn,firmware_id,target_chip,firmware_version,status,source)
 VALUES('one',$1,'arm','2.0','pending','admin')`, f.ID)
	require.Error(t, err, "legacy insertion must enforce exact compatibility window")
}
