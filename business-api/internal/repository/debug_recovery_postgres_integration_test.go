//go:build integration

package repository

import (
	"context"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"testing"
	"time"
)

func TestDebugRecoveryRetriesExpiryAndNormalHeartbeat(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)
	sess := &model.DeviceDebugSession{DeviceSN: "DEBUG-RECOVERY", RequestID: "recovery", Status: model.DebugSessionActive,
		IntervalSeconds: 5, DurationSeconds: 3600, StartedAt: time.Now().Add(-time.Minute), ExpiresAt: time.Now().Add(time.Hour), RequestedBy: 1, Source: "app"}
	require.NoError(t, repo.CreateDebugSession(ctx, sess))
	first, err := repo.BeginDebugSessionStop(ctx, sess.ID, "stable-stop")
	require.NoError(t, err)
	retry, err := repo.BeginDebugSessionStop(ctx, sess.ID, "discarded-retry")
	require.NoError(t, err)
	require.Equal(t, first.StopTaskID, retry.StopTaskID)
	ack, err := repo.GetDebugSessionByTaskID(ctx, "stable-stop")
	require.NoError(t, err)
	require.Equal(t, sess.ID, ack.ID)
	_, err = pool.Exec(ctx, `UPDATE device_debug_sessions SET expires_at=NOW()-INTERVAL '1 second' WHERE id=$1`, sess.ID)
	require.NoError(t, err)
	expired, err := repo.ExpireDebugSessions(ctx)
	require.NoError(t, err)
	require.Len(t, expired, 1)
	require.Equal(t, model.DebugSessionStopping, expired[0].Status, "coordinator sees pre-expiry state and sends fallback stop")
	sess.RequestID = "restarted"
	sess.Status = model.DebugSessionStarting
	sess.ExpiresAt = time.Now().Add(time.Hour)
	require.NoError(t, repo.CreateDebugSession(ctx, sess))
	_, err = pool.Exec(ctx, `INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,received_at,data_hash)
 VALUES('DEBUG-RECOVERY',3,1,NOW()-INTERVAL '50 seconds',NOW()-INTERVAL '50 seconds','one')`)
	require.NoError(t, err)
	n, err := repo.RefreshDebugSampleTimes(ctx)
	require.NoError(t, err)
	require.Zero(t, n, "one normal heartbeat does not confirm debug mode")
	_, err = pool.Exec(ctx, `INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,received_at,data_hash)
 VALUES('DEBUG-RECOVERY',3,2,NOW()-INTERVAL '45 seconds',NOW()-INTERVAL '45 seconds','two')`)
	require.NoError(t, err)
	n, err = repo.RefreshDebugSampleTimes(ctx)
	require.NoError(t, err)
	require.Equal(t, 1, n, "fast samples confirm debug cadence")
	require.NoError(t, repo.FinalizeDebugSession(ctx, sess.ID, []string{model.DebugSessionActive}, model.DebugSessionInterrupted, "power loss"))
	sess.RequestID = "after-interruption"
	sess.Status = model.DebugSessionStarting
	require.NoError(t, repo.CreateDebugSession(ctx, sess), "interrupted session does not occupy device")
}
