//go:build integration

package repository

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

// OTA 升级生命周期真库回归：Upsert → 设备侧拉取 pending → 进度上报 → 终态保护 →
// 失败重推幂等（retry_count 递增）与成功后重推保持（不复活已完成升级）。

func TestOTAUpgradeLifecyclePendingToSuccess(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	const (
		sn         = "OTA-LC-SN-001"
		firmwareID = int64(990001)
	)
	seedOTALifecycleFirmware(t, pool, firmwareID, "2.0.0", "esp")

	repo := NewOTARepository(pool)
	pushedBy := int64(300)
	du := &model.DeviceUpgrade{
		DeviceSN:        sn,
		FirmwareID:      firmwareID,
		FirmwareVersion: "2.0.0",
		TargetChip:      "esp",
		OldVersion:      "1.9.0",
		Status:          "pending",
		PushedBy:        &pushedBy,
	}
	require.NoError(t, repo.UpsertDeviceUpgrade(ctx, du))
	require.NotZero(t, du.ID)

	// 设备侧 CheckUpdate 拉取 pending 升级，附带固件元数据
	got, fw, err := repo.GetPendingUpgradeForDevice(ctx, sn)
	require.NoError(t, err)
	assert.Equal(t, du.ID, got.ID)
	assert.Equal(t, "pending", got.Status)
	assert.Equal(t, "esp", got.TargetChip)
	assert.Equal(t, "2.0.0", fw.Version)
	assert.Equal(t, "/firmware/2.0.0.bin", fw.FileURL)

	// 进度上报：进入 downloading 后不再属于 pending
	rows, err := repo.UpdateUpgradeStatus(ctx, sn, "downloading", 10, "")
	require.NoError(t, err)
	assert.Equal(t, int64(1), rows)
	_, _, err = repo.GetPendingUpgradeForDevice(ctx, sn)
	assert.ErrorIs(t, err, pgx.ErrNoRows, "downloading 状态的升级不应再被设备拉取为 pending")
	// GetActiveUpgradeBySN 只认 pending/upgrading 两态
	rows, err = repo.UpdateUpgradeStatus(ctx, sn, "upgrading", 45, "")
	require.NoError(t, err)
	active, err := repo.GetActiveUpgradeBySN(ctx, sn)
	require.NoError(t, err)
	assert.Equal(t, "upgrading", active.Status)
	assert.Equal(t, 45, active.Progress)

	// 完成上报：completed_at 落库
	rows, err = repo.UpdateUpgradeStatus(ctx, sn, "success", 100, "")
	require.NoError(t, err)
	assert.Equal(t, int64(1), rows)
	var completedAt *time.Time
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT completed_at FROM device_upgrades WHERE id=$1`, du.ID).Scan(&completedAt))
	assert.NotNil(t, completedAt)

	// 终态保护：success 之后再上报进度不得改写
	rows, err = repo.UpdateUpgradeStatus(ctx, sn, "failed", 0, "迟到上报")
	require.NoError(t, err)
	assert.Zero(t, rows, "终态升级不得被迟到上报改写")
	var status string
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT status FROM device_upgrades WHERE id=$1`, du.ID).Scan(&status))
	assert.Equal(t, "success", status)

	// 成功后重推同一固件：ON CONFLICT 保持 success，不复活、不递增 retry_count
	retryCountBefore := 0
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT retry_count FROM device_upgrades WHERE id=$1`, du.ID).Scan(&retryCountBefore))
	repush := &model.DeviceUpgrade{
		DeviceSN: sn, FirmwareID: firmwareID, FirmwareVersion: "2.0.0",
		TargetChip: "esp", Status: "pending", PushedBy: &pushedBy,
	}
	require.NoError(t, repo.UpsertDeviceUpgrade(ctx, repush))
	assert.Equal(t, du.ID, repush.ID, "重推必须命中同一行")
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT status, retry_count FROM device_upgrades WHERE id=$1`, du.ID).Scan(&status, &retryCountBefore))
	assert.Equal(t, "success", status, "已完成升级不得被重推复活")
	assert.Equal(t, 0, retryCountBefore)
}

func TestOTAUpgradeLifecycleFailedRepushIncrementsRetry(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	const (
		sn         = "OTA-LC-SN-002"
		firmwareID = int64(990101)
	)
	seedOTALifecycleFirmware(t, pool, firmwareID, "3.1.0", "arm")

	repo := NewOTARepository(pool)
	pushedBy := int64(300)
	du := &model.DeviceUpgrade{
		DeviceSN: sn, FirmwareID: firmwareID, FirmwareVersion: "3.1.0",
		TargetChip: "arm", OldVersion: "3.0.0", Status: "failed",
		ErrorMessage: "download timeout", PushedBy: &pushedBy,
	}
	require.NoError(t, repo.UpsertDeviceUpgrade(ctx, du))

	// 失败后重推：pending 复活 + retry_count 递增 + 保留原 old_version
	repush := &model.DeviceUpgrade{
		DeviceSN: sn, FirmwareID: firmwareID, FirmwareVersion: "3.1.0",
		TargetChip: "arm", OldVersion: "", Status: "pending", PushedBy: &pushedBy,
	}
	require.NoError(t, repo.UpsertDeviceUpgrade(ctx, repush))
	assert.Equal(t, du.ID, repush.ID)

	got, _, err := repo.GetPendingUpgradeForDevice(ctx, sn)
	require.NoError(t, err)
	assert.Equal(t, "pending", got.Status)
	assert.Equal(t, 1, got.RetryCount, "失败重推必须递增 retry_count")
	assert.Equal(t, "3.0.0", got.OldVersion, "old_version 非空时重推不得覆盖")
	// upsert 只在新状态为 failed 时写 error_message；复活为 pending 保留上次失败原因供用户查看
	assert.Equal(t, "download timeout", got.ErrorMessage)
}

func seedOTALifecycleFirmware(t *testing.T, pool *pgxpool.Pool, id int64, version, chip string) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO firmware_versions (id, model, version, file_url, target_chip, main_version)
		VALUES ($1, 'CS-INV-TEST', $2, $3, $4, $5)
	`, id, version, "/firmware/"+version+".bin", chip, "V"+version)
	require.NoError(t, err)
}
