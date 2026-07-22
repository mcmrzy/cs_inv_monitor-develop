package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ParallelGroup represents a parallel group configuration record.
type ParallelGroup struct {
	ID          int64    `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	StationID   *int64   `json:"station_id"`
	MasterSN    string   `json:"master_sn"`
	PhaseConfig string   `json:"phase_config"`
	DeviceSNs   []string `json:"device_sns"`
	Status      string   `json:"status"`
	CreatedAt   string   `json:"created_at"`
	UpdatedAt   string   `json:"updated_at"`
}

type ParallelRepository struct {
	db *pgxpool.Pool
}

func NewParallelRepository(db *pgxpool.Pool) *ParallelRepository {
	return &ParallelRepository{db: db}
}

// List returns a paginated list of parallel groups, optionally filtered by search keyword
// (matched against name or master_sn) and station_id.
func (r *ParallelRepository) List(ctx context.Context, page, pageSize int, search string, stationID *int64) ([]ParallelGroup, int64, error) {
	// Build WHERE clause dynamically
	where := "WHERE 1=1"
	args := []interface{}{}
	argIdx := 1

	if search != "" {
		where += fmt.Sprintf(" AND (name ILIKE $%d OR master_sn ILIKE $%d)", argIdx, argIdx)
		args = append(args, "%"+search+"%")
		argIdx++
	}
	if stationID != nil {
		where += fmt.Sprintf(" AND station_id = $%d", argIdx)
		args = append(args, *stationID)
		argIdx++
	}

	// Count total
	var total int64
	countSQL := "SELECT COUNT(*) FROM parallel_groups " + where
	if err := r.db.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	// Query page
	offset := (page - 1) * pageSize
	querySQL := `
		SELECT id, name, COALESCE(description, ''), station_id, COALESCE(master_sn, ''),
		       phase_config, device_sns, status,
		       TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS'),
		       TO_CHAR(updated_at, 'YYYY-MM-DD HH24:MI:SS')
		FROM parallel_groups ` + where + `
		ORDER BY id DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)
	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, querySQL, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	groups := make([]ParallelGroup, 0)
	for rows.Next() {
		var g ParallelGroup
		var deviceSNsJSON []byte
		if err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.StationID, &g.MasterSN,
			&g.PhaseConfig, &deviceSNsJSON, &g.Status, &g.CreatedAt, &g.UpdatedAt); err != nil {
			return nil, 0, err
		}
		if len(deviceSNsJSON) > 0 {
			if err := json.Unmarshal(deviceSNsJSON, &g.DeviceSNs); err != nil {
				g.DeviceSNs = []string{}
			}
		}
		if g.DeviceSNs == nil {
			g.DeviceSNs = []string{}
		}
		groups = append(groups, g)
	}
	return groups, total, nil
}

// GetByID returns a single parallel group by its ID.
func (r *ParallelRepository) GetByID(ctx context.Context, id int64) (*ParallelGroup, error) {
	var g ParallelGroup
	var deviceSNsJSON []byte
	err := r.db.QueryRow(ctx, `
		SELECT id, name, COALESCE(description, ''), station_id, COALESCE(master_sn, ''),
		       phase_config, device_sns, status,
		       TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS'),
		       TO_CHAR(updated_at, 'YYYY-MM-DD HH24:MI:SS')
		FROM parallel_groups WHERE id = $1`, id).Scan(
		&g.ID, &g.Name, &g.Description, &g.StationID, &g.MasterSN,
		&g.PhaseConfig, &deviceSNsJSON, &g.Status, &g.CreatedAt, &g.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	if len(deviceSNsJSON) > 0 {
		if err := json.Unmarshal(deviceSNsJSON, &g.DeviceSNs); err != nil {
			g.DeviceSNs = []string{}
		}
	}
	if g.DeviceSNs == nil {
		g.DeviceSNs = []string{}
	}
	return &g, nil
}

// Create inserts a new parallel group and returns the created record.
func (r *ParallelRepository) Create(ctx context.Context, g *ParallelGroup) error {
	deviceSNsJSON, _ := json.Marshal(g.DeviceSNs)
	return r.db.QueryRow(ctx, `
		INSERT INTO parallel_groups (name, description, station_id, master_sn, phase_config, device_sns, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS'), TO_CHAR(updated_at, 'YYYY-MM-DD HH24:MI:SS')`,
		g.Name, g.Description, g.StationID, g.MasterSN, g.PhaseConfig, deviceSNsJSON, g.Status).Scan(&g.ID, &g.CreatedAt, &g.UpdatedAt)
}

// Update selectively updates a parallel group. Only non-nil fields are applied.
func (r *ParallelRepository) Update(ctx context.Context, id int64, name *string, description *string,
	stationID *int64, masterSN *string, phaseConfig *string, deviceSNs []string, status *string) error {
	// Use a transaction-free single UPDATE with COALESCE pattern for nullable fields.
	// device_sns is special: nil means "don't change", empty slice means "clear".
	var nameVal interface{}
	if name != nil {
		nameVal = *name
	}
	var descVal interface{}
	if description != nil {
		descVal = *description
	}
	var stationVal interface{}
	if stationID != nil {
		stationVal = *stationID
	}
	var masterVal interface{}
	if masterSN != nil {
		masterVal = *masterSN
	}
	var phaseVal interface{}
	if phaseConfig != nil {
		phaseVal = *phaseConfig
	}
	var statusVal interface{}
	if status != nil {
		statusVal = *status
	}

	// device_sns: only update if deviceSNs is non-nil (nil = skip, even empty slice updates)
	var deviceSNsVal interface{}
	if deviceSNs != nil {
		jsonBytes, _ := json.Marshal(deviceSNs)
		deviceSNsVal = jsonBytes
	}

	result, err := r.db.Exec(ctx, `
		UPDATE parallel_groups SET
			name        = COALESCE($2, name),
			description = COALESCE($3, description),
			station_id  = CASE WHEN $4::bigint IS NOT NULL THEN $4::bigint ELSE station_id END,
			master_sn   = COALESCE($5, master_sn),
			phase_config= COALESCE($6, phase_config),
			device_sns  = CASE WHEN $7::jsonb IS NOT NULL THEN $7::jsonb ELSE device_sns END,
			status      = COALESCE($8, status),
			updated_at  = NOW()
		WHERE id = $1`,
		id, nameVal, descVal, stationVal, masterVal, phaseVal, deviceSNsVal, statusVal)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// Delete removes a parallel group by its ID.
func (r *ParallelRepository) Delete(ctx context.Context, id int64) error {
	result, err := r.db.Exec(ctx, `DELETE FROM parallel_groups WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}
