//go:build integration

package repository

import (
	"context"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"testing"
)

// No historical hardware/registry/window record is required to choose, create,
// dispatch, retry or report a real upgrade; the device's actual model is used.
func TestOTAModelTargetLifecycleWithoutHardwareMetadata(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,firmware_arm) VALUES('bare','MODEL','')`)
	f := seedHardwareFirmware(t, pool, "arm", "2.0", nil, true)
	repo := NewOTARepository(pool)
	listed, err := repo.ListPublishedFirmwareForDevice(ctx, "bare", "arm")
	require.NoError(t, err)
	require.Len(t, listed, 1)
	require.Equal(t, f.ID, listed[0].ID)
	latest, err := repo.GetLatestFirmware(ctx, "bare", "MODEL", "arm")
	require.NoError(t, err)
	require.Equal(t, f.ID, latest.ID)
	refs, err := repo.CreateIndependentFirmwareTasks(ctx, 1, "bare", []int64{f.ID}, "bare-upgrade", "trigger", "")
	require.NoError(t, err)
	require.Len(t, refs, 1)
	var id int64
	var old string
	var identity *int64
	require.NoError(t, pool.QueryRow(ctx, `SELECT id,old_version,identity_revision FROM device_upgrades WHERE task_id=$1`, refs[0].TaskID).Scan(&id, &old, &identity))
	require.Empty(t, old)
	require.Nil(t, identity)
	require.NoError(t, repo.ValidateUpgradeSnapshot(ctx, id, "bare", f.ID))
	hardwareExec(t, pool, `UPDATE device_upgrades SET status='failed' WHERE id=$1`, id)
	require.NoError(t, repo.RetryFailedUpgradesByTask(ctx, refs[0].TaskID))
	require.NoError(t, repo.ValidateUpgradeSnapshot(ctx, id, "bare", f.ID))
	require.Error(t, repo.ValidateUpgradeSnapshot(ctx, id, "other", f.ID))
	// Optional history can change or conflict without changing model selection.
	hardwareExec(t, pool, `INSERT INTO device_hardware_registry(sn,verified_model,identity_state,frozen,identity_revision) VALUES('bare','OTHER','conflict',TRUE,9)`)
	_, d, err := repo.ValidateFirmwareForDevice(ctx, "bare", f.ID)
	require.NoError(t, err)
	require.Equal(t, "MODEL", d.Model)
	hardwareExec(t, pool, `UPDATE devices SET model='OTHER' WHERE sn='bare'`)
	_, _, err = repo.ValidateFirmwareForDevice(ctx, "bare", f.ID)
	require.Equal(t, "firmware_incompatible", OTAEligibilityReason(err))
	require.Error(t, repo.ValidateUpgradeSnapshot(ctx, id, "bare", f.ID))
}

func TestOTAModelTargetInsertStillRejectsWrongFirmware(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model) VALUES('bare','MODEL'),('wrong','OTHER')`)
	f := seedHardwareFirmware(t, pool, "dsp", "2.0", nil, true)
	draft := seedHardwareFirmware(t, pool, "dsp", "3.0", nil, false)
	for _, v := range []struct {
		sn, target string
		fid        int64
	}{{"wrong", "dsp", f.ID}, {"bare", "esp", f.ID}, {"bare", "bogus", f.ID}, {"bare", "dsp", draft.ID}} {
		_, err := pool.Exec(ctx, `INSERT INTO device_upgrades(device_sn,firmware_id,target_chip,firmware_version,status,source) VALUES($1,$2,$3,'2.0','pending','admin')`, v.sn, v.fid, v.target)
		require.Error(t, err)
	}
	_, err := pool.Exec(ctx, `INSERT INTO device_upgrades(device_sn,firmware_id,target_chip,firmware_version,status,source) VALUES('bare',$1,'dsp','2.0','pending','admin')`, f.ID)
	require.NoError(t, err)
	repo := NewOTARepository(pool)
	hardwareExec(t, pool, `UPDATE firmware_versions SET rollout_type='device',rollout_targets='other' WHERE id=$1`, f.ID)
	_, _, err = repo.ValidateFirmwareForDevice(ctx, "bare", f.ID)
	require.Equal(t, "firmware_outside_rollout", OTAEligibilityReason(err))
	hardwareExec(t, pool, `UPDATE firmware_versions SET release_status='disabled',status=0 WHERE id=$1`, f.ID)
	_, _, err = repo.ValidateFirmwareForDevice(ctx, "bare", f.ID)
	require.Equal(t, "firmware_not_published", OTAEligibilityReason(err))
}

func TestOTALocalResultMatchesRealModelTargetVersion(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model) VALUES('bare','MODEL')`)
	f := seedHardwareFirmware(t, pool, "dsp", "2.0", nil, true)
	repo := NewOTARepository(pool)
	_, err := repo.CreateTaskFromLocalOTA(ctx, 1, "bare", "esp", "2.0", "", f.ID)
	require.Error(t, err)
	_, err = repo.CreateTaskFromLocalOTA(ctx, 1, "bare", "dsp", "9.0", "", f.ID)
	require.Error(t, err)
	id, err := repo.CreateTaskFromLocalOTA(ctx, 1, "bare", "dsp", "2.0", "", f.ID)
	require.NoError(t, err)
	require.NotZero(t, id)
	var version, status, old string
	require.NoError(t, pool.QueryRow(ctx, `SELECT firmware_dsp FROM devices WHERE sn='bare'`).Scan(&version))
	require.Equal(t, "2.0", version)
	require.NoError(t, pool.QueryRow(ctx, `SELECT status,old_version FROM device_upgrades WHERE task_id=$1`, id).Scan(&status, &old))
	require.Equal(t, model.UpgradeStatusSuccess, status)
	require.Empty(t, old)
}
