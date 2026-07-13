package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"inv-device-server/internal/telemetry"
)

func (r *DeviceRepository) SaveReportedConfig(ctx context.Context, sn string, cfg *telemetry.ReportedConfig) error {
	reported, err := json.Marshal(cfg.Values)
	if err != nil {
		return err
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var oldReported []byte
	_ = tx.QueryRow(ctx, `SELECT reported FROM device_control_state WHERE device_sn=$1 FOR UPDATE`, sn).Scan(&oldReported)
	_, err = tx.Exec(ctx, `
		INSERT INTO device_control_state(device_sn,protocol_version,reported,reported_revision,sync_status,reported_at,updated_at)
		VALUES($1,$2,$3::jsonb,$4,'unknown',$5,NOW())
		ON CONFLICT(device_sn) DO UPDATE SET
			protocol_version=EXCLUDED.protocol_version,
			reported=EXCLUDED.reported,
			reported_revision=EXCLUDED.reported_revision,
			reported_at=EXCLUDED.reported_at,
			sync_status=CASE
				WHEN device_control_state.desired='{}'::jsonb THEN 'unknown'
				WHEN device_control_state.desired=EXCLUDED.reported THEN 'synced'
				ELSE 'drifted' END,
			updated_at=NOW()
		WHERE EXCLUDED.reported_revision >= device_control_state.reported_revision`,
		sn, cfg.ProtocolVersion, reported, cfg.Revision, cfg.EventTime)
	if err != nil {
		return fmt.Errorf("save reported config: %w", err)
	}
	if string(oldReported) != string(reported) {
		if _, err = tx.Exec(ctx, `INSERT INTO device_control_events(device_sn,event_type,old_value,new_value) VALUES($1,'reported',$2::jsonb,$3::jsonb)`, sn, jsonOrEmpty(oldReported), reported); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func jsonOrEmpty(v []byte) []byte {
	if len(v) == 0 {
		return []byte(`{}`)
	}
	return v
}
