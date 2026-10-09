//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
)

func TestDebugStopServiceRetryAndDelayedACK(t *testing.T) {
	pool := overviewTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `INSERT INTO users(id,phone,password_hash,status) VALUES(99500,'debug-service-test','hash',1);
        INSERT INTO devices(sn,model,user_id,status) VALUES('DEBUG-SERVICE','TEST',99500,1)`)
	require.NoError(t, err)
	repo := repository.NewDeviceRepository(pool, nil)
	sess := &model.DeviceDebugSession{DeviceSN: "DEBUG-SERVICE", RequestID: "service-retry", Status: model.DebugSessionActive,
		IntervalSeconds: 5, DurationSeconds: 3600, StartedAt: time.Now().Add(-time.Minute), ExpiresAt: time.Now().Add(time.Hour),
		RequestedBy: 99500, Source: model.DebugSourceApp, StartTaskID: "11111111-1111-4111-8111-111111111111"}
	require.NoError(t, repo.CreateDebugSession(ctx, sess))
	commands := make(chan map[string]any, 4)
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			w.WriteHeader(400)
			return
		}
		commands <- body
		if calls.Add(1) == 1 {
			w.WriteHeader(503)
			return
		}
		w.WriteHeader(200)
	}))
	defer server.Close()
	debug := service.NewDeviceDebugService(repo, nil, server.URL, "")
	_, err = debug.StopSession(ctx, 99500, true, "DEBUG-SERVICE", sess.ID)
	require.Error(t, err, "send failure is surfaced to App so close is retryable")
	first := <-commands
	stopped, err := debug.StopSession(ctx, 99500, true, "DEBUG-SERVICE", sess.ID)
	require.NoError(t, err)
	second := <-commands
	require.Equal(t, first["task_id"], second["task_id"])
	require.Equal(t, []any{float64(0), float64(5), float64(0)}, second["args"])
	require.Equal(t, model.DebugSessionStopping, stopped.Status)
	debug.HandleCommandResult(ctx, sess.StartTaskID, "success", "")
	pending, err := repo.GetDebugSessionByID(ctx, "DEBUG-SERVICE", sess.ID)
	require.NoError(t, err)
	require.Equal(t, model.DebugSessionStopping, pending.Status, "late start ACK cannot undo stop")
	debug.HandleCommandResult(ctx, first["task_id"].(string), "success", "")
	stopped, err = debug.StopSession(ctx, 99500, true, "DEBUG-SERVICE", sess.ID)
	require.NoError(t, err)
	require.Equal(t, model.DebugSessionStopped, stopped.Status)
	require.Equal(t, int32(2), calls.Load(), "terminal stop is idempotent")
	next, conflict, err := debug.StartSession(ctx, 99500, true, "DEBUG-SERVICE", 300, "after-reboot", model.DebugSourceApp)
	require.NoError(t, err)
	require.False(t, conflict)
	require.NotEqual(t, sess.ID, next.ID)
}
