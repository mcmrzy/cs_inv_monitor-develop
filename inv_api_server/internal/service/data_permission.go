package service

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

type DataPermission struct {
	pool       dataPermissionDB
	authorizer channelDeviceAuthorizer
	mode       DataPermissionMode
	recorder   DataPermissionShadowRecorder
}

type DataPermissionMode string

var ErrChannelAuthorizerUnavailable = errors.New("channel authorizer is unavailable")

const (
	DataPermissionLegacy  DataPermissionMode = "legacy"
	DataPermissionShadow  DataPermissionMode = "shadow"
	DataPermissionEnforce DataPermissionMode = "enforce"
)

type channelDeviceAuthorizer interface {
	Authorize(ctx context.Context, actor model.ActorContext, request model.AuthorizationRequest) (model.AuthorizationDecision, error)
}

type DataPermissionShadowRecorder interface {
	RecordDeviceDecision(ctx context.Context, actor model.ActorContext, permissionCode, deviceSN string, legacyAllowed, channelAllowed bool, channelErr error)
}

type dataPermissionDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

func NewDataPermission(pool *pgxpool.Pool) *DataPermission {
	return &DataPermission{pool: pool, mode: DataPermissionLegacy}
}

func NewDataPermissionAdapter(pool *pgxpool.Pool, authorizer channelDeviceAuthorizer, mode DataPermissionMode, recorder DataPermissionShadowRecorder) *DataPermission {
	return &DataPermission{pool: pool, authorizer: authorizer, mode: mode, recorder: recorder}
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
	return `EXISTS (
		SELECT 1 FROM v_user_device_access permission_access
		WHERE permission_access.user_id=$1 AND permission_access.device_sn=sn
	)`, []interface{}{userID}, nil
}

// HasDeviceAccessV2 requires an already validated organization context. It
// never guesses a membership from userID and never ORs legacy/new decisions.
func (d *DataPermission) HasDeviceAccessV2(ctx context.Context, actor model.ActorContext, permissionCode, deviceSN string) (bool, error) {
	legacyAllowed, legacyErr := d.HasDeviceAccess(ctx, actor.UserID, deviceSN)
	if d.mode == DataPermissionLegacy {
		return legacyAllowed, legacyErr
	}
	if d.authorizer == nil {
		if d.recorder != nil {
			d.recorder.RecordDeviceDecision(ctx, actor, permissionCode, deviceSN, legacyAllowed, false, ErrChannelAuthorizerUnavailable)
		}
		if d.mode == DataPermissionShadow {
			return legacyAllowed, legacyErr
		}
		return false, ErrChannelAuthorizerUnavailable
	}
	decision, channelErr := d.authorizer.Authorize(ctx, actor, model.AuthorizationRequest{
		PermissionCode: permissionCode,
		Object:         &model.ObjectRef{ResourceType: "device", ResourceID: deviceSN},
	})
	if d.recorder != nil && (legacyAllowed != decision.Allowed || channelErr != nil) {
		d.recorder.RecordDeviceDecision(ctx, actor, permissionCode, deviceSN, legacyAllowed, decision.Allowed, channelErr)
	}
	if d.mode == DataPermissionShadow {
		return legacyAllowed, legacyErr
	}
	if channelErr != nil {
		return false, channelErr
	}
	return decision.Allowed, nil
}
