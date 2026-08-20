//go:build integration

package repository

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// setupCommandTestDB 为命令生命周期测试创建独立临时库并加载 squash schema
// （device_commands / device_cmd_logs 均来自 schema.sql 基线）。
func setupCommandTestDB(t *testing.T) (*pgxpool.Pool, func()) {
	t.Helper()
	ctx := context.Background()
	host := envOrFallback("TEST_DB_HOST", "localhost")
	port := envOrFallback("TEST_DB_PORT", "15432")
	user := envOrFallback("TEST_DB_USER", "testuser")
	password := envOrFallback("TEST_DB_PASSWORD", "testpass")
	admin, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable", user, password, host, port))
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))

	dbName := fmt.Sprintf("cmd_lifecycle_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err)
	pool, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, password, host, port, dbName))
	require.NoError(t, err)

	repoRoot := filepath.Clean(filepath.Join("..", "..", ".."))
	schemaBytes, err := os.ReadFile(filepath.Join(repoRoot, "database", "schema.sql"))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(schemaBytes))
	require.NoError(t, err, "load schema.sql")

	return pool, func() {
		pool.Close()
		_, _ = admin.Exec(ctx, `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1`, dbName)
		_, dropErr := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+dbName)
		assert.NoError(t, dropErr)
		admin.Close()
	}
}

// TestLegacyStatusParamSQLPatternFailsWith42P08 回归防护：
// 历史写法将同一参数同时用于 SET status=$n（推断 varchar(20)）与
// CASE WHEN $n='literal'（推断 text），服务器参数类型推断不一致必然报
// SQLSTATE 42P08。该断言固化根因，防止未来把参数布局改回单一 $n 复用。
func TestLegacyStatusParamSQLPatternFailsWith42P08(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	taskID := uuid.NewString()
	seedCommand(t, pool, taskID)

	_, err := pool.Exec(ctx, `
		UPDATE device_commands SET status=$2,
			sent_at=CASE WHEN $2='sent' THEN NOW() ELSE sent_at END
		WHERE task_id=$1::uuid
	`, taskID, "sent")
	require.Error(t, err, "legacy single-param reuse pattern must be rejected by PostgreSQL")
	assert.Contains(t, err.Error(), "42P08")
}

// TestUpdateCommandLogStatusLifecycle 覆盖 InsertCommandLog →
// UpdateCommandLogStatus 的完整状态机推进（sent/queued/failed），
// 防止静默失败（42P08 曾被调用方 `_ =` 吞掉，状态永远停在 pending）。
func TestUpdateCommandLogStatusLifecycle(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	taskID := uuid.NewString()
	require.NoError(t, repo.InsertCommandLog(ctx, "SN-TEST-001", taskID, "set_control", `{"batch_charge_soc":80}`))
	assertCommandStatus(t, pool, taskID, "pending")

	// 设备服务器确认接收 → sent
	require.NoError(t, repo.UpdateCommandLogStatus(ctx, taskID, "sent", "命令已发送"))
	assertCommandStatus(t, pool, taskID, "sent", "sent_at")

	// 离线排队场景 → queued（补验 queued_at）
	require.NoError(t, repo.UpdateCommandLogStatus(ctx, taskID, "queued", "设备离线，命令已排队"))
	assertCommandStatus(t, pool, taskID, "queued", "queued_at", "sent_at")

	// 终态 → failed（补验 completed_at）
	require.NoError(t, repo.UpdateCommandLogStatus(ctx, taskID, "failed", "发送失败"))
	assertCommandStatus(t, pool, taskID, "failed", "completed_at", "queued_at", "sent_at")
}

// TestDeviceCmdResultLifecycleSQL 验证 internal_handler.DeviceCmdResult 内联
// UPDATE 的参数布局（状态时间戳使用独立布尔参数，避免 42P08）。
// SQL 文本须与 internal_handler.go DeviceCmdResult 保持同步。
func TestDeviceCmdResultLifecycleSQL(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()

	t.Run("acknowledged sets acknowledged_at only", func(t *testing.T) {
		taskID := uuid.NewString()
		seedCommand(t, pool, taskID)
		status := "acknowledged"
		_, err := pool.Exec(ctx, `
			UPDATE device_commands SET status=$2,result_code=COALESCE(NULLIF($3,''),result_code),
				result_message=$4,response_data=COALESCE($5::jsonb,'[]'::jsonb),
				acknowledged_at=CASE WHEN $6 THEN NOW() ELSE acknowledged_at END,
				completed_at=CASE WHEN $7 THEN NOW() ELSE completed_at END
			WHERE task_id::text=$1
		`, taskID, status, "", "ack ok", []byte(`[]`), status == "acknowledged", status == "success" || status == "failed")
		require.NoError(t, err)
		assertCommandStatus(t, pool, taskID, status, "acknowledged_at")
	})

	t.Run("success sets completed_at", func(t *testing.T) {
		taskID := uuid.NewString()
		seedCommand(t, pool, taskID)
		status := "success"
		_, err := pool.Exec(ctx, `
			UPDATE device_commands SET status=$2,result_code=COALESCE(NULLIF($3,''),result_code),
				result_message=$4,response_data=COALESCE($5::jsonb,'[]'::jsonb),
				acknowledged_at=CASE WHEN $6 THEN NOW() ELSE acknowledged_at END,
				completed_at=CASE WHEN $7 THEN NOW() ELSE completed_at END
			WHERE task_id::text=$1
		`, taskID, status, "0", "done", []byte(`{"batch_charge_soc":80}`), status == "acknowledged", status == "success" || status == "failed")
		require.NoError(t, err)
		assertCommandStatus(t, pool, taskID, status, "completed_at")

		var resultCode string
		var responseData []byte
		require.NoError(t, pool.QueryRow(ctx,
			`SELECT result_code, response_data FROM device_commands WHERE task_id=$1::uuid`, taskID,
		).Scan(&resultCode, &responseData))
		assert.Equal(t, "0", resultCode)
		assert.JSONEq(t, `{"batch_charge_soc":80}`, string(responseData))
	})

	t.Run("non-uuid task_id updates zero rows without error", func(t *testing.T) {
		tag, err := pool.Exec(ctx, `
			UPDATE device_commands SET status=$2,result_code=COALESCE(NULLIF($3,''),result_code),
				result_message=$4,response_data=COALESCE($5::jsonb,'[]'::jsonb),
				acknowledged_at=CASE WHEN $6 THEN NOW() ELSE acknowledged_at END,
				completed_at=CASE WHEN $7 THEN NOW() ELSE completed_at END
			WHERE task_id::text=$1
		`, "cmd_1787135703558894092", "success", "", "", []byte(`[]`), false, true)
		require.NoError(t, err)
		assert.EqualValues(t, 0, tag.RowsAffected())
	})
}

func seedCommand(t *testing.T, pool *pgxpool.Pool, taskID string) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO device_commands(task_id,device_sn,command_code,requested_args,status,timeout_at)
		VALUES($1::uuid,$2,$3,$4::jsonb,'pending',NOW()+INTERVAL '30 seconds')
		ON CONFLICT(task_id) DO NOTHING
	`, taskID, "SN-TEST-001", "set_control", `[]`)
	require.NoError(t, err)
}

// assertCommandStatus 断言当前状态以及指定的时间戳列已被写入，
// 其余时间戳列保持 NULL。
func assertCommandStatus(t *testing.T, pool *pgxpool.Pool, taskID, wantStatus string, wantSetCols ...string) {
	t.Helper()
	var status string
	var acknowledgedAt, completedAt, queuedAt, sentAt *time.Time
	require.NoError(t, pool.QueryRow(context.Background(), `
		SELECT status, acknowledged_at, completed_at, queued_at, sent_at
		FROM device_commands WHERE task_id=$1::uuid
	`, taskID).Scan(&status, &acknowledgedAt, &completedAt, &queuedAt, &sentAt))
	assert.Equal(t, wantStatus, status)

	wantSet := make(map[string]bool, len(wantSetCols))
	for _, col := range wantSetCols {
		wantSet[col] = true
	}
	for col, val := range map[string]*time.Time{
		"acknowledged_at": acknowledgedAt,
		"completed_at":    completedAt,
		"queued_at":       queuedAt,
		"sent_at":         sentAt,
	} {
		if wantSet[col] {
			assert.NotNil(t, val, "%s must be set for status %s", col, wantStatus)
		} else {
			assert.Nil(t, val, "%s must stay NULL for status %s", col, wantStatus)
		}
	}
}
