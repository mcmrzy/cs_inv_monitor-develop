package repository

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrRevisionMismatch 乐观锁版本不匹配
var ErrRevisionMismatch = errors.New("revision mismatch: schedule was modified by another request")

// EnergySchedule 设备能源计划
type EnergySchedule struct {
	DeviceSN  string                 `json:"device_sn"`
	Timezone  string                 `json:"timezone"`
	Revision  int64                  `json:"revision"`
	Enabled   bool                   `json:"enabled"`
	Periods   []map[string]interface{} `json:"periods"`
	UpdatedBy *int64                 `json:"updated_by"`
	UpdatedAt time.Time              `json:"updated_at"`
}

// UpsertScheduleReq 更新能源计划请求
type UpsertScheduleReq struct {
	Timezone string                   `json:"timezone"`
	Enabled  bool                     `json:"enabled"`
	Periods  []map[string]interface{} `json:"periods"`
	UpdatedBy int64                   `json:"updated_by"`
}

// ControlOverride 临时控制覆盖
type ControlOverride struct {
	ID        int64                  `json:"id"`
	DeviceSN  string                 `json:"device_sn"`
	Domain    string                 `json:"domain"`
	Value     map[string]interface{} `json:"value"`
	ExpiresAt time.Time              `json:"expires_at"`
	TaskID    *string                `json:"task_id"`
	CreatedBy int64                  `json:"created_by"`
	CreatedAt time.Time              `json:"created_at"`
	Active    bool                   `json:"active"`
}

// CreateOverrideReq 创建临时覆盖请求
type CreateOverrideReq struct {
	Domain    string                 `json:"domain"`
	Value     map[string]interface{} `json:"value"`
	ExpiresAt time.Time              `json:"expires_at"`
	TaskID    *string                `json:"task_id"`
	CreatedBy int64                  `json:"created_by"`
}

type EnergyScheduleRepository struct {
	db *pgxpool.Pool
}

func NewEnergyScheduleRepository(db *pgxpool.Pool) *EnergyScheduleRepository {
	return &EnergyScheduleRepository{db: db}
}

func (r *EnergyScheduleRepository) GetEnergySchedule(ctx context.Context, sn string) (*EnergySchedule, error) {
	var s EnergySchedule
	var periodsRaw []byte
	err := r.db.QueryRow(ctx, `
		SELECT device_sn, timezone, revision, enabled, periods, updated_by, updated_at
		FROM device_energy_schedules WHERE device_sn = $1`, sn).Scan(
		&s.DeviceSN, &s.Timezone, &s.Revision, &s.Enabled, &periodsRaw, &s.UpdatedBy, &s.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if periodsRaw != nil {
		json.Unmarshal(periodsRaw, &s.Periods)
	}
	return &s, nil
}

func (r *EnergyScheduleRepository) UpsertEnergySchedule(ctx context.Context, sn string, req UpsertScheduleReq, expectedRevision int64) (*EnergySchedule, error) {
	periodsRaw, _ := json.Marshal(req.Periods)

	// 使用乐观锁：如果记录已存在，则检查 revision 是否匹配
	var s EnergySchedule
	var periodsResult []byte

	// 先尝试 INSERT ... ON CONFLICT，仅在 revision 匹配时更新
	err := r.db.QueryRow(ctx, `
		INSERT INTO device_energy_schedules (device_sn, timezone, revision, enabled, periods, updated_by, updated_at)
		VALUES ($1, $2, 1, $3, $4, $5, NOW())
		ON CONFLICT (device_sn) DO UPDATE SET
			timezone = EXCLUDED.timezone,
			enabled = EXCLUDED.enabled,
			periods = EXCLUDED.periods,
			updated_by = EXCLUDED.updated_by,
			updated_at = NOW(),
			revision = device_energy_schedules.revision + 1
		WHERE device_energy_schedules.revision = $6
		RETURNING device_sn, timezone, revision, enabled, periods, updated_by, updated_at`,
		sn, req.Timezone, req.Enabled, periodsRaw, req.UpdatedBy, expectedRevision,
	).Scan(
		&s.DeviceSN, &s.Timezone, &s.Revision, &s.Enabled, &periodsResult, &s.UpdatedBy, &s.UpdatedAt)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// RETURNING 返回空行说明 WHERE 条件不满足（revision 不匹配）
			return nil, ErrRevisionMismatch
		}
		return nil, err
	}
	if periodsResult != nil {
		json.Unmarshal(periodsResult, &s.Periods)
	}
	return &s, nil
}

func (r *EnergyScheduleRepository) CreateControlOverride(ctx context.Context, sn string, req CreateOverrideReq) (*ControlOverride, error) {
	valueRaw, _ := json.Marshal(req.Value)
	var o ControlOverride
	var valueResult []byte
	err := r.db.QueryRow(ctx, `
		INSERT INTO device_control_overrides (device_sn, domain, value, expires_at, task_id, created_by)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, device_sn, domain, value, expires_at, task_id, created_by, created_at, active`,
		sn, req.Domain, valueRaw, req.ExpiresAt, req.TaskID, req.CreatedBy,
	).Scan(
		&o.ID, &o.DeviceSN, &o.Domain, &valueResult, &o.ExpiresAt, &o.TaskID, &o.CreatedBy, &o.CreatedAt, &o.Active)
	if err != nil {
		return nil, err
	}
	if valueResult != nil {
		json.Unmarshal(valueResult, &o.Value)
	}
	return &o, nil
}

func (r *EnergyScheduleRepository) ListActiveOverrides(ctx context.Context, sn string) ([]ControlOverride, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, device_sn, domain, value, expires_at, task_id, created_by, created_at, active
		FROM device_control_overrides
		WHERE device_sn = $1 AND active = TRUE AND expires_at > NOW()
		ORDER BY created_at DESC`, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var overrides []ControlOverride
	for rows.Next() {
		var o ControlOverride
		var valueRaw []byte
		if err := rows.Scan(
			&o.ID, &o.DeviceSN, &o.Domain, &valueRaw, &o.ExpiresAt, &o.TaskID,
			&o.CreatedBy, &o.CreatedAt, &o.Active); err != nil {
			return nil, err
		}
		if valueRaw != nil {
			json.Unmarshal(valueRaw, &o.Value)
		}
		overrides = append(overrides, o)
	}
	return overrides, nil
}

func (r *EnergyScheduleRepository) CancelOverride(ctx context.Context, sn string, id int64) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE device_control_overrides SET active = FALSE
		WHERE device_sn = $1 AND id = $2 AND active = TRUE`, sn, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}
