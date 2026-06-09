package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

type DataPermission struct {
	pool *pgxpool.Pool
}

func NewDataPermission(pool *pgxpool.Pool) *DataPermission {
	return &DataPermission{pool: pool}
}

func (d *DataPermission) GetAllowedDeviceSNs(ctx context.Context, userID int64) ([]string, error) {
	rows, err := d.pool.Query(ctx, `
		SELECT DISTINCT device_sn FROM v_user_device_access
		WHERE user_id = $1
		UNION
		SELECT sn FROM devices WHERE user_id = $1 AND deleted_at IS NULL
		ORDER BY device_sn
	`, userID)
	if err != nil {
		logger.Error("DataPermission: query failed",
			zap.Int64("user_id", userID), zap.Error(err))
		return nil, err
	}
	defer rows.Close()

	var sns []string
	for rows.Next() {
		var sn string
		if err := rows.Scan(&sn); err != nil {
			continue
		}
		sns = append(sns, sn)
	}
	return sns, nil
}

func (d *DataPermission) HasDeviceAccess(ctx context.Context, userID int64, deviceSN string) (bool, error) {
	var count int
	err := d.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM (
			SELECT device_sn FROM v_user_device_access WHERE user_id = $1 AND device_sn = $2
			UNION
			SELECT sn FROM devices WHERE user_id = $1 AND sn = $2 AND deleted_at IS NULL
		) t
	`, userID, deviceSN).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (d *DataPermission) BuildSNFilter(ctx context.Context, userID int64) (string, []interface{}, error) {
	role, _ := d.getUserRole(ctx, userID)
	if role == 1 {
		return "", nil, nil
	}

	sns, err := d.GetAllowedDeviceSNs(ctx, userID)
	if err != nil {
		return "", nil, err
	}

	if len(sns) == 0 {
		return "1=0", nil, nil
	}

	placeholders := make([]string, len(sns))
	args := make([]interface{}, len(sns))
	for i, sn := range sns {
		placeholders[i] = fmt.Sprintf("$%d", i+1)
		args[i] = sn
	}

	return fmt.Sprintf("sn IN (%s)", strings.Join(placeholders, ",")), args, nil
}

func (d *DataPermission) getUserRole(ctx context.Context, userID int64) (int, error) {
	var role int
	err := d.pool.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if err != nil {
		return 0, err
	}
	return role, nil
}
