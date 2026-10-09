//go:build integration

package repository

import (
	"context"
	"github.com/stretchr/testify/require"
	"testing"
	"time"
)

func TestMonitoringEnergyAndRichDeviceList(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `INSERT INTO users(id,phone,password_hash,nickname,status) VALUES(99101,'energy-test','hash','Energy test',1);
      INSERT INTO stations(id,user_id,name,province,city,address,capacity,timezone) VALUES(99101,99101,'Energy test','','','',10,'UTC');
      INSERT INTO devices(sn,model,user_id,station_id,status,rated_power,rated_power_w) VALUES('ENERGY-LIST', 'L10',99101,99101,1,10,10000);
      INSERT INTO device_latest_state(device_sn,protocol_version,sequence_no,event_time,received_at,total_pv_energy,ac_active_power)
      VALUES('ENERGY-LIST',3,1,NOW(),NOW(),0,1234);
      INSERT INTO device_energy_day(device_sn,stat_date,timezone,pv_energy,total_pv_energy) VALUES('ENERGY-LIST',CURRENT_DATE,'UTC',12.5,100);
      INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,received_at,data_hash,bms_summary)
      VALUES('ENERGY-LIST',3,1,NOW(),NOW(),'energy-test',jsonb_build_object('layout',0,'battery_count',1,'bms_online',1,'soc',80,'expires_at',NOW()+INTERVAL '200 seconds'));`)
	require.NoError(t, err)
	repo := NewDeviceRepository(pool, nil)
	total, month := repo.GetStationEnergySummary(ctx, 99101, "UTC")
	require.Equal(t, 100.0, total, "reset counter retains the previously recorded counter")
	require.Equal(t, 12.5, month)
	stats, err := repo.GetStatistics(ctx, "ENERGY-LIST", "", "", "day", "UTC")
	require.NoError(t, err)
	require.Equal(t, 100.0, stats["total_energy"])
	_, err = pool.Exec(ctx, `UPDATE device_energy_day SET total_pv_energy=NULL WHERE device_sn='ENERGY-LIST'`)
	require.NoError(t, err)
	total, _ = repo.GetStationEnergySummary(ctx, 99101, "UTC")
	require.Equal(t, 12.5, total, "zero device counter cannot erase recorded generation")
	_, err = pool.Exec(ctx, `UPDATE device_latest_state SET total_pv_energy=500 WHERE device_sn='ENERGY-LIST'`)
	require.NoError(t, err)
	total, _ = repo.GetStationEnergySummary(ctx, 99101, "UTC")
	require.Equal(t, 500.0, total, "prefer reported lifetime when larger, never sum absolute reports")
	for i := 0; i < 2; i++ {
		list, count, err := repo.List(ctx, DeviceListParams{UserID: 99101, Page: 1, PageSize: 10, Status: -1})
		require.NoError(t, err)
		require.EqualValues(t, 1, count)
		require.Len(t, list, 1)
		require.Equal(t, 10000, list[0].RatedPowerW)
		require.NotNil(t, list[0].TelemetryUpdatedAt)
		require.Equal(t, float64(80), list[0].BMSSummary["soc"])
	}
	_, err = pool.Exec(ctx, `UPDATE device_telemetry_3min SET bms_summary=bms_summary || '{"voltage":51.2,"current":-12}'::jsonb;
		UPDATE device_latest_state SET ac_active_power=1234 WHERE device_sn='ENERGY-LIST'`)
	require.NoError(t, err)
	_, load, _, batteryPower, batterySOC := repo.GetStationPowerBreakdown(ctx, 99101)
	require.Equal(t, 1234.0, load)
	require.InDelta(t, -614.4, batteryPower, 0.001)
	require.Equal(t, 80.0, batterySOC)
	for _, invalid := range []string{"-1", "Infinity", "NaN"} {
		_, err = pool.Exec(ctx, `UPDATE device_latest_state SET total_pv_energy=$1::float8 WHERE device_sn='ENERGY-LIST'`, invalid)
		require.NoError(t, err)
		stats, err := repo.GetStatistics(ctx, "ENERGY-LIST", "", "", "day", "UTC")
		require.NoError(t, err)
		require.Equal(t, 12.5, stats["total_energy"])
		total, _ := repo.GetStationEnergySummary(ctx, 99101, "UTC")
		require.Equal(t, 12.5, total)
	}
	_, err = pool.Exec(ctx, `UPDATE device_telemetry_3min SET bms_summary=jsonb_set(bms_summary,'{expires_at}',to_jsonb($1::text))`, time.Now().Add(-time.Minute).UTC().Format(time.RFC3339))
	require.NoError(t, err)
	list, err := repo.GetByStationID(ctx, 99101)
	require.NoError(t, err)
	require.Len(t, list, 1)
	require.Equal(t, 0, list[0].BMSSummary["bms_online"])
	require.Nil(t, list[0].BMSSummary["soc"])
	require.Equal(t, float64(1), list[0].BMSSummary["battery_count"], "offline battery remains discoverable")
	_, _, _, batteryPower, batterySOC = repo.GetStationPowerBreakdown(ctx, 99101)
	require.Zero(t, batteryPower)
	require.Zero(t, batterySOC)
}
