//go:build integration

package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestCreateRevivesSoftDeletedDevice 回归防护：devices.sn 是完整唯一索引，
// 删除仅软删（deleted_at）不删行。此前重新录入同一 SN 会因唯一冲突报
// device already exists，而列表（deleted_at IS NULL）里又看不到它——
// 表现为"界面上加不了、数据库里却有"。期望行为：软删残留行被复活重置为
// 未绑定新设备，而不是报错。
func TestCreateRevivesSoftDeletedDevice(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	repo := NewDeviceRepository(pool, nil)
	const sn = "REVIVE-SN-001"

	require.NoError(t, repo.Create(ctx, sn, "M1", nil, "1.0.0", "2.0.0"))

	// 软删后重新录入：应复活而非 already exists
	require.NoError(t, repo.Delete(ctx, sn))
	var deletedNow bool
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT deleted_at IS NOT NULL FROM devices WHERE sn=$1`, sn).Scan(&deletedNow))
	require.True(t, deletedNow, "precondition: row is soft-deleted")

	ratedPower := 6.6
	require.NoError(t, repo.Create(ctx, sn, "M2", &ratedPower, "1.1.0", "2.1.0"))

	var (
		userID     int64
		stationID  any
		model      string
		fwArm      string
		fwEsp      string
		isDeleted  bool
		activeOnly bool
	)
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT user_id, station_id, model, firmware_arm, firmware_esp, deleted_at IS NOT NULL
		FROM devices WHERE sn=$1`, sn).Scan(&userID, &stationID, &model, &fwArm, &fwEsp, &isDeleted))
	assert.False(t, isDeleted, "resurrected row must not be soft-deleted")
	assert.Zero(t, userID, "resurrected row must be unbound (user_id=0)")
	assert.Nil(t, stationID, "resurrected row must not keep the old station")
	assert.Equal(t, "M2", model)
	assert.Equal(t, "1.1.0", fwArm)
	assert.Equal(t, "2.1.0", fwEsp)

	// 复活后的行必须能被正常查询到（等价于 GetBySN 的非软删过滤）
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT deleted_at IS NULL FROM devices WHERE sn=$1 AND deleted_at IS NULL`, sn).Scan(&activeOnly))
	assert.True(t, activeOnly)
}

// TestCreateRejectsStillActiveDevice 保护 DO UPDATE 的 WHERE 守卫：仅当冲突行
// 是软删残留时才复活；仍在使用的设备必须继续报 already exists，防止被覆盖。
func TestCreateRejectsStillActiveDevice(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	repo := NewDeviceRepository(pool, nil)
	const sn = "ACTIVE-SN-001"

	require.NoError(t, repo.Create(ctx, sn, "M1", nil, "", ""))

	err := repo.Create(ctx, sn, "M2", nil, "", "")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "already exists")

	var rowCount int
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM devices WHERE sn=$1`, sn).Scan(&rowCount))
	assert.Equal(t, 1, rowCount, "active device must never be duplicated or reset")
}

// TestEnsureDeviceRevivesSoftDeletedRow 保护绑定前的 EnsureDevice 路径：
// 软删残留应被复活（deleted_at 清空），但仍在用（未软删）的设备不得被重置归属。
func TestEnsureDeviceRevivesSoftDeletedRow(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	repo := NewDeviceRepository(pool, nil)
	const snDeleted = "ENSURE-SN-DEL"
	const snActive = "ENSURE-SN-ACT"

	// 软删行：EnsureDevice 后复活
	require.NoError(t, repo.Create(ctx, snDeleted, "", nil, "", ""))
	require.NoError(t, repo.Delete(ctx, snDeleted))
	require.NoError(t, repo.EnsureDevice(ctx, snDeleted))
	var deletedIsNil bool
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT deleted_at IS NULL FROM devices WHERE sn=$1`, snDeleted).Scan(&deletedIsNil))
	assert.True(t, deletedIsNil, "EnsureDevice must un-delete a soft-deleted row")

	// 在用行：EnsureDevice 不得清空归属（user_id/station 保持原样）
	require.NoError(t, repo.Create(ctx, snActive, "", nil, "", ""))
	_, err := pool.Exec(ctx, `UPDATE devices SET user_id=42, station_id=NULL WHERE sn=$1`, snActive)
	require.NoError(t, err)
	require.NoError(t, repo.EnsureDevice(ctx, snActive))
	var userID int64
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT user_id FROM devices WHERE sn=$1`, snActive).Scan(&userID))
	assert.Equal(t, int64(42), userID, "EnsureDevice must not reset an in-use device's owner")
}
