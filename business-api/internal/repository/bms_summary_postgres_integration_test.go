//go:build integration

package repository

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestBMSSummaryMigrationOnCompressedTelemetry(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `CREATE EXTENSION IF NOT EXISTS timescaledb;
		ALTER TABLE device_telemetry_3min DROP COLUMN bms_summary;
		SELECT create_hypertable('device_telemetry_3min','event_time',if_not_exists=>true);
		ALTER TABLE device_telemetry_3min SET(timescaledb.compress,
			timescaledb.compress_segmentby='device_sn',timescaledb.compress_orderby='event_time DESC');
		INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,data_hash)
			VALUES('OLD-BMS-TEST',3,0,NOW()-INTERVAL '5 days','old-packet');
		SELECT compress_chunk(c) FROM show_chunks('device_telemetry_3min') c;`)
	require.NoError(t, err)
	migration, err := os.ReadFile(filepath.Join("..", "..", "..", "database", "migrations", "126_arm_cmd08_bms_summary.up.sql"))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(migration))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(migration))
	require.NoError(t, err, "migration replay is idempotent")
	_, err = pool.Exec(ctx, `INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,data_hash,bms_summary)
		VALUES('NEW-BMS-TEST',3,0,NOW(),'new-packet','{"bms_online":1,"current":-1.23}'::jsonb)`)
	require.NoError(t, err)
	var current float64
	require.NoError(t, pool.QueryRow(ctx, `SELECT (bms_summary->>'current')::float8 FROM device_telemetry_3min WHERE device_sn='NEW-BMS-TEST'`).Scan(&current))
	require.Equal(t, -1.23, current)
}

func TestBMSSummaryDurableRealtimeAndRawHistory(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)
	now := time.Now().UTC().Truncate(time.Second)
	const sn = "BMS-CMD08-TEST"
	summary := map[string]any{"layout": 0, "bms_online": 1, "updated_at": now.Format(time.RFC3339), "expires_at": now.Add(210 * time.Second).Format(time.RFC3339), "soc": 87.5, "current": -1.23, "warning_flag": 32769, "raw_bytes": make([]int, 100)}
	raw, err := json.Marshal(summary)
	require.NoError(t, err)
	for _, at := range []time.Time{now, now.Add(-time.Minute)} {
		if at.Before(now) {
			summary["soc"] = 12.0
			raw, err = json.Marshal(summary)
			require.NoError(t, err)
		}
		_, err = pool.Exec(ctx, `INSERT INTO device_telemetry_3min
			(device_sn,protocol_version,sequence_no,event_time,received_at,data_hash,bms_summary)
			VALUES($1,3,0,$2,$2,$3,$4::jsonb)`, sn, at, at.Format(time.RFC3339), raw)
		require.NoError(t, err)
	}
	got, err := repo.GetRealtimeData(ctx, sn)
	require.NoError(t, err)
	bms := got["bms_summary"].(map[string]interface{})
	require.Equal(t, 87.5, bms["soc"])
	require.Equal(t, -1.23, bms["current"])
	require.Len(t, bms["raw_bytes"], 100)
	history, err := repo.GetTelemetryPage(ctx, sn, now.Add(-2*time.Minute).Format(time.RFC3339), now.Add(time.Second).Format(time.RFC3339), "raw", "UTC", true, 0, 10, nil)
	require.NoError(t, err)
	require.Len(t, history, 2)
	require.NotNil(t, history[0]["bms_summary"])
	_, err = pool.Exec(ctx, `UPDATE device_telemetry_3min SET bms_summary=jsonb_set(bms_summary,'{expires_at}',to_jsonb($2::text)) WHERE device_sn=$1`, sn, now.Add(-time.Minute).Format(time.RFC3339))
	require.NoError(t, err)
	got, err = repo.GetRealtimeData(ctx, sn)
	require.NoError(t, err)
	bms = got["bms_summary"].(map[string]interface{})
	require.Equal(t, 0, bms["bms_online"])
	require.Nil(t, bms["soc"])
	require.Len(t, bms["raw_bytes"], 100)
}

func TestBMSSummaryLookupFailurePreservesInverterRealtime(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,data_hash,ac_voltage)
		VALUES('BMS-OPTIONAL-TEST',3,0,NOW(),'core-packet',230);
		ALTER TABLE device_telemetry_3min DROP COLUMN bms_summary;`)
	require.NoError(t, err)
	got, err := NewDeviceRepository(pool, nil).GetRealtimeData(ctx, "BMS-OPTIONAL-TEST")
	require.NoError(t, err, "optional BMS lookup failure preserves core realtime")
	require.Equal(t, 230.0, got["ac_voltage"])
}
