//go:build integration

package repository

import (
	"context"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"testing"
	"time"
)

func TestOTAStageProgressReadRoutes(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	const sn = "OTA-PHASE-SN"
	seedOTAStatusTask(t, pool, 983001, "1.0.0", "running")
	seedOTAStatusUpgrade(t, pool, sn, 983002, 983001, "dsp", "1.0.0", "upgrading", 70, time.Now())
	_, err := pool.Exec(ctx, `UPDATE device_upgrades SET stage='installing', stage_progress=0, overall_progress=70 WHERE device_sn=$1`, sn)
	require.NoError(t, err)
	repo := NewOTARepository(pool)
	latest, err := repo.GetDeviceUpgradeBySN(ctx, sn)
	require.NoError(t, err)
	check := func(stage string, phase, overall *int) {
		require.Equal(t, "installing", stage)
		require.NotNil(t, phase)
		require.NotNil(t, overall)
		require.Equal(t, 0, *phase)
		require.Equal(t, 70, *overall)
	}
	check(latest.Stage, latest.StageProgress, latest.OverallProgress)
	items, err := repo.ListDeviceUpgradesBySNAndTaskID(ctx, sn, 983001)
	require.NoError(t, err)
	require.Len(t, items, 1)
	check(items[0].Stage, items[0].StageProgress, items[0].OverallProgress)
	history, _, err := repo.GetDeviceUpgradeHistory(ctx, sn, 1, 20)
	require.NoError(t, err)
	require.Len(t, history, 1)
	check(history[0].Stage, history[0].StageProgress, history[0].OverallProgress)
	filtered, _, err := repo.ListUpgradeHistoryFiltered(ctx, model.UpgradeHistoryFilter{DeviceSN: sn, Page: 1, PageSize: 20})
	require.NoError(t, err)
	require.Len(t, filtered, 1)
	check(filtered[0].Stage, filtered[0].StageProgress, filtered[0].OverallProgress)
	byID, err := repo.GetUpgradeByID(ctx, latest.ID)
	require.NoError(t, err)
	check(byID.Stage, byID.StageProgress, byID.OverallProgress)
	_, err = repo.ReconcileUpgradeStatusByID(ctx, latest.ID, "success", 100, "")
	require.NoError(t, err)
	confirmed, err := repo.GetDeviceUpgradeBySN(ctx, sn)
	require.NoError(t, err)
	require.Equal(t, "succeeded", confirmed.Stage)
	require.Equal(t, 100, *confirmed.StageProgress)
	require.Equal(t, 100, *confirmed.OverallProgress)
	_, err = pool.Exec(ctx, `UPDATE device_upgrades SET stage_progress=NULL, overall_progress=NULL, progress=70 WHERE id=$1`, latest.ID)
	require.NoError(t, err)
	legacy, err := repo.GetDeviceUpgradeBySN(ctx, sn)
	require.NoError(t, err)
	require.Nil(t, legacy.StageProgress)
	require.Nil(t, legacy.OverallProgress)
	require.Equal(t, 70, legacy.Progress)
}
