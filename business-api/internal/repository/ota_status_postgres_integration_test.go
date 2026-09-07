//go:build integration

package repository

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestListDeviceUpgradesBySNAndTaskIDSelectsAllChipsForRequestedTask protects the App OTA
// detail contract: task_id identifies an upgrade_tasks row, so opening an older
// task must not silently display the device's most recently updated task.
func TestListDeviceUpgradesBySNAndTaskIDSelectsAllChipsForRequestedTask(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	const (
		deviceSN      = "OTA-STATUS-SN-001"
		otherSN       = "OTA-STATUS-SN-002"
		requestedTask = int64(980001)
		latestTask    = int64(980002)
	)

	seedOTAStatusTask(t, pool, requestedTask, "V1.0.0", "completed")
	seedOTAStatusTask(t, pool, latestTask, "V2.0.0", "running")
	seedOTAStatusUpgrade(t, pool, deviceSN, 981001, requestedTask, "arm", "1.0.0", "success", 100, time.Now().Add(-time.Hour))
	seedOTAStatusUpgrade(t, pool, deviceSN, 981004, requestedTask, "esp", "1.0.1", "pending", 0, time.Now().Add(-time.Minute))
	seedOTAStatusUpgrade(t, pool, deviceSN, 981002, latestTask, "arm", "2.0.0", "upgrading", 73, time.Now())
	seedOTAStatusUpgrade(t, pool, otherSN, 981003, requestedTask, "arm", "1.0.2", "failed", 12, time.Now().Add(time.Minute))

	repo := NewOTARepository(pool)
	got, err := repo.ListDeviceUpgradesBySNAndTaskID(ctx, deviceSN, requestedTask)
	require.NoError(t, err)
	require.Len(t, got, 2)
	assert.Equal(t, deviceSN, got[0].DeviceSN)
	assert.Equal(t, deviceSN, got[1].DeviceSN)
	for _, item := range got {
		require.NotNil(t, item.TaskID)
		assert.Equal(t, requestedTask, *item.TaskID)
	}
}

func TestListDeviceUpgradesBySNAndTaskIDDoesNotCrossDeviceBoundary(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	const taskID = int64(980101)
	seedOTAStatusTask(t, pool, taskID, "V3.0.0", "running")
	seedOTAStatusUpgrade(t, pool, "OTA-STATUS-OWNER", 981101, taskID, "arm", "3.0.0", "upgrading", 55, time.Now())

	repo := NewOTARepository(pool)
	got, err := repo.ListDeviceUpgradesBySNAndTaskID(ctx, "OTA-STATUS-STRANGER", taskID)
	require.NoError(t, err)
	assert.Empty(t, got)
}

func TestListDeviceUpgradesBySNAndTaskIDReturnsEmptyForUnknownTask(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()

	repo := NewOTARepository(pool)
	got, err := repo.ListDeviceUpgradesBySNAndTaskID(context.Background(), "OTA-STATUS-SN-404", 989999)
	require.NoError(t, err)
	assert.Empty(t, got)
}

func seedOTAStatusTask(t *testing.T, pool *pgxpool.Pool, taskID int64, targetVersion, status string) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO upgrade_tasks
			(id, name, task_type, model, target_version, status, execute_mode, total_devices)
		VALUES ($1, $2, 'package', 'CS-INV-TEST', $3, $4, 'immediate', 1)
	`, taskID, "OTA status task", targetVersion, status)
	require.NoError(t, err)
}

func seedOTAStatusUpgrade(t *testing.T, pool *pgxpool.Pool, deviceSN string, firmwareID, taskID int64, targetChip, version, status string, progress int, updatedAt time.Time) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO firmware_versions (id, model, version, file_url, target_chip, main_version)
		VALUES ($1, 'CS-INV-TEST', $2, $3, $4, $5)
	`, firmwareID, version, "/firmware/"+version+".bin", targetChip, "V"+version)
	require.NoError(t, err)

	_, err = pool.Exec(context.Background(), `
		INSERT INTO device_upgrades
			(device_sn, firmware_id, firmware_version, target_chip, status, progress, task_id, source, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'app', $8)
	`, deviceSN, firmwareID, version, targetChip, status, progress, taskID, updatedAt)
	require.NoError(t, err)
}
