//go:build integration

package repository

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/require"
)

func TestOTAOfflineDeliverySurvivesReconnectAndRestart(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,status) VALUES ('offline','MODEL',0)`)
	fw := seedHardwareFirmware(t, pool, "esp", "2.0", nil, true)
	hardwareExec(t, pool, `INSERT INTO upgrade_tasks(id,status,execute_mode,updated_at) VALUES (1,'running','immediate',NOW()-INTERVAL '2 hours')`)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(id,device_sn,firmware_id,task_id,target_chip,status) VALUES (1,'offline',$1,1,'esp','pending')`, fw.ID)
	hardwareExec(t, pool, `UPDATE device_upgrades SET firmware_version='2.0'`)
	repo := NewOTARepository(pool)
	sns, err := repo.ListPendingDeliveryDevices(ctx)
	require.NoError(t, err)
	require.Empty(t, sns)
	claimed, err := repo.ClaimUpgradeDelivery(ctx, 1, "offline", 0)
	require.NoError(t, err)
	require.False(t, claimed)
	n, err := repo.MarkTimedOutUpgradeTasks(ctx, 30*time.Minute, "timeout")
	require.NoError(t, err)
	require.Zero(t, n, "a device that has never received a command must wait while offline")

	// Recreate the repository to model a server restart, then bring the device
	// online without sending the special MQTT online event used by the old queue.
	repo = NewOTARepository(pool)
	hardwareExec(t, pool, `UPDATE devices SET status=2 WHERE sn='offline'`)
	sns, err = repo.ListPendingDeliveryDevices(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"offline"}, sns)
	du, _, err := repo.GetPendingUpgradeForDevice(ctx, "offline")
	require.NoError(t, err)
	require.EqualValues(t, 1, du.ID)
	require.NotNil(t, du.TaskID)
	require.EqualValues(t, 1, *du.TaskID)
	claimed, err = repo.ClaimUpgradeDelivery(ctx, du.ID, "offline", 0)
	require.NoError(t, err)
	require.True(t, claimed)
	n, err = repo.MarkTimedOutUpgradeTasks(ctx, 30*time.Minute, "timeout")
	require.NoError(t, err)
	require.Zero(t, n, "first delivery starts a fresh acknowledgement timeout")
	claimed, err = repo.ClaimUpgradeDelivery(ctx, du.ID, "offline", 0)
	require.NoError(t, err)
	require.False(t, claimed, "repeated scans must not flood the device")

	// A lost MQTT publish/ACK is retried with the same persistent upgrade ID.
	hardwareExec(t, pool, `UPDATE device_upgrades SET last_dispatched_at=NOW()-INTERVAL '2 minutes' WHERE id=1`)
	claimed, err = repo.ClaimUpgradeDelivery(ctx, 1, "offline", 0)
	require.NoError(t, err)
	require.True(t, claimed)
	hardwareExec(t, pool, `UPDATE upgrade_tasks SET updated_at=NOW()-INTERVAL '2 hours' WHERE id=1`)
	n, err = repo.MarkTimedOutUpgradeTasks(ctx, 30*time.Minute, "timeout")
	require.NoError(t, err)
	require.EqualValues(t, 1, n, "a dispatched command still has the normal timeout")
}

func TestOTADeliveryMigrationReplayAndRollback(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	hardwareExec(t, pool, `INSERT INTO devices(sn,model) VALUES ('migration','MODEL')`)
	fw := seedHardwareFirmware(t, pool, "esp", "2.0", nil, true)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(device_sn,firmware_id,target_chip,status) VALUES ('migration',$1,'esp','pending')`, fw.ID)
	for _, direction := range []string{"up", "down", "down", "up", "up"} {
		data, err := os.ReadFile(filepath.Join("..", "..", "..", "database", "migrations", "133_ota_offline_delivery."+direction+".sql"))
		require.NoError(t, err)
		hardwareExec(t, pool, string(data))
	}
	var count int
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT COUNT(*) FROM device_upgrades WHERE device_sn='migration' AND last_dispatched_at IS NULL`).Scan(&count))
	require.Equal(t, 1, count, "migration replay must preserve pending tasks")
}

func TestOTARetryOfflineStartsNewDeliveryAttempt(t *testing.T) {
	for _, byTask := range []bool{true, false} {
		name := "firmware"
		if byTask {
			name = "task"
		}
		t.Run(name, func(t *testing.T) {
			pool := setupOTAHardwareDB(t, true)
			ctx := context.Background()
			hardwareExec(t, pool, `INSERT INTO devices(sn,model,status) VALUES ('retry-offline','MODEL',0)`)
			fw := seedHardwareFirmware(t, pool, "esp", "2.0", nil, true)
			hardwareExec(t, pool, `INSERT INTO upgrade_tasks(id,status,execute_mode,updated_at) VALUES (1,'running','immediate',NOW()-INTERVAL '2 hours')`)
			hardwareExec(t, pool, `INSERT INTO device_upgrades(id,device_sn,firmware_id,task_id,target_chip,status,last_dispatched_at)
 VALUES (1,'retry-offline',$1,1,'esp','failed',NOW()-INTERVAL '2 hours')`, fw.ID)
			repo := NewOTARepository(pool)
			if byTask {
				require.NoError(t, repo.RetryFailedUpgradesByTask(ctx, 1))
			} else {
				require.NoError(t, repo.RetryFailedUpgrades(ctx, fw.ID, []string{"retry-offline"}))
			}
			n, err := repo.MarkTimedOutUpgradeTasks(ctx, 30*time.Minute, "timeout")
			require.NoError(t, err)
			require.Zero(t, n, "an offline retry must wait for its first delivery regardless of the previous attempt")
			claimed, err := repo.ClaimUpgradeDelivery(ctx, 1, "retry-offline", 1)
			require.NoError(t, err)
			require.False(t, claimed)
			hardwareExec(t, pool, `UPDATE devices SET status=1 WHERE sn='retry-offline'`)
			// A delayed sender still holding the previous attempt must not claim
			// this retry's pending row or transmit an already consumed task ID.
			staleClaimed, staleErr := repo.ClaimUpgradeDelivery(ctx, 1, "retry-offline", 0)
			require.NoError(t, staleErr)
			require.False(t, staleClaimed)
			claimed, err = repo.ClaimUpgradeDelivery(ctx, 1, "retry-offline", 1)
			require.NoError(t, err)
			require.True(t, claimed)
			n, err = repo.MarkTimedOutUpgradeTasks(ctx, 30*time.Minute, "timeout")
			require.NoError(t, err)
			require.Zero(t, n, "the retried attempt starts a fresh acknowledgement timeout on reconnect")
		})
	}
}

func TestOTATaskRepushReturnsCurrentAttempt(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `CREATE UNIQUE INDEX uq_retry_task_target ON device_upgrades(task_id,device_sn,target_chip) WHERE task_id IS NOT NULL`)
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,status) VALUES ('repush','MODEL',1)`)
	fw := seedHardwareFirmware(t, pool, "dsp", "1.1.50", nil, true)
	hardwareExec(t, pool, `INSERT INTO upgrade_tasks(id,status,execute_mode) VALUES (1,'running','immediate')`)
	taskID := int64(1)
	repo := NewOTARepository(pool)
	du := &model.DeviceUpgrade{DeviceSN: "repush", FirmwareID: fw.ID, FirmwareVersion: "1.1.50", TargetChip: "dsp", Status: "failed", TaskID: &taskID}
	require.NoError(t, repo.UpsertDeviceUpgradeWithTask(ctx, du))
	hardwareExec(t, pool, `UPDATE device_upgrades SET last_dispatched_at=NOW()-INTERVAL '2 hours' WHERE id=$1`, du.ID)
	repush := &model.DeviceUpgrade{DeviceSN: "repush", FirmwareID: fw.ID, FirmwareVersion: "1.1.50", TargetChip: "dsp", Status: "pending", TaskID: &taskID}
	require.NoError(t, repo.UpsertDeviceUpgradeWithTask(ctx, repush))
	require.Equal(t, du.ID, repush.ID)
	require.Equal(t, 1, repush.RetryCount, "the immediate sender must use the persisted attempt counter")
	claimed, err := repo.ClaimUpgradeDelivery(ctx, repush.ID, "repush", repush.RetryCount)
	require.NoError(t, err)
	require.True(t, claimed, "repush must clear the previous attempt's delivery throttle")
}

func TestOTADeliveryGuardsAndConcurrentClaim(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model) VALUES ('online','MODEL')`)
	fw := seedHardwareFirmware(t, pool, "esp", "2.0", nil, true)
	hardwareExec(t, pool, `INSERT INTO upgrade_tasks(id,status,execute_mode) VALUES
 (1,'pending','manual'),(2,'scheduled','scheduled'),(3,'cancelled','immediate'),(4,'running','immediate')`)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(id,device_sn,firmware_id,task_id,target_chip,status) VALUES
 (1,'online',$1,1,'esp','pending'),(2,'online',$1,2,'esp','pending'),(3,'online',$1,3,'esp','pending'),
 (4,'online',$1,4,'esp','pending'),(5,'online',$1,4,'esp','pending')`, fw.ID)
	hardwareExec(t, pool, `UPDATE device_upgrades SET firmware_version='2.0'`)
	repo := NewOTARepository(pool)
	du, _, err := repo.GetPendingUpgradeForDevice(ctx, "online")
	require.NoError(t, err)
	require.EqualValues(t, 4, du.ID, "skip manual, scheduled and cancelled tasks")
	for _, id := range []int64{1, 2, 3, 5} {
		ok, err := repo.ClaimUpgradeDelivery(ctx, id, "online", 0)
		require.NoError(t, err)
		require.False(t, ok)
	}
	var wg sync.WaitGroup
	results := make(chan bool, 12)
	errors := make(chan error, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ok, err := repo.ClaimUpgradeDelivery(ctx, 4, "online", 0)
			results <- ok
			errors <- err
		}()
	}
	wg.Wait()
	close(results)
	close(errors)
	for err := range errors {
		require.NoError(t, err)
	}
	count := 0
	for ok := range results {
		if ok {
			count++
		}
	}
	require.Equal(t, 1, count)
	hardwareExec(t, pool, `UPDATE device_upgrades SET status='downloading' WHERE id=4`)
	_, _, err = repo.GetPendingUpgradeForDevice(ctx, "online")
	require.ErrorIs(t, err, pgx.ErrNoRows, "another module must wait for the active download")
	hardwareExec(t, pool, `UPDATE device_upgrades SET status='success' WHERE id=4`)
	du, _, err = repo.GetPendingUpgradeForDevice(ctx, "online")
	require.NoError(t, err)
	require.EqualValues(t, 5, du.ID)
	hardwareExec(t, pool, `UPDATE upgrade_tasks SET status='cancelled' WHERE id=4`)
	ok, err := repo.ClaimUpgradeDelivery(ctx, 5, "online", 0)
	require.NoError(t, err)
	require.False(t, ok, "cancellation after selection must prevent delivery")
}

// TestCancelTaskReleasesDeviceDeliveryQueue covers the production stall where a
// task was cancelled while its record was still downloading/upgrading: the
// orphaned in-flight record kept blocking every later pending upgrade of the
// same device until the record timeout fired.
func TestCancelTaskReleasesDeviceDeliveryQueue(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	ctx := context.Background()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,status) VALUES ('cancel-release','MODEL',1)`)
	dsp := seedHardwareFirmware(t, pool, "dsp", "1.1.50", nil, true)
	esp := seedHardwareFirmware(t, pool, "esp", "2.0", nil, true)
	hardwareExec(t, pool, `INSERT INTO upgrade_tasks(id,status,execute_mode,updated_at) VALUES (1,'running','immediate',NOW()),(2,'running','immediate',NOW())`)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(id,device_sn,firmware_id,task_id,target_chip,status) VALUES
 (1,'cancel-release',$1,1,'dsp','upgrading'),(2,'cancel-release',$2,2,'esp','pending')`, dsp.ID, esp.ID)
	repo := NewOTARepository(pool)

	// The in-flight DSP record blocks the pending ESP delivery for this device.
	sns, err := repo.ListPendingDeliveryDevices(ctx)
	require.NoError(t, err)
	require.Empty(t, sns)
	claimed, err := repo.ClaimUpgradeDelivery(ctx, 2, "cancel-release", 0)
	require.NoError(t, err)
	require.False(t, claimed)

	// Cancelling the owning task must cancel the in-flight record too so the
	// queue is released immediately instead of after the record timeout.
	require.NoError(t, repo.CancelUpgradesByTask(ctx, 1))
	var status string
	require.NoError(t, pool.QueryRow(ctx, `SELECT status FROM device_upgrades WHERE id=1`).Scan(&status))
	require.Equal(t, "cancelled", status, "cancelling a task must release its in-flight record")

	sns, err = repo.ListPendingDeliveryDevices(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"cancel-release"}, sns)
	claimed, err = repo.ClaimUpgradeDelivery(ctx, 2, "cancel-release", 0)
	require.NoError(t, err)
	require.True(t, claimed)
}
