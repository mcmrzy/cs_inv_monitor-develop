package repository

import (
	"context"
	"fmt"

	"inv-api-server/internal/model"
)

type StationOverviewDeviceStats struct {
	DeviceCount int
	OnlineCount int
	FaultCount  int
	TotalPower  float64
	TodayEnergy float64
	TotalEnergy float64
	MonthEnergy float64
	YearEnergy  float64
}

// Both resource scopes are rechecked in the aggregation statement. Each device
// contributes one lifetime value, independently of how many daily rows it has.
func (r *StationRepository) OverviewDeviceStats(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationIDs []int64) (map[int64]StationOverviewDeviceStats, error) {
	result := make(map[int64]StationOverviewDeviceStats)
	if len(stationIDs) == 0 {
		return result, nil
	}
	stationFilter, stationArgs := OverviewScopeFilter(stationPlan, systemAdmin, "s", 2)
	deviceFilter, deviceArgs := OverviewScopeFilter(devicePlan, systemAdmin, "d", 2+len(stationArgs))
	args := append([]any{stationIDs}, stationArgs...)
	args = append(args, deviceArgs...)
	query := fmt.Sprintf(`WITH selected_stations AS (
		SELECT s.id,(NOW() AT TIME ZONE COALESCE(NULLIF(s.timezone,''),'Asia/Shanghai'))::date AS today
		FROM stations s WHERE s.id=ANY($1) AND s.deleted_at IS NULL AND %s
	), scoped_devices AS (
		SELECT d.sn,d.station_id,d.status,s.today,l.total_pv_energy,l.ac_active_power,l.updated_at
		FROM devices d JOIN selected_stations s ON s.id=d.station_id
		LEFT JOIN device_latest_state l ON l.device_sn=d.sn
		WHERE d.deleted_at IS NULL AND %s
	), recorded AS (
		SELECT e.device_sn,
			COALESCE(SUM(e.pv_energy) FILTER (WHERE e.pv_energy>=0 AND e.pv_energy<'Infinity'::float8),0) AS recorded,
			COALESCE(MAX(e.total_pv_energy) FILTER (WHERE e.total_pv_energy>=0 AND e.total_pv_energy<'Infinity'::float8),0) AS counter,
			COALESCE(SUM(e.pv_energy) FILTER (WHERE e.stat_date=d.today AND e.pv_energy>=0 AND e.pv_energy<'Infinity'::float8),0) AS today,
			COALESCE(SUM(e.pv_energy) FILTER (WHERE e.stat_date>=date_trunc('month',d.today)::date AND e.pv_energy>=0 AND e.pv_energy<'Infinity'::float8),0) AS month,
			COALESCE(SUM(e.pv_energy) FILTER (WHERE e.stat_date>=date_trunc('year',d.today)::date AND e.pv_energy>=0 AND e.pv_energy<'Infinity'::float8),0) AS year
		FROM device_energy_day e JOIN scoped_devices d ON d.sn=e.device_sn
		GROUP BY e.device_sn
	)
	SELECT d.station_id,COUNT(*),COUNT(*) FILTER (WHERE d.status IN (1,2)),COUNT(*) FILTER (WHERE d.status=2),
		COALESCE(SUM(d.ac_active_power) FILTER (WHERE d.status IN (1,2) AND d.updated_at>NOW()-INTERVAL '5 minutes'
			AND d.updated_at<=NOW() AND d.ac_active_power>'-Infinity'::float8 AND d.ac_active_power<'Infinity'::float8),0),
		ROUND(COALESCE(SUM(e.today),0)::numeric,2)::float8,
		ROUND(COALESCE(SUM(GREATEST(COALESCE(CASE WHEN d.total_pv_energy>=0 AND d.total_pv_energy<'Infinity'::float8 THEN d.total_pv_energy END,0),
			COALESCE(e.recorded,0),COALESCE(e.counter,0))),0)::numeric,2)::float8,
		ROUND(COALESCE(SUM(e.month),0)::numeric,2)::float8,
		ROUND(COALESCE(SUM(e.year),0)::numeric,2)::float8
	FROM scoped_devices d LEFT JOIN recorded e ON e.device_sn=d.sn GROUP BY d.station_id`, stationFilter, deviceFilter)
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		var stats StationOverviewDeviceStats
		if err := rows.Scan(&id, &stats.DeviceCount, &stats.OnlineCount, &stats.FaultCount, &stats.TotalPower,
			&stats.TodayEnergy, &stats.TotalEnergy, &stats.MonthEnergy, &stats.YearEnergy); err != nil {
			return nil, err
		}
		result[id] = stats
	}
	return result, rows.Err()
}
