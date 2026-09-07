//go:build integration

package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/repository"
)

// SendPreparedCommand 真库回归：命令审计日志（device_cmd_logs +
// device_commands 双写）随发送结果推进状态机（sent/queued/failed），
// 成功路径落期望控制态（device_control_state）与站内通知。
// 设备服务器用 httptest 假实现，X-Internal-Key 与请求体一并断言。

func mustDeviceRepo(t *testing.T, pool *pgxpool.Pool) *repository.DeviceRepository {
	t.Helper()
	return repository.NewDeviceRepository(pool, nil)
}

func mustModelRepo(t *testing.T, pool *pgxpool.Pool) *repository.ModelRepository {
	t.Helper()
	return repository.NewModelRepository(pool, nil)
}

func TestSendPreparedCommandSuccessWritesAuditAndDesiredState(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)

	var gotKey string
	var gotBody map[string]interface{}
	deviceSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("X-Internal-Key")
		require.Equal(t, "/api/v1/device/CTL-SN-001/command", r.URL.Path)
		require.NoError(t, json.NewDecoder(r.Body).Decode(&gotBody))
		w.WriteHeader(http.StatusOK)
	}))
	defer deviceSrv.Close()

	svc := NewDeviceService(mustDeviceRepo(t, pool), nil, mustModelRepo(t, pool), nil,
		deviceSrv.URL, "test-internal-key", pool)
	svc.limitChecker = nil
	svc.preconditionChecker = nil

	prepared, err := svc.ValidateAndPrepareCommand(context.Background(), 301, "CTL-SN-001",
		"set_output_priority", map[string]interface{}{"value": 1}, true)
	require.NoError(t, err)

	taskID, err := svc.SendPreparedCommand(context.Background(), "CTL-SN-001", prepared)
	require.NoError(t, err)
	assert.Equal(t, prepared.TaskID, taskID)
	assert.Equal(t, "test-internal-key", gotKey, "内部调用密钥必须随命令发送")
	assert.Equal(t, "set_output_priority", gotBody["cmd"])
	assert.Equal(t, float64(1), gotBody["v"], "V2 协议必须带版本标记")
	assert.NotNil(t, gotBody["args"])
	assert.NotNil(t, gotBody["expires_at"])

	// 审计日志双表状态推进到 sent
	var logStatus string
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT status FROM device_cmd_logs WHERE task_id=$1`, taskID).Scan(&logStatus))
	assert.Equal(t, "sent", logStatus)
	var status string
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT status FROM device_commands WHERE task_id=$1::uuid`, taskID).Scan(&status))
	assert.Equal(t, "sent", status)

	// 期望控制态落库（sync_status=pending，等待设备回报）
	var syncStatus string
	var desiredVersion int64
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT sync_status, desired_version FROM device_control_state WHERE device_sn=$1`, "CTL-SN-001").
		Scan(&syncStatus, &desiredVersion))
	assert.Equal(t, "pending", syncStatus)
	assert.GreaterOrEqual(t, desiredVersion, int64(1))
}

func TestSendPreparedCommandDeviceOfflineQueuesWithoutFailure(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)

	deviceSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer deviceSrv.Close()

	svc := NewDeviceService(mustDeviceRepo(t, pool), nil, mustModelRepo(t, pool), nil,
		deviceSrv.URL, "test-internal-key", pool)
	svc.limitChecker = nil
	svc.preconditionChecker = nil

	prepared, err := svc.ValidateAndPrepareCommand(context.Background(), 301, "CTL-SN-001",
		"set_output_priority", map[string]interface{}{"value": 1}, true)
	require.NoError(t, err)

	// 503 = 设备离线：返回 taskID（命令已排队）而非错误
	taskID, err := svc.SendPreparedCommand(context.Background(), "CTL-SN-001", prepared)
	require.NoError(t, err)
	assert.NotEmpty(t, taskID)

	var logStatus, result string
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT status, COALESCE(result,'') FROM device_cmd_logs WHERE task_id=$1`, taskID).
		Scan(&logStatus, &result))
	assert.Equal(t, "queued", logStatus)
	assert.Contains(t, result, "离线")
}

func TestSendPreparedCommandDeviceServerFailureMarksFailed(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)

	deviceSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer deviceSrv.Close()

	svc := NewDeviceService(mustDeviceRepo(t, pool), nil, mustModelRepo(t, pool), nil,
		deviceSrv.URL, "test-internal-key", pool)
	svc.limitChecker = nil
	svc.preconditionChecker = nil

	prepared, err := svc.ValidateAndPrepareCommand(context.Background(), 301, "CTL-SN-001",
		"set_output_priority", map[string]interface{}{"value": 1}, true)
	require.NoError(t, err)

	_, err = svc.SendPreparedCommand(context.Background(), "CTL-SN-001", prepared)
	require.Error(t, err)

	var logStatus string
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT status FROM device_cmd_logs WHERE task_id=$1`, prepared.TaskID).Scan(&logStatus))
	assert.Equal(t, "failed", logStatus, "设备服务器 5xx 时审计日志必须标记 failed")
}
