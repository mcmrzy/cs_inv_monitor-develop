//go:build integration

package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 设备核心数据链路真库回归：Create/EnsureDevice 幂等语义 → Bind（仅未绑定可绑、
// 电站时区继承、key hash 落库）→ HasDataPermission 三分支（属主/共享成员/陌生人）
// → GetAllowedDeviceSNs 并集语义 → Unbind 重置。

func TestDeviceLifecycleBindPermissionAndReset(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	repo := NewDeviceRepository(pool, nil)

	const (
		sn        = "LC-CORE-SN-001"
		sharedSN  = "LC-CORE-SN-002"
		ownerID   = int64(501)
		memberID  = int64(502)
		stranger  = int64(503)
		stationID = int64(601)
	)

	seed := `
		INSERT INTO users(id, phone, password_hash, status) VALUES
			(501, 'lc-501', 'hash', 1), (502, 'lc-502', 'hash', 1), (503, 'lc-503', 'hash', 1);
		INSERT INTO stations(id, user_id, name, province, city, address, capacity, timezone) VALUES (601, 501, 'LC Station', '湖南省', '长沙市', '麓谷', 10.0, 'UTC');
	`
	_, err := pool.Exec(ctx, seed)
	require.NoError(t, err)

	// Create：设备以未绑定状态（user_id=0）落库
	require.NoError(t, repo.Create(ctx, sn, "CS-INV-TEST", nil, "1.0.0", "1.0.0"))

	// 重复 Create 活跃设备必须报 already exists（不可静默覆盖绑定关系）
	err = repo.Create(ctx, sn, "CS-INV-TEST", nil, "", "")
	require.ErrorContains(t, err, "already exists")

	// 未绑定设备对任何人都无数据权限
	assert.False(t, repo.HasDataPermission(ctx, ownerID, sn))

	// Bind：写入 user_id/station_id/key hash，并继承电站时区
	require.NoError(t, repo.Bind(ctx, sn, ownerID, stationID, "hash-abc"))
	var tz, keyHash string
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT timezone, device_key_hash FROM devices WHERE sn=$1`, sn).Scan(&tz, &keyHash))
	assert.Equal(t, "UTC", tz, "绑定后必须继承电站时区")
	assert.Equal(t, "hash-abc", keyHash)

	// 已绑定设备不可二次绑定
	err = repo.Bind(ctx, sn, memberID, 0, "hash-xyz")
	require.ErrorContains(t, err, "already bound")

	// HasDataPermission：属主/共享成员/陌生人 三分支
	assert.True(t, repo.HasDataPermission(ctx, ownerID, sn))
	_, err = pool.Exec(ctx,
		`INSERT INTO user_device_rel(user_id, device_sn) VALUES ($1, $2)`, memberID, sn)
	require.NoError(t, err)
	assert.True(t, repo.HasDataPermission(ctx, memberID, sn), "user_device_rel 成员必须有数据权限")
	assert.False(t, repo.HasDataPermission(ctx, stranger, sn))

	// GetAllowedDeviceSNs：属主设备 + 共享设备 并集，且排除陌生人
	_, err = pool.Exec(ctx, `INSERT INTO devices(sn, model, user_id) VALUES ($1, 'CS-INV-TEST', $2)`, sharedSN, stranger)
	require.NoError(t, err)
	_, err = pool.Exec(ctx,
		`INSERT INTO user_device_rel(user_id, device_sn) VALUES ($1, $2)`, memberID, sharedSN)
	require.NoError(t, err)

	ownerSNs, err := repo.GetAllowedDeviceSNs(ctx, ownerID)
	require.NoError(t, err)
	assert.Equal(t, []string{sn}, ownerSNs)

	memberSNs, err := repo.GetAllowedDeviceSNs(ctx, memberID)
	require.NoError(t, err)
	assert.Equal(t, []string{"LC-CORE-SN-001", "LC-CORE-SN-002"}, memberSNs, "属主设备与共享设备都应可见且按 SN 有序")

	// GetBySN：字段回读 + 未知 SN 返回 nil,nil（调用方按不存在处理）
	got, err := repo.GetBySN(ctx, sn)
	require.NoError(t, err)
	require.NotNil(t, got)
	assert.Equal(t, sn, got.SN)
	assert.Equal(t, ownerID, got.UserID)
	assert.NotNil(t, got.StationID)
	assert.Equal(t, stationID, *got.StationID)
	missing, err := repo.GetBySN(ctx, "LC-CORE-SN-404")
	require.NoError(t, err)
	assert.Nil(t, missing)

	// Unbind：绑定关系全部重置，权限随之失效
	require.NoError(t, repo.Unbind(ctx, sn))
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT COALESCE(device_key_hash,'') FROM devices WHERE sn=$1`, sn).Scan(&keyHash))
	assert.Empty(t, keyHash)
	assert.False(t, repo.HasDataPermission(ctx, ownerID, sn), "解绑后原属主不再有数据权限")

	// EnsureDevice：软删复活路径——软删后重新录入恢复可见，未触达的软删行保持不可见
	_, err = pool.Exec(ctx, `UPDATE devices SET deleted_at=NOW() WHERE sn=$1`, sn)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `UPDATE devices SET deleted_at=NOW() WHERE sn=$1`, sharedSN)
	require.NoError(t, err)
	require.NoError(t, repo.EnsureDevice(ctx, sn))
	var alive bool
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT deleted_at IS NULL FROM devices WHERE sn=$1`, sn).Scan(&alive))
	assert.True(t, alive, "软删设备 EnsureDevice 后必须复活")
	require.NoError(t, pool.QueryRow(ctx,
		`SELECT deleted_at IS NULL FROM devices WHERE sn=$1`, sharedSN).Scan(&alive))
	assert.False(t, alive, "未被 EnsureDevice 触达的软删行必须保持不可见")
}
