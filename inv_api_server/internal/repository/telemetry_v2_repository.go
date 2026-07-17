package repository

import (
	"context"
	"encoding/json"
	"time"

	"inv-api-server/pkg/timezone"

	"github.com/jackc/pgx/v5"
)

func (r *DeviceRepository) GetHistoryData(ctx context.Context, sn, startDate, endDate, period string) ([]map[string]interface{}, error) {
	query := `
		SELECT bucket, avg_ac_power, max_ac_power, daily_pv_energy,
		       avg_inverter_temperature, run_minutes
		FROM device_telemetry_hour
		WHERE device_sn=$1 AND bucket >= $2::timestamptz
		  AND bucket < ($3::date + 1)::timestamptz
		ORDER BY bucket`
	if period != "hour" {
		query = `
			SELECT stat_date::timestamptz, NULL::double precision, max_ac_power,
			       pv_energy, max_inverter_temperature, run_minutes
			FROM device_energy_day
			WHERE device_sn=$1 AND stat_date >= $2::date AND stat_date <= $3::date
			ORDER BY stat_date`
	}
	rows, err := r.db.Query(ctx, query, sn, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]map[string]interface{}, 0)
	for rows.Next() {
		var bucket time.Time
		var avgPower, maxPower, energy, temperature *float64
		var runMinutes int
		if err := rows.Scan(&bucket, &avgPower, &maxPower, &energy, &temperature, &runMinutes); err != nil {
			return nil, err
		}
		result = append(result, map[string]interface{}{
			"time": bucket, "avg_power": numberOrZero(avgPower), "max_power": numberOrZero(maxPower),
			"energy_produce": numberOrZero(energy), "avg_temperature": numberOrZero(temperature),
			"run_minutes": runMinutes,
		})
	}
	return result, rows.Err()
}

func (r *DeviceRepository) GetStatistics(ctx context.Context, sn, startDate, endDate, period, tz string) (map[string]interface{}, error) {
	today := timezone.TodayInTimezone(tz)
	loc := timezone.LoadLocation(tz)
	now := time.Now().In(loc)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc).Format("2006-01-02")
	var dailyEnergy, monthlyEnergy, totalEnergy, dailyDischarge float64
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(MAX(pv_energy) FILTER (WHERE stat_date=$2::date),0),
		       COALESCE(
		           (SELECT m.pv_energy FROM device_energy_month m
		            WHERE m.device_sn=$1 AND m.stat_month=$3::date),
		           SUM(pv_energy) FILTER (WHERE stat_date >= $3::date),
		           0
		       ),
		       COALESCE(SUM(pv_energy),0),
		       COALESCE(MAX(discharge_energy) FILTER (WHERE stat_date=$2::date),0)
		FROM device_energy_day WHERE device_sn=$1`, sn, today, monthStart).
		Scan(&dailyEnergy, &monthlyEnergy, &totalEnergy, &dailyDischarge)
	if err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"daily_energy": dailyEnergy, "monthly_energy": monthlyEnergy, "total_energy": totalEnergy,
		"daily_discharge": dailyDischarge, "daily_grid_sell": 0.0, "daily_grid_buy": 0.0,
	}, nil
}

func numberOrZero(value *float64) float64 {
	if value == nil {
		return 0
	}
	return *value
}

func (r *DeviceRepository) GetControlState(ctx context.Context, sn string) (map[string]interface{}, error) {
	var raw []byte
	err := r.db.QueryRow(ctx, `
		SELECT jsonb_build_object(
			'device_sn',device_sn,'protocol_version',protocol_version,
			'desired',desired,'reported',reported,'desired_version',desired_version,
			'reported_revision',reported_revision,'sync_status',sync_status,
			'desired_at',desired_at,'reported_at',reported_at,'last_task_id',last_task_id,
			'updated_at',updated_at)
		FROM device_control_state WHERE device_sn=$1`, sn).Scan(&raw)
	if err == pgx.ErrNoRows {
		return map[string]interface{}{
			"device_sn": sn, "protocol_version": 1, "desired": map[string]interface{}{},
			"reported": map[string]interface{}{}, "sync_status": "unknown",
		}, nil
	}
	if err != nil {
		return nil, err
	}
	var state map[string]interface{}
	if err := json.Unmarshal(raw, &state); err != nil {
		return nil, err
	}
	return state, nil
}

func (r *DeviceRepository) SetDesiredControlState(ctx context.Context, sn, taskID, command string, params map[string]interface{}) error {
	raw, err := json.Marshal(params)
	if err != nil {
		return err
	}
	_, err = r.db.Exec(ctx, `
		INSERT INTO device_control_state(device_sn,desired,desired_version,sync_status,desired_at,last_task_id,updated_at)
		VALUES($1,$2::jsonb,1,'pending',NOW(),$3::uuid,NOW())
		ON CONFLICT(device_sn) DO UPDATE SET desired=device_control_state.desired || EXCLUDED.desired,
			desired_version=device_control_state.desired_version+1,sync_status='pending',desired_at=NOW(),
			last_task_id=EXCLUDED.last_task_id,updated_at=NOW()`, sn, raw, taskID)
	if err != nil {
		return err
	}
	_, err = r.db.Exec(ctx, `INSERT INTO device_control_events(device_sn,task_id,event_type,new_value)
		VALUES($1,$2::uuid,$3,$4::jsonb)`, sn, taskID, "desired:"+command, raw)
	return err
}

func (r *StationRepository) GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error) {
	query := `SELECT h.bucket, SUM(h.avg_pv_power), SUM(h.avg_ac_power), SUM(h.avg_battery_power),
		SUM(h.daily_pv_energy),
		SUM(GREATEST(h.avg_battery_power, 0)) / 1000.0,
		SUM(GREATEST(-h.avg_battery_power, 0)) / 1000.0,
		SUM(h.avg_ac_power) / 1000.0
		FROM device_telemetry_hour h JOIN devices d ON d.sn=h.device_sn
		WHERE d.station_id=$1 AND d.deleted_at IS NULL AND h.bucket >= $2::timestamptz
		AND h.bucket < ($3::date+1)::timestamptz GROUP BY h.bucket ORDER BY h.bucket`
	if period != "hour" {
		query = `SELECT e.stat_date::timestamptz, SUM(e.pv_energy), SUM(e.max_ac_power), NULL::double precision,
			SUM(e.pv_energy),SUM(e.charge_energy),SUM(e.discharge_energy),SUM(e.load_energy)
			FROM device_energy_day e JOIN devices d ON d.sn=e.device_sn
			WHERE d.station_id=$1 AND d.deleted_at IS NULL AND e.stat_date >= $2::date AND e.stat_date <= $3::date
			GROUP BY e.stat_date ORDER BY e.stat_date`
	}
	rows, err := r.db.Query(ctx, query, stationID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]map[string]interface{}, 0)
	for rows.Next() {
		var bucket time.Time
		var pv, ac, battery, dailyPV, charge, discharge, load *float64
		if err := rows.Scan(&bucket, &pv, &ac, &battery, &dailyPV, &charge, &discharge, &load); err != nil {
			return nil, err
		}
		batt := numberOrZero(battery)
		result = append(result, map[string]interface{}{
			"time": bucket, "energy_produce": numberOrZero(pv), "energy_consume": numberOrZero(ac),
			"battery_charge": maxFloat(batt, 0), "battery_discharge": maxFloat(-batt, 0),
			"daily_pv": numberOrZero(dailyPV), "daily_charge": numberOrZero(charge),
			"daily_discharge": numberOrZero(discharge), "daily_load": numberOrZero(load),
		})
	}
	return result, rows.Err()
}

func (r *DeviceRepository) GetStationRealtimeSummary(ctx context.Context, stationID int64, tz string) (float64, float64, error) {
	today := timezone.TodayInTimezone(tz)
	var energy, power float64
	err := r.db.QueryRow(ctx, `SELECT COALESCE(SUM(e.pv_energy),0),COALESCE(SUM(l.ac_active_power),0)
		FROM devices d LEFT JOIN device_energy_day e ON e.device_sn=d.sn AND e.stat_date=$2::date
		LEFT JOIN device_latest_state l ON l.device_sn=d.sn
		WHERE d.station_id=$1 AND d.deleted_at IS NULL`, stationID, today).Scan(&energy, &power)
	return energy, power, err
}

func (r *DeviceRepository) GetStationPowerBreakdown(ctx context.Context, stationID int64) (pvPower, loadPower, gridPower, battPower, battSoc float64) {
	_ = r.db.QueryRow(ctx, `SELECT COALESCE(SUM(l.pv_total_power),0),COALESCE(SUM(l.ac_active_power),0),
		COALESCE(SUM(l.battery_power),0),COALESCE(AVG(l.battery_soc),0)
		FROM devices d JOIN device_latest_state l ON l.device_sn=d.sn
		WHERE d.station_id=$1 AND d.deleted_at IS NULL`, stationID).Scan(&pvPower, &loadPower, &battPower, &battSoc)
	return pvPower, loadPower, 0, battPower, battSoc
}

func (r *DeviceRepository) GetStationEnergySummary(ctx context.Context, stationID int64, tz string) (float64, float64) {
	loc := timezone.LoadLocation(tz)
	now := time.Now().In(loc)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc).Format("2006-01-02")
	var total, month float64
	_ = r.db.QueryRow(ctx, `SELECT COALESCE(SUM(l.total_pv_energy),0),COALESCE((SELECT SUM(e.pv_energy)
		FROM device_energy_day e JOIN devices d2 ON d2.sn=e.device_sn
		WHERE d2.station_id=$1 AND d2.deleted_at IS NULL AND e.stat_date >= $2::date),0)
		FROM devices d LEFT JOIN device_latest_state l ON l.device_sn=d.sn
		WHERE d.station_id=$1 AND d.deleted_at IS NULL`, stationID, monthStart).Scan(&total, &month)
	return total, month
}

func (r *DeviceRepository) GetStationYearEnergy(ctx context.Context, stationID int64, tz string) float64 {
	loc := timezone.LoadLocation(tz)
	yearStart := time.Date(time.Now().In(loc).Year(), 1, 1, 0, 0, 0, 0, loc).Format("2006-01-02")
	var value float64
	_ = r.db.QueryRow(ctx, `SELECT COALESCE(SUM(e.pv_energy),0) FROM device_energy_day e
		JOIN devices d ON d.sn=e.device_sn WHERE d.station_id=$1 AND d.deleted_at IS NULL AND e.stat_date >= $2::date`, stationID, yearStart).Scan(&value)
	return value
}

func (r *DeviceRepository) GetStationTodayEnergy(ctx context.Context, stationID int64, tz string) (float64, error) {
	var value float64
	err := r.db.QueryRow(ctx, `SELECT COALESCE(SUM(e.pv_energy),0) FROM device_energy_day e
		JOIN devices d ON d.sn=e.device_sn WHERE d.station_id=$1 AND d.deleted_at IS NULL AND e.stat_date=$2::date`,
		stationID, timezone.TodayInTimezone(tz)).Scan(&value)
	return value, err
}

func (r *DeviceRepository) GetTrend(ctx context.Context, userID int64, period, tz string) ([]map[string]interface{}, error) {
	today := timezone.TodayInTimezone(tz)
	rows, err := r.db.Query(ctx, `SELECT e.stat_date,COALESCE(SUM(e.pv_energy),0) FROM device_energy_day e
		JOIN devices d ON d.sn=e.device_sn WHERE d.deleted_at IS NULL
		AND d.sn IN (SELECT sn FROM devices WHERE user_id=$1 AND deleted_at IS NULL UNION SELECT device_sn FROM user_device_rel WHERE user_id=$1)
		AND e.stat_date >= $2::date-30 GROUP BY e.stat_date ORDER BY e.stat_date`, userID, today)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]map[string]interface{}, 0)
	for rows.Next() {
		var date time.Time
		var energy float64
		if err := rows.Scan(&date, &energy); err != nil {
			return nil, err
		}
		result = append(result, map[string]interface{}{"date": date, "energy_produce": energy, "income": 0.0})
	}
	return result, rows.Err()
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func (r *DeviceRepository) getTelemetryV2(ctx context.Context, sn, startTime, endTime string) ([]map[string]interface{}, error) {
	rows, err := r.db.Query(ctx, `
		-- Keep protocol_version and quality_flags in the JSON contract. Clients use
		-- them to explain parser version and degraded/late samples.
		SELECT to_jsonb(t) - 'device_sn' - 'received_at' || jsonb_build_object('time', t.event_time)
		FROM device_telemetry_3min t
		WHERE device_sn=$1 AND event_time >= $2::timestamptz AND event_time <= $3::timestamptz
		ORDER BY event_time`, sn, startTime, endTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]map[string]interface{}, 0)
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, err
		}
		var item map[string]interface{}
		if err := json.Unmarshal(raw, &item); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}
