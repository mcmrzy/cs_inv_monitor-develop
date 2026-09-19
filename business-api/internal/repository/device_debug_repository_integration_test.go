//go:build integration

package repository

import (
	"context"
	"fmt"
	"testing"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestDebugSessionLifecycle 覆盖：创建 → 并发冲突（部分唯一索引）→
// 同 request_id 幂等 → 样本触达 → 停止 → 终态后可重新开启。
func TestDebugSessionLifecycle(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	sn := "DBG-SESS-1"
	expires := time.Now().UTC().Add(time.Hour)

	sess := &model.DeviceDebugSession{
		DeviceSN:        sn,
		RequestID:       "req-1",
		Status:          model.DebugSessionStarting,
		IntervalSeconds: 30,
		DurationSeconds: 3600,
		ExpiresAt:       expires,
		RequestedBy:     42,
		Source:          model.DebugSourceWeb,
	}
	require.NoError(t, repo.CreateDebugSession(ctx, sess))
	require.Positive(t, sess.ID)
	assert.Equal(t, model.DebugSessionStarting, sess.Status)

	// 同 request_id 幂等可查
	byReq, err := repo.GetDebugSessionByRequest(ctx, sn, "req-1")
	require.NoError(t, err)
	require.NotNil(t, byReq)
	assert.Equal(t, sess.ID, byReq.ID)

	// 占用中：第二个不同请求 → 冲突
	sess2 := *sess
	sess2.RequestID = "req-2"
	err = repo.CreateDebugSession(ctx, &sess2)
	require.ErrorIs(t, err, ErrDebugSessionConflict)

	// 占用中会话可见
	active, err := repo.GetActiveDebugSession(ctx, sn)
	require.NoError(t, err)
	require.NotNil(t, active)
	assert.Equal(t, sess.ID, active.ID)

	// 回执闭环：按 task_id 定位 + starting → active
	require.NoError(t, repo.UpdateDebugSessionStartTask(ctx, sess.ID, "task-start-1"))
	got, err := repo.GetDebugSessionByTaskID(ctx, "task-start-1")
	require.NoError(t, err)
	require.NotNil(t, got)
	require.NoError(t, repo.FinalizeDebugSession(ctx, sess.ID,
		[]string{model.DebugSessionStarting}, model.DebugSessionActive, ""))

	// 样本触达推进 last_sample_at（协调循环路径：RefreshDebugSampleTimes 直查遥测表，
	// 单测里直接落库模拟）
	ts := time.Now().UTC()
	require.NoError(t, execPool(ctx, pool,
		`UPDATE device_debug_sessions SET last_sample_at = $1 WHERE device_sn = $2`, ts, sn))
	touched, err := repo.GetDebugSessionByID(ctx, sn, sess.ID)
	require.NoError(t, err)
	require.NotNil(t, touched.LastSampleAt)
	assert.WithinDuration(t, ts, *touched.LastSampleAt, time.Second)

	// 停止：stopping → stopped
	require.NoError(t, repo.MarkDebugSessionStopping(ctx, sess.ID, "task-stop-1"))
	require.NoError(t, repo.FinalizeDebugSession(ctx, sess.ID,
		[]string{model.DebugSessionStopping}, model.DebugSessionStopped, ""))
	stopped, err := repo.GetDebugSessionByID(ctx, sn, sess.ID)
	require.NoError(t, err)
	assert.Equal(t, model.DebugSessionStopped, stopped.Status)
	require.NotNil(t, stopped.StoppedAt)

	// 终态后可重新开启
	sess3 := &model.DeviceDebugSession{
		DeviceSN: sn, RequestID: "req-3", Status: model.DebugSessionStarting,
		IntervalSeconds: 30, DurationSeconds: 3600, ExpiresAt: expires.Add(time.Hour),
		RequestedBy: 42, Source: model.DebugSourceApp,
	}
	require.NoError(t, repo.CreateDebugSession(ctx, sess3))
}

// TestDebugSessionReaping 覆盖协调循环的三个收口：starting 超时、active 中断、到期。
func TestDebugSessionReaping(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	now := time.Now().UTC()
	reqSeq := 0
	mk := func(sn string, status string, startedAt time.Time, expires time.Time) *model.DeviceDebugSession {
		reqSeq++
		s := &model.DeviceDebugSession{
			DeviceSN: sn, RequestID: fmt.Sprintf("r-%s-%d", sn, reqSeq), Status: status,
			IntervalSeconds: 30, DurationSeconds: 3600,
			StartedAt: startedAt, ExpiresAt: expires, RequestedBy: 1, Source: "web",
		}
		require.NoError(t, repo.CreateDebugSession(ctx, s))
		return s
	}

	stuck := mk("DBG-STUCK", model.DebugSessionStarting, now.Add(-2*time.Minute), now.Add(time.Hour))
	stale := mk("DBG-STALE", model.DebugSessionActive, now.Add(-10*time.Minute), now.Add(time.Hour))
	require.NoError(t, execPool(ctx, pool,
		`UPDATE device_debug_sessions SET last_sample_at = $1 WHERE device_sn = $2`, now.Add(-3*time.Minute), "DBG-STALE"))
	fresh := mk("DBG-FRESH", model.DebugSessionActive, now.Add(-10*time.Minute), now.Add(time.Hour))
	require.NoError(t, execPool(ctx, pool,
		`UPDATE device_debug_sessions SET last_sample_at = $1 WHERE device_sn = $2`, now.Add(-10*time.Second), "DBG-FRESH"))
	// 到期但样本新鲜（不会被中断收口抢先）：到期收口的专门用例
	expired := mk("DBG-EXPIRED", model.DebugSessionActive, now.Add(-10*time.Minute), now.Add(-time.Minute))
	require.NoError(t, execPool(ctx, pool,
		`UPDATE device_debug_sessions SET last_sample_at = $1 WHERE device_sn = $2`, now.Add(-10*time.Second), "DBG-EXPIRED"))

	// starting 超时（>90s）→ failed；其余不受影响
	reaps, err := repo.ReapStaleStartingSessions(ctx, 90*time.Second)
	require.NoError(t, err)
	assert.Len(t, reaps, 1)
	gotStuck, err := repo.GetDebugSessionByID(ctx, "DBG-STUCK", stuck.ID)
	require.NoError(t, err)
	assert.Equal(t, model.DebugSessionFailed, gotStuck.Status)

	// active 样本迟到（>75s）→ interrupted；新鲜样本（含过期会话）不受影响
	reaps, err = repo.ReapStaleActiveSessions(ctx, 75*time.Second)
	require.NoError(t, err)
	require.Len(t, reaps, 1)
	assert.Equal(t, "DBG-STALE", reaps[0].DeviceSN)
	gotStale, err := repo.GetDebugSessionByID(ctx, "DBG-STALE", stale.ID)
	require.NoError(t, err)
	assert.Equal(t, model.DebugSessionInterrupted, gotStale.Status)
	gotFresh, err := repo.GetDebugSessionByID(ctx, "DBG-FRESH", fresh.ID)
	require.NoError(t, err)
	assert.Equal(t, model.DebugSessionActive, gotFresh.Status)

	// 到期 → expired（此前 active 的行返回用于补发停止命令）
	reaps, err = repo.ExpireDebugSessions(ctx)
	require.NoError(t, err)
	require.Len(t, reaps, 1)
	assert.Equal(t, "DBG-EXPIRED", reaps[0].DeviceSN)
	gotExpired, err := repo.GetDebugSessionByID(ctx, "DBG-EXPIRED", expired.ID)
	require.NoError(t, err)
	assert.Equal(t, model.DebugSessionExpired, gotExpired.Status)

	// 到期后可重新开启
	re := mk("DBG-EXPIRED", model.DebugSessionStarting, now, now.Add(time.Hour))
	require.Positive(t, re.ID)
}

// TestDebugSamplesBoundedQuery 覆盖：白名单投影、SN 隔离、null 断线、游标增量分页、空结果非 nil。
func TestDebugSamplesBoundedQuery(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	now := time.Now().UTC()
	base := now.Add(-10 * time.Minute)
	// 6 行样本，间隔 30s，其中一行 battery 为 NULL（null 断线语义）
	for i := 0; i < 6; i++ {
		ts := base.Add(time.Duration(i*30) * time.Second)
		hash := "hash-" + ts.Format(time.RFC3339Nano)
		if i == 3 {
			require.NoError(t, execPool(ctx, pool, `
				INSERT INTO device_telemetry_3min
					(device_sn, protocol_version, sequence_no, event_time, data_hash, ac_voltage)
				VALUES ($1, 2, $2, $3, $4, $5)
			`, "DBG-SN", i, ts, hash, float64(220+i)))
			continue
		}
		require.NoError(t, execPool(ctx, pool, `
			INSERT INTO device_telemetry_3min
				(device_sn, protocol_version, sequence_no, event_time, data_hash, battery_voltage, ac_voltage)
			VALUES ($1, 2, $2, $3, $4, $5, $6)
		`, "DBG-SN", i, ts, hash, float64(51+i), float64(220+i)))
	}
	// 另一台设备的样本：必须被隔离
	require.NoError(t, execPool(ctx, pool, `
		INSERT INTO device_telemetry_3min
			(device_sn, protocol_version, sequence_no, event_time, data_hash, battery_voltage)
		VALUES ('DBG-OTHER', 2, 99, $1, 'hash-other', 99)
	`, base.Add(time.Minute)))

	from := base.Add(-time.Minute)
	to := now
	items, cursor, err := repo.GetDebugSamples(ctx, "DBG-SN", from, to, nil, "", 200)
	require.NoError(t, err)
	require.NotNil(t, items)
	require.Len(t, items, 6)
	assert.NotEmpty(t, cursor)
	assert.True(t, items[0].Time.Before(items[5].Time))
	require.NotNil(t, items[0].Metrics.BatteryVoltage)
	assert.InDelta(t, 51.0, *items[0].Metrics.BatteryVoltage, 0.001)
	require.NotNil(t, items[0].Metrics.ACVoltage)
	assert.InDelta(t, 220.0, *items[0].Metrics.ACVoltage, 0.001)
	// i==3 行 battery 为 NULL（断线），ac_voltage 有效
	assert.Nil(t, items[3].Metrics.BatteryVoltage)
	require.NotNil(t, items[3].Metrics.ACVoltage)
	// 未写入列 → nil
	assert.Nil(t, items[0].Metrics.InvCurrent)
	assert.Nil(t, items[0].Metrics.PV1Voltage)

	// 游标增量：全量页之后再拉 → 空且不重复
	afterT, afterHash := parseDebugCursor(t, cursor)
	page2, _, err := repo.GetDebugSamples(ctx, "DBG-SN", from, to, &afterT, afterHash, 200)
	require.NoError(t, err)
	require.NotNil(t, page2)
	assert.Empty(t, page2)

	// limit=2 分页：页间无重复且有序
	p1, c1, err := repo.GetDebugSamples(ctx, "DBG-SN", from, to, nil, "", 2)
	require.NoError(t, err)
	require.Len(t, p1, 2)
	at1, ah1 := parseDebugCursor(t, c1)
	p2, _, err := repo.GetDebugSamples(ctx, "DBG-SN", from, to, &at1, ah1, 2)
	require.NoError(t, err)
	require.Len(t, p2, 2)
	assert.True(t, p1[1].Time.Before(p2[0].Time))

	// 空结果：非 nil 空切片（Go nil slice → JSON null 会打爆前端）
	none, _, err := repo.GetDebugSamples(ctx, "DBG-NONE", from, to, nil, "", 200)
	require.NoError(t, err)
	require.NotNil(t, none)
	assert.Empty(t, none)
}

// TestDebugOnlineCheck 覆盖在线判定（status 1/2 在线，0 离线，不存在报错）。
func TestDebugOnlineCheck(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	_, err := repo.IsDeviceDebugOnline(ctx, "DBG-MISSING")
	require.Error(t, err)

	require.NoError(t, execPool(ctx, pool, `INSERT INTO devices (sn, user_id, status) VALUES ('DBG-ON-1', 1, 1)`))
	require.NoError(t, execPool(ctx, pool, `INSERT INTO devices (sn, user_id, status) VALUES ('DBG-ON-2', 1, 2)`))
	require.NoError(t, execPool(ctx, pool, `INSERT INTO devices (sn, user_id, status) VALUES ('DBG-OFF', 1, 0)`))

	on, err := repo.IsDeviceDebugOnline(ctx, "DBG-ON-1")
	require.NoError(t, err)
	assert.True(t, on)
	on, err = repo.IsDeviceDebugOnline(ctx, "DBG-ON-2")
	require.NoError(t, err)
	assert.True(t, on)
	on, err = repo.IsDeviceDebugOnline(ctx, "DBG-OFF")
	require.NoError(t, err)
	assert.False(t, on)
}

func execPool(ctx context.Context, pool *pgxpool.Pool, sql string, args ...any) error {
	_, err := pool.Exec(ctx, sql, args...)
	return err
}

func parseDebugCursor(t *testing.T, cursor string) (time.Time, string) {
	t.Helper()
	for i := len(cursor) - 1; i >= 0; i-- {
		if cursor[i] == '|' {
			ts, err := time.Parse(time.RFC3339Nano, cursor[:i])
			require.NoError(t, err, "cursor: %q", cursor)
			return ts, cursor[i+1:]
		}
	}
	t.Fatalf("cursor missing separator: %q", cursor)
	return time.Time{}, ""
}
