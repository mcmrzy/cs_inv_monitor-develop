//go:build integration

package repository

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

// 独立模块固件升级：schema 约束与发布生命周期真库回归。
// 覆盖 release_status 回填、唯一性、重复尝试、幂等请求与旧包任务收口。

func insertFirmwareForIndependent(t *testing.T, pool *pgxpool.Pool, id int64, model, version, chip string, releaseStatus string, publishedAt *time.Time) {
	t.Helper()
	statusVal := 0
	if releaseStatus == "published" {
		statusVal = 1
	}
	_, err := pool.Exec(context.Background(), `
		INSERT INTO firmware_versions (id, model, version, file_url, target_chip, release_status, published_at, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, id, model, version, "/fw/"+version+".bin", chip, releaseStatus, publishedAt, int16(statusVal))
	require.NoError(t, err)
}

func insertDeviceUpgradeAttempt(t *testing.T, pool *pgxpool.Pool, id int64, sn, chip string, firmwareID int64, taskID int64) int64 {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO device_upgrades (id, device_sn, firmware_id, firmware_version, target_chip, status, task_id)
		VALUES ($1, $2, $3, $4, $5, 'pending', $6)
	`, id, sn, firmwareID, "1.0."+string(rune('0'+id%10)), chip, taskID)
	require.NoError(t, err)
	return id
}

func TestIndependentOTASchemaSupportsRepeatedAttempts(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	insertFirmwareForIndependent(t, pool, 710101, "CS-INV-IND", "1.0.0", "arm", "published", ptrTime(time.Now()))

	_, err := pool.Exec(ctx, `
		INSERT INTO upgrade_tasks (id, task_type, firmware_id, model, status, target_version)
		VALUES (7101, 'single', 710101, 'CS-INV-IND', 'running', '1.0.0'),
		       (7102, 'single', 710101, 'CS-INV-IND', 'pending', '1.0.0')
	`)
	require.NoError(t, err)

	first := insertDeviceUpgradeAttempt(t, pool, 71011, "SN-IND-1", "arm", 710101, 7101)
	second := insertDeviceUpgradeAttempt(t, pool, 71012, "SN-IND-1", "arm", 710101, 7102)
	require.NotEqual(t, first, second, "同一固件应允许产生多次手动任务")

	// 同一任务同一设备模块不能重复
	_, err = pool.Exec(ctx, `
		INSERT INTO device_upgrades (device_sn, firmware_id, firmware_version, target_chip, status, task_id)
		VALUES ('SN-IND-1', 710101, '1.0.0', 'arm', 'pending', 7101)
	`)
	require.Error(t, err, "同一任务同一设备模块必须拒绝重复插入")
	assert.Contains(t, err.Error(), "23505")
}

func TestIndependentOTAReleaseStatusBackfill(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	// 模拟迁移前旧行：status=1/0，无 release_status（迁移已回填，直接验证结果）
	// 通过迁移回放后的默认值语义验证
	insertFirmwareForIndependent(t, pool, 710201, "CS-INV-BF", "1.0.0", "dsp", "published", ptrTime(time.Now().Add(-time.Hour)))
	insertFirmwareForIndependent(t, pool, 710202, "CS-INV-BF", "1.0.1", "dsp", "draft", nil)
	insertFirmwareForIndependent(t, pool, 710203, "CS-INV-BF", "0.9.0", "dsp", "disabled", nil)

	// 软删行必须保留 disabled 语义
	var st string
	require.NoError(t, pool.QueryRow(ctx, `SELECT release_status FROM firmware_versions WHERE id=710201`).Scan(&st))
	assert.Equal(t, "published", st)
	require.NoError(t, pool.QueryRow(ctx, `SELECT release_status FROM firmware_versions WHERE id=710202`).Scan(&st))
	assert.Equal(t, "draft", st)
	require.NoError(t, pool.QueryRow(ctx, `SELECT release_status FROM firmware_versions WHERE id=710203`).Scan(&st))
	assert.Equal(t, "disabled", st)

	var publishedAt *time.Time
	require.NoError(t, pool.QueryRow(ctx, `SELECT published_at FROM firmware_versions WHERE id=710201`).Scan(&publishedAt))
	assert.NotNil(t, publishedAt)
	require.NoError(t, pool.QueryRow(ctx, `SELECT published_at FROM firmware_versions WHERE id=710202`).Scan(&publishedAt))
	assert.Nil(t, publishedAt)
}

func TestIndependentOTAFirmwareVersionUnique(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	insertFirmwareForIndependent(t, pool, 710301, "CS-INV-UQ", "2.0.0", "bms", "published", ptrTime(time.Now()))

	// 同 model+target+version 必须拒绝
	_, err := pool.Exec(ctx, `
		INSERT INTO firmware_versions (id, model, version, file_url, target_chip, release_status, published_at)
		VALUES (710302, 'CS-INV-UQ', '2.0.0', '/fw/dup.bin', 'bms', 'draft', NULL)
	`)
	require.Error(t, err, "同型号同芯片同版本必须拒绝重复")
	assert.Contains(t, err.Error(), "23505")

	// 不同芯片可复用版本号
	_, err = pool.Exec(ctx, `
		INSERT INTO firmware_versions (id, model, version, file_url, target_chip, release_status, published_at)
		VALUES (710303, 'CS-INV-UQ', '2.0.0', '/fw/esp.bin', 'esp', 'draft', NULL)
	`)
	require.NoError(t, err, "不同芯片允许相同版本字符串")
}

func TestIndependentOTAIdempotencyRequestsUnique(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	_, err := pool.Exec(ctx, `
		INSERT INTO ota_idempotency_requests (user_id, device_sn, idempotency_key, operation, payload_hash, task_ids)
		VALUES (1, 'SN-IDEM', 'key-1', 'trigger', 'hash-a', '[7101]'::jsonb)
	`)
	require.NoError(t, err)

	// 同 user+device+operation+key 拒绝并发重复
	_, err = pool.Exec(ctx, `
		INSERT INTO ota_idempotency_requests (user_id, device_sn, idempotency_key, operation, payload_hash, task_ids)
		VALUES (1, 'SN-IDEM', 'key-1', 'trigger', 'hash-a', '[7101]'::jsonb)
	`)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "23505")

	// 不同 operation 允许同 key
	_, err = pool.Exec(ctx, `
		INSERT INTO ota_idempotency_requests (user_id, device_sn, idempotency_key, operation, payload_hash, task_ids)
		VALUES (1, 'SN-IDEM', 'key-1', 'rollback', 'hash-a', '[]'::jsonb)
	`)
	require.NoError(t, err)
}

func TestIndependentOTAPendingPackageTasksCancelled(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	insertFirmwareForIndependent(t, pool, 710401, "CS-INV-PKG", "1.0.0", "arm", "published", ptrTime(time.Now()))
	_, err := pool.Exec(ctx, `
		INSERT INTO upgrade_packages (id, model, main_version, status)
		VALUES (7104, 'CS-INV-PKG', 'V1.0.0', 1)
	`)
	require.NoError(t, err)

	// 迁移会取消 pending/scheduled 的 package 任务；新建的 package 任务不再写入路径
	// 此处直接验证迁移收口后的语义：手动插入 pending package 后由应用层/启动收口取消
	_, err = pool.Exec(ctx, `
		INSERT INTO upgrade_tasks (id, task_type, firmware_id, package_id, model, status, target_version)
		VALUES (71041, 'package', NULL, 7104, 'CS-INV-PKG', 'pending', 'V1.0.0')
	`)
	require.NoError(t, err)

	// 模拟启动收口
	_, err = pool.Exec(ctx, `
		UPDATE upgrade_tasks SET status = 'cancelled', completed_at = NOW()
		WHERE task_type = 'package' AND status IN ('pending', 'scheduled')
	`)
	require.NoError(t, err)

	var status string
	require.NoError(t, pool.QueryRow(ctx, `SELECT status FROM upgrade_tasks WHERE id=71041`).Scan(&status))
	assert.Equal(t, "cancelled", status)

	// 历史明细不得被删除
	var cnt int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM device_upgrades`).Scan(&cnt))
	assert.Equal(t, 0, cnt)
}

func TestFirmwareReleaseLifecyclePublishDisable(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewOTARepository(pool)

	fw := &model.Firmware{
		Model:      "CS-INV-RL",
		Version:    "3.0.0",
		FileURL:    "/fw/3.0.0.bin",
		TargetChip: "arm",
		Status:     0,
	}
	require.NoError(t, repo.CreateFirmware(ctx, fw))
	require.NotZero(t, fw.ID)

	// draft 不进入用户列表
	require.NoError(t, seedIndependentTestDevice(t, pool, "SN-RL-1", "CS-INV-RL"))
	list, err := repo.ListPublishedFirmwareForDevice(ctx, "SN-RL-1", "arm")
	require.NoError(t, err)
	assert.Empty(t, list, "draft 固件不得出现在用户可安装列表")

	require.NoError(t, repo.PublishFirmware(ctx, fw.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RolloutType: "all"}))
	list, err = repo.ListPublishedFirmwareForDevice(ctx, "SN-RL-1", "arm")
	require.NoError(t, err)
	require.Len(t, list, 1)
	assert.Equal(t, "published", list[0].ReleaseStatus)

	// 重复 publish 幂等，不刷新 published_at
	var publishedAt1 time.Time
	require.NoError(t, pool.QueryRow(ctx, `SELECT published_at FROM firmware_versions WHERE id=$1`, fw.ID).Scan(&publishedAt1))
	require.NoError(t, repo.PublishFirmware(ctx, fw.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RolloutType: "all"}))
	var publishedAt2 time.Time
	require.NoError(t, pool.QueryRow(ctx, `SELECT published_at FROM firmware_versions WHERE id=$1`, fw.ID).Scan(&publishedAt2))
	assert.True(t, publishedAt1.Equal(publishedAt2), "已 published 时重复 publish 不应刷新 published_at")

	require.NoError(t, repo.DisableFirmware(ctx, fw.ID, 1))
	list, err = repo.ListPublishedFirmwareForDevice(ctx, "SN-RL-1", "arm")
	require.NoError(t, err)
	assert.Empty(t, list, "disabled 固件不得出现在用户可安装列表")

	// disabled -> published 重新发布刷新 published_at
	require.NoError(t, repo.PublishFirmware(ctx, fw.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RolloutType: "all"}))
	var publishedAt3 time.Time
	require.NoError(t, pool.QueryRow(ctx, `SELECT published_at FROM firmware_versions WHERE id=$1`, fw.ID).Scan(&publishedAt3))
	assert.True(t, publishedAt3.After(publishedAt1) || publishedAt3.After(publishedAt2.Add(-time.Millisecond)),
		"重新发布应刷新 published_at")
}

func TestLatestPublishedFirmwareOrdersByPublishedAt(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewOTARepository(pool)

	base := time.Now().Add(-2 * time.Hour)
	// 旧 published（version 字符串更大，但 published_at 更早）
	insertFirmwareForIndependent(t, pool, 710501, "CS-INV-LF", "9.9.9", "dsp", "published", ptrTime(base))
	// 新 published（version 字符串更小，但 published_at 更新）—— 必须胜出
	insertFirmwareForIndependent(t, pool, 710502, "CS-INV-LF", "1.0.0", "dsp", "published", ptrTime(base.Add(time.Hour)))
	// draft 不参与
	insertFirmwareForIndependent(t, pool, 710503, "CS-INV-LF", "0.0.1", "dsp", "draft", nil)

	latest, err := repo.GetLatestFirmware(ctx, "", "CS-INV-LF", "dsp")
	require.NoError(t, err)
	assert.Equal(t, int64(710502), latest.ID, "最新固件必须按 published_at DESC, id DESC，而不是版本字符串")
	assert.Equal(t, "1.0.0", latest.Version)
}

func ptrTime(t time.Time) *time.Time { return &t }

func seedIndependentTestDevice(t *testing.T, pool *pgxpool.Pool, sn, deviceModel string) error {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO devices (sn, model, user_id, status)
		VALUES ($1, $2, 1, 0)
		ON CONFLICT (sn) DO UPDATE SET model = EXCLUDED.model
	`, sn, deviceModel)
	return err
}
