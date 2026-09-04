package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"inv-device-server/internal/model"

	"github.com/jackc/pgx/v5"
)

// GetModelDiagnosticSpecs 读取 device_models.specifications.diagnostics 阈值。
// modelID<=0（型号未注册）或读取失败时返回默认阈值，保证诊断引擎始终可用。
func (r *DeviceRepository) GetModelDiagnosticSpecs(ctx context.Context, modelID int32) model.DiagnosticSpecs {
	specs := model.DefaultDiagnosticSpecs()
	if modelID <= 0 {
		return specs
	}
	var raw []byte
	err := r.db.QueryRow(ctx,
		`SELECT COALESCE(specifications->'diagnostics', '{}'::jsonb) FROM device_models WHERE id=$1`, modelID).Scan(&raw)
	if err != nil {
		return specs
	}
	// 部分字段缺失时保留默认值：以默认结构为底，用 DB 值覆盖已配置字段
	_ = json.Unmarshal(raw, &specs)
	return specs
}

// ListActiveDiagnostics 列出设备活跃诊断（status='active'）。
func (r *DeviceRepository) ListActiveDiagnostics(ctx context.Context, sn string) ([]model.DiagnosticEvent, error) {
	rows, err := r.db.Query(ctx, `
		SELECT rule_code, level, detail, first_at, last_at, count
		FROM device_diagnostics WHERE device_sn=$1 AND status='active'`, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []model.DiagnosticEvent
	for rows.Next() {
		var e model.DiagnosticEvent
		var detail []byte
		if err := rows.Scan(&e.RuleCode, &e.Level, &detail, &e.FirstAt, &e.LastAt, &e.Count); err != nil {
			return nil, err
		}
		e.Status = "active"
		_ = json.Unmarshal(detail, &e.Detail)
		events = append(events, e)
	}
	return events, rows.Err()
}

// UpsertDiagnostic 写入/聚合诊断事件：已存在则更新 level/detail/last_at 并 count+1、置回 active。
func (r *DeviceRepository) UpsertDiagnostic(ctx context.Context, sn string, e model.DiagnosticEvent) error {
	detail, err := json.Marshal(e.Detail)
	if err != nil {
		return err
	}
	_, err = r.db.Exec(ctx, `
		INSERT INTO device_diagnostics(device_sn,rule_code,level,status,detail,first_at,last_at,count)
		VALUES($1,$2,$3,'active',$4::jsonb,$5,$5,1)
		ON CONFLICT(device_sn,rule_code) DO UPDATE SET
			level=EXCLUDED.level,
			status='active',
			detail=EXCLUDED.detail,
			last_at=EXCLUDED.last_at,
			count=device_diagnostics.count+1`,
		sn, e.RuleCode, e.Level, detail, e.LastAt)
	return err
}

// ResolveDiagnostic 将指定规则标记为 resolved（仅 active → resolved）。
func (r *DeviceRepository) ResolveDiagnostic(ctx context.Context, sn, ruleCode string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_diagnostics SET status='resolved'
		WHERE device_sn=$1 AND rule_code=$2 AND status='active'`, sn, ruleCode)
	return err
}

// GetPreviousWorkTimeTotal 返回该设备在 eventTime 之前的最近一条 work_time_total
// （用于 MAINTENANCE_DUE 跨阈值判定：上次 < 阈值 ≤ 本次）。
func (r *DeviceRepository) GetPreviousWorkTimeTotal(ctx context.Context, sn string, eventTime time.Time) (float64, bool, error) {
	var v float64
	err := r.db.QueryRow(ctx, `
		SELECT work_time_total FROM device_telemetry_3min
		WHERE device_sn=$1 AND event_time < $2 AND work_time_total IS NOT NULL
		ORDER BY event_time DESC LIMIT 1`, sn, eventTime).Scan(&v)
	if err != nil {
		if err == pgx.ErrNoRows {
			return 0, false, nil
		}
		return 0, false, err
	}
	return v, true, nil
}

// SaveHealthScore 更新 device_latest_state.health_score；score 发生变化时追加 device_health_history。
func (r *DeviceRepository) SaveHealthScore(ctx context.Context, sn string, h model.HealthResult, eventTime time.Time) error {
	var old *float64
	_ = r.db.QueryRow(ctx, `SELECT health_score FROM device_latest_state WHERE device_sn=$1`, sn).Scan(&old)
	if _, err := r.db.Exec(ctx, `UPDATE device_latest_state SET health_score=$2 WHERE device_sn=$1`, sn, h.Score); err != nil {
		return fmt.Errorf("update health score: %w", err)
	}
	if old != nil && math.Abs(*old-h.Score) < 0.01 {
		return nil // score 未变化，不追加历史（避免历史表随心跳膨胀）
	}
	factors, err := json.Marshal(h.Factors)
	if err != nil {
		return err
	}
	_, err = r.db.Exec(ctx, `
		INSERT INTO device_health_history(device_sn,event_time,score,level,factors)
		VALUES($1,$2,$3,$4,$5::jsonb)`, sn, eventTime, h.Score, h.Level, factors)
	return err
}
