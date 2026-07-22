package handler

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func ensureTenantDeviceCapacity(ctx context.Context, db *pgxpool.Pool, userID int64) error {
	var limit *int
	var used int
	err := db.QueryRow(ctx, `WITH RECURSIVE ancestors AS (
		SELECT id,parent_id,role,device_limit FROM users WHERE id=$1 AND deleted_at IS NULL
		UNION ALL SELECT u.id,u.parent_id,u.role,u.device_limit FROM users u JOIN ancestors a ON a.parent_id=u.id WHERE u.deleted_at IS NULL
	), tenant AS (SELECT id,device_limit FROM ancestors WHERE role=1 LIMIT 1), members AS (
		SELECT id FROM users WHERE id=(SELECT id FROM tenant)
		UNION ALL SELECT u.id FROM users u JOIN members m ON u.parent_id=m.id WHERE u.deleted_at IS NULL
	) SELECT (SELECT device_limit FROM tenant),
		(SELECT COUNT(*) FROM devices WHERE user_id IN(SELECT id FROM members) AND deleted_at IS NULL)`, userID).Scan(&limit, &used)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if limit != nil && used >= *limit {
		return fmt.Errorf("tenant device quota reached (%d/%d)", used, *limit)
	}
	return nil
}

func ensureTenantUserCapacity(ctx context.Context, db *pgxpool.Pool, parentID, movingUserID int64) error {
	var limit *int
	var used int
	var alreadyMember bool
	err := db.QueryRow(ctx, `WITH RECURSIVE ancestors AS (
		SELECT id,parent_id,role,user_limit FROM users WHERE id=$1 AND deleted_at IS NULL
		UNION ALL SELECT u.id,u.parent_id,u.role,u.user_limit FROM users u JOIN ancestors a ON a.parent_id=u.id WHERE u.deleted_at IS NULL
	), tenant AS (SELECT id,user_limit FROM ancestors WHERE role=1 LIMIT 1), members AS (
		SELECT id FROM users WHERE id=(SELECT id FROM tenant)
		UNION ALL SELECT u.id FROM users u JOIN members m ON u.parent_id=m.id WHERE u.deleted_at IS NULL
	) SELECT (SELECT user_limit FROM tenant),
		(SELECT GREATEST(COUNT(*)-1,0) FROM members),
		EXISTS(SELECT 1 FROM members WHERE id=$2)`, parentID, movingUserID).Scan(&limit, &used, &alreadyMember)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if limit != nil && !alreadyMember && used >= *limit {
		return fmt.Errorf("tenant user quota reached (%d/%d)", used, *limit)
	}
	return nil
}
