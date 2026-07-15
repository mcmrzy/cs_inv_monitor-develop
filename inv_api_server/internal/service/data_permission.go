package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

type DataPermission struct {
	pool dataPermissionDB
}

type dataPermissionDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

func NewDataPermission(pool *pgxpool.Pool) *DataPermission {
	return &DataPermission{pool: pool}
}

func (d *DataPermission) GetAllowedDeviceSNs(ctx context.Context, userID int64) ([]string, error) {
	rows, err := d.pool.Query(ctx, `
		SELECT d.sn
		FROM devices d
		WHERE d.deleted_at IS NULL
		  AND (
			d.user_id = $1
			OR EXISTS (
				SELECT 1
				FROM user_device_rel udr
				WHERE udr.user_id = $1 AND udr.device_sn = d.sn
			)
		  )
		ORDER BY d.sn
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
			return nil, err
		}
		sns = append(sns, sn)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return sns, nil
}

func (d *DataPermission) HasDeviceAccess(ctx context.Context, userID int64, deviceSN string) (bool, error) {
	var allowed bool
	err := d.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM devices d
			WHERE d.sn = $2
			  AND d.deleted_at IS NULL
			  AND (
				d.user_id = $1
				OR EXISTS (
					SELECT 1
					FROM user_device_rel udr
					WHERE udr.user_id = $1 AND udr.device_sn = d.sn
				)
			  )
		)
	`, userID, deviceSN).Scan(&allowed)
	if err != nil {
		return false, err
	}
	return allowed, nil
}

func (d *DataPermission) BuildSNFilter(ctx context.Context, userID int64) (string, []interface{}, error) {
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
