//go:build integration

package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// devices.status 三态: 0=离线, 1=在线, 2=故障但在线。故障态设备的遥测仍在
// 上报, 固件页也按 IN (1,2) 显示在线, 因此提交升级任务必须用同一口径 ——
// 否则界面显示在线、提交却报 DEVICE_OFFLINE（提交入口曾经只认 =1）。
func TestCreateIndependentFirmwareTasksTreatsFaultStateAsOnline(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	const (
		userID   = int64(9301)
		deviceSN = "OTA-STATUS2-SN-001"
	)

	_, err := pool.Exec(ctx, `
		INSERT INTO users(id, phone, password_hash, is_system_admin, status)
		VALUES ($1, 'ota-status2-9301', 'hash', false, 1);
	`, userID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO devices(sn, model, user_id, status, firmware_esp)
		VALUES ($1, 'CS-L10-6K2', $2, 2, '1.6.1');
	`, deviceSN, userID)
	require.NoError(t, err)

	repo := NewOTARepository(pool)

	// 固件页口径: status=2 视为在线
	info, err := repo.GetDeviceInfoForOTA(ctx, deviceSN)
	require.NoError(t, err)
	require.True(t, info.IsOnline, "status=2 必须在固件页被视为在线")

	// 提交任务口径: 必须与上面一致, 否则界面在线却提交报离线
	_, err = repo.CreateIndependentFirmwareTasks(ctx, userID, deviceSN, []int64{999999}, "idem-status2", "upgrade", "")
	assert.NotErrorIs(t, err, ErrDeviceOffline,
		"status=2 设备提交升级任务不应被判离线")

	// 真离线(status=0)仍必须拦住
	_, err = pool.Exec(ctx, `UPDATE devices SET status=0 WHERE sn=$1`, deviceSN)
	require.NoError(t, err)
	_, err = repo.CreateIndependentFirmwareTasks(ctx, userID, deviceSN, []int64{999999}, "idem-status0", "upgrade", "")
	assert.ErrorIs(t, err, ErrDeviceOffline, "status=0 设备必须仍被判离线")
}
