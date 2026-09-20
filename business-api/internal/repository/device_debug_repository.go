package repository

import (
	"context"
	"errors"
	"math"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// roundDebugMetric 规整 REAL(float32) 指标列读出后带出的表示噪声。
// device_telemetry_3min 的指标列是 float32，读成 float64 后 51.2 会变成
// 51.20000076293945；调试页的 tooltip/表格直显这些数字极难读，且会传给
// 前端参与功率计算。保留 3 位小数（远超传感器有效精度）足以抹掉噪声，
// 同时把 -0 归一化为 0（否则 JSON 里会出现 "-0"）。
func roundDebugMetric(p *float64) *float64 {
	if p == nil {
		return nil
	}
	v := math.Round(*p*1000) / 1000
	if v == 0 {
		v = 0
	}
	return &v
}

// ErrDebugSessionConflict 同设备已有占用中会话（部分唯一索引 uq_device_debug_active_sn）。
var ErrDebugSessionConflict = errors.New("device debug session conflict")

const debugSessionColumns = `
	id, device_sn, request_id, status, interval_seconds, duration_seconds,
	started_at, expires_at, stopped_at, requested_by, source,
	start_task_id, stop_task_id, last_sample_at, failure_reason, created_at, updated_at
`

func scanDebugSession(row pgx.Row) (*model.DeviceDebugSession, error) {
	var s model.DeviceDebugSession
	err := row.Scan(
		&s.ID, &s.DeviceSN, &s.RequestID, &s.Status, &s.IntervalSeconds, &s.DurationSeconds,
		&s.StartedAt, &s.ExpiresAt, &s.StoppedAt, &s.RequestedBy, &s.Source,
		&s.StartTaskID, &s.StopTaskID, &s.LastSampleAt, &s.FailureReason, &s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// CreateDebugSession 插入调试会话。同设备已有占用中会话时返回 ErrDebugSessionConflict。
func (r *DeviceRepository) CreateDebugSession(ctx context.Context, s *model.DeviceDebugSession) error {
	row := r.db.QueryRow(ctx, `
		INSERT INTO device_debug_sessions
			(device_sn, request_id, status, interval_seconds, duration_seconds,
			 started_at, expires_at, requested_by, source, start_task_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING `+debugSessionColumns+`
	`,
		s.DeviceSN, s.RequestID, s.Status, s.IntervalSeconds, s.DurationSeconds,
		s.StartedAt, s.ExpiresAt, s.RequestedBy, s.Source, s.StartTaskID,
	)
	created, err := scanDebugSession(row)
	if err != nil {
		if isDebugUniqueViolation(err) {
			return ErrDebugSessionConflict
		}
		return err
	}
	*s = *created
	return nil
}

// GetDebugSessionByID 按 SN + 会话 ID 查询（数据隔离：SN 不匹配视为不存在）。
func (r *DeviceRepository) GetDebugSessionByID(ctx context.Context, sn string, id int64) (*model.DeviceDebugSession, error) {
	row := r.db.QueryRow(ctx,
		`SELECT `+debugSessionColumns+` FROM device_debug_sessions WHERE id = $1 AND device_sn = $2`, id, sn)
	return scanDebugSession(row)
}

// GetDebugSessionByRequest 幂等查询：按 (sn, request_id) 取已存在会话。
func (r *DeviceRepository) GetDebugSessionByRequest(ctx context.Context, sn, requestID string) (*model.DeviceDebugSession, error) {
	row := r.db.QueryRow(ctx,
		`SELECT `+debugSessionColumns+` FROM device_debug_sessions WHERE device_sn = $1 AND request_id = $2`, sn, requestID)
	s, err := scanDebugSession(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return s, err
}

// GetActiveDebugSession 查询设备当前占用中的会话；无则返回 nil。
func (r *DeviceRepository) GetActiveDebugSession(ctx context.Context, sn string) (*model.DeviceDebugSession, error) {
	row := r.db.QueryRow(ctx, `
		SELECT `+debugSessionColumns+` FROM device_debug_sessions
		WHERE device_sn = $1 AND status IN ('starting', 'active', 'stopping')
		ORDER BY id DESC LIMIT 1
	`, sn)
	s, err := scanDebugSession(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return s, err
}

// GetLatestDebugSession 查询设备最近一条会话（任意状态）；无则返回 nil。
func (r *DeviceRepository) GetLatestDebugSession(ctx context.Context, sn string) (*model.DeviceDebugSession, error) {
	row := r.db.QueryRow(ctx, `
		SELECT `+debugSessionColumns+` FROM device_debug_sessions
		WHERE device_sn = $1 ORDER BY id DESC LIMIT 1
	`, sn)
	s, err := scanDebugSession(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return s, err
}

// FinalizeDebugSession 将会话置为终态（幂等：仅从给定前状态集合推进，不匹配则无操作）。
// 注意 42P08 陷阱：status 列（SET 推断 varchar）与 CASE 字面量比较（推断 text）
// 必须使用独立参数（$2 与 $4），不可复用同一参数。
func (r *DeviceRepository) FinalizeDebugSession(ctx context.Context, id int64, fromStatuses []string, toStatus, reason string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_debug_sessions
		SET status = $2,
		    failure_reason = $3,
		    stopped_at = CASE WHEN $4 IN ('stopped', 'expired', 'interrupted', 'failed') THEN NOW() ELSE stopped_at END,
		    updated_at = NOW()
		WHERE id = $1 AND status = ANY($5)
	`, id, toStatus, reason, toStatus, fromStatuses)
	return err
}

// UpdateDebugSessionStartTask 回填开启命令 task_id。
func (r *DeviceRepository) UpdateDebugSessionStartTask(ctx context.Context, id int64, taskID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_debug_sessions SET start_task_id = $2, updated_at = NOW()
		WHERE id = $1
	`, id, taskID)
	return err
}

// GetDebugSessionByTaskID 按开启/停止命令 task_id 定位会话；未命中返回 pgx.ErrNoRows。
func (r *DeviceRepository) GetDebugSessionByTaskID(ctx context.Context, taskID string) (*model.DeviceDebugSession, error) {
	row := r.db.QueryRow(ctx, `
		SELECT `+debugSessionColumns+` FROM device_debug_sessions
		WHERE start_task_id = $1 OR stop_task_id = $1
		LIMIT 1
	`, taskID)
	return scanDebugSession(row)
}

// MarkDebugSessionStopping 停止流程：记停止任务 ID 并置为 stopping。
func (r *DeviceRepository) MarkDebugSessionStopping(ctx context.Context, id int64, stopTaskID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_debug_sessions SET stop_task_id = $2, status = 'stopping', updated_at = NOW()
		WHERE id = $1 AND status IN ('active', 'starting')
	`, id, stopTaskID)
	return err
}

// DebugSessionReap 一轮收口的会话行。
type DebugSessionReap struct {
	ID       int64
	DeviceSN string
	Status   string
}

// ReapStaleStartingSessions starting 超时（始终无新样本/回执确认）→ failed。
// 按 started_at 判定（插入时显式持久化），不用 created_at。
func (r *DeviceRepository) ReapStaleStartingSessions(ctx context.Context, olderThan time.Duration) ([]DebugSessionReap, error) {
	rows, err := r.db.Query(ctx, `
		UPDATE device_debug_sessions
		SET status = 'failed', failure_reason = '开启命令未在时限内确认', updated_at = NOW()
		WHERE status = 'starting' AND started_at < NOW() - make_interval(secs => $1)
		RETURNING id, device_sn, status
	`, olderThan.Seconds())
	return collectDebugReaps(rows, err)
}

// ReapStaleActiveSessions active 样本迟到超过阈值 → interrupted（设备侧 TTL 兜底恢复默认周期）。
func (r *DeviceRepository) ReapStaleActiveSessions(ctx context.Context, staleAfter time.Duration) ([]DebugSessionReap, error) {
	rows, err := r.db.Query(ctx, `
		UPDATE device_debug_sessions
		SET status = 'interrupted', failure_reason = '数据中断：超过时限未收到新样本', updated_at = NOW()
		WHERE status = 'active'
		  AND COALESCE(last_sample_at, started_at) < NOW() - make_interval(secs => $1)
		RETURNING id, device_sn, status
	`, staleAfter.Seconds())
	return collectDebugReaps(rows, err)
}

// ExpireDebugSessions 到期收口：所有占用中且已过 expires_at 的会话置为 expired。
// 返回此前处于 active/stopping 的行，协调循环对其补发停止命令（设备侧 TTL 为最终兜底）。
func (r *DeviceRepository) ExpireDebugSessions(ctx context.Context) ([]DebugSessionReap, error) {
	rows, err := r.db.Query(ctx, `
		UPDATE device_debug_sessions
		SET status = 'expired', updated_at = NOW()
		WHERE status IN ('starting', 'active', 'stopping') AND expires_at < NOW()
		RETURNING id, device_sn, status
	`)
	return collectDebugReaps(rows, err)
}

// RefreshDebugSampleTimes 用遥测表最新落库时间刷新占用中会话的 last_sample_at，
// 并把已见到新样本的 starting 会话提升为 active（首条新样本是设备真正在
// 按调试周期上报的最直接证据）。设备服务直写 device_telemetry_3min（不经
// business-api 内部 API），因此样本新鲜度由协调循环直接查询遥测表得到。
// 聚合通过 JOIN 限定到占用中会话的 SN，避免全设备规模扫描。
func (r *DeviceRepository) RefreshDebugSampleTimes(ctx context.Context) (int, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE device_debug_sessions s
		SET last_sample_at = t.max_time,
		    status = CASE WHEN s.status = 'starting' THEN 'active' ELSE s.status END,
		    updated_at = NOW()
		FROM (
			SELECT t.device_sn, MAX(t.event_time) AS max_time
			FROM device_debug_sessions s2
			JOIN device_telemetry_3min t
			  ON t.device_sn = s2.device_sn
			 AND t.event_time > NOW() - INTERVAL '15 minutes'
			WHERE s2.status IN ('starting', 'active')
			GROUP BY t.device_sn
		) t
		WHERE s.device_sn = t.device_sn
		  AND s.status IN ('starting', 'active')
		  AND (s.last_sample_at IS NULL OR s.last_sample_at < t.max_time)
	`)
	if err != nil {
		return 0, err
	}
	return int(tag.RowsAffected()), nil
}

// CountOccupyingDebugSessions 全局占用中会话数（并发设备上限用）。
func (r *DeviceRepository) CountOccupyingDebugSessions(ctx context.Context) (int, error) {
	var n int
	err := r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM device_debug_sessions WHERE status IN ('starting', 'active', 'stopping')
	`).Scan(&n)
	return n, err
}

// GetDebugSamples 有界原始样本查询：只投影白名单列，按 (event_time, data_hash) 稳定排序，
// 游标 (afterTime, afterHash) 增量返回。调用方必须以会话时间窗限定 from/to。
// 返回值保证非 nil（空结果为空切片，避免 JSON null）。
func (r *DeviceRepository) GetDebugSamples(ctx context.Context, sn string, from, to time.Time, afterTime *time.Time, afterHash string, limit int) ([]model.DebugSamplePoint, string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT event_time, received_at, quality_flags, protocol_version,
		       pv1_voltage, buck1_current, pv2_voltage, buck2_current,
		       battery_voltage, battery_current, dc_bus_voltage, inv_current,
		       ac_voltage, ac_current, data_hash
		FROM device_telemetry_3min
		WHERE device_sn = $1 AND event_time >= $2 AND event_time <= $3
		  AND ($4::timestamptz IS NULL OR event_time > $4
		       OR (event_time = $4 AND data_hash > $5))
		ORDER BY event_time ASC, data_hash ASC
		LIMIT $6
	`, sn, from, to, afterTime, afterHash, limit)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	items := make([]model.DebugSamplePoint, 0, limit)
	nextCursor := ""
	lastCursorHash := ""
	for rows.Next() {
		var p model.DebugSamplePoint
		var pv1, buck1, pv2, buck2, batV, batI, busV, invI, acV, acI *float64
		var dataHash string
		if err := rows.Scan(
			&p.Time, &p.ReceivedAt, &p.QualityFlags, &p.ProtocolVersion,
			&pv1, &buck1, &pv2, &buck2,
			&batV, &batI, &busV, &invI,
			&acV, &acI, &dataHash,
		); err != nil {
			return nil, "", err
		}
		p.Metrics = model.DebugSampleMetrics{
			PV1Voltage: roundDebugMetric(pv1), Buck1Current: roundDebugMetric(buck1),
			PV2Voltage: roundDebugMetric(pv2), Buck2Current: roundDebugMetric(buck2),
			BatteryVoltage: roundDebugMetric(batV), BatteryCurrent: roundDebugMetric(batI),
			DCBusVoltage: roundDebugMetric(busV), InvCurrent: roundDebugMetric(invI),
			ACVoltage: roundDebugMetric(acV), ACCurrent: roundDebugMetric(acI),
		}
		items = append(items, p)
		lastCursorHash = dataHash
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	// 游标 = 最后一行的 (event_time, data_hash)：满页时可能有更多数据；
	// 未满页也给出游标，调用方据此做增量拉取同样正确。
	if len(items) > 0 {
		last := items[len(items)-1]
		nextCursor = last.Time.UTC().Format(time.RFC3339Nano) + "|" + lastCursorHash
	}
	return items, nextCursor, nil
}

// IsDeviceDebugOnline 设备是否在线（status 1=在线 2=故障但在线，遥测会拉回 1）。
func (r *DeviceRepository) IsDeviceDebugOnline(ctx context.Context, sn string) (bool, error) {
	var status int
	err := r.db.QueryRow(ctx,
		`SELECT status FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn).Scan(&status)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, err
	}
	if err != nil {
		return false, err
	}
	return status == 1 || status == 2, nil
}

func collectDebugReaps(rows pgx.Rows, err error) ([]DebugSessionReap, error) {
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []DebugSessionReap{}
	for rows.Next() {
		var reap DebugSessionReap
		if err := rows.Scan(&reap.ID, &reap.DeviceSN, &reap.Status); err != nil {
			return nil, err
		}
		out = append(out, reap)
	}
	return out, rows.Err()
}

// isDebugUniqueViolation 唯一约束冲突（uq_device_debug_active_sn / uq_device_debug_request）。
func isDebugUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
