package repository

import (
	"context"
	"database/sql"
	"math"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5"
)

func (r *StationRepository) GetOverviewByID(ctx context.Context, plan model.ScopePlan, systemAdmin bool, id int64) (*model.Station, error) {
	filter, args := OverviewScopeFilter(plan, systemAdmin, "s", 2)
	args = append([]any{id}, args...)
	var st model.Station
	err := r.db.QueryRow(ctx, "SELECT "+stationListSelectColumns+" FROM stations s WHERE s.id=$1 AND s.deleted_at IS NULL AND "+filter, args...).Scan(
		&st.ID, &st.UserID, &st.Name, &st.Country, &st.Province, &st.City, &st.District,
		&st.Address, &st.Capacity, &st.PanelCount, &st.Latitude, &st.Longitude, &st.Timezone,
		&st.Status, &st.CardImageURL, &st.CreatedAt, &st.UpdatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &st, nil
}

func stationOverviewReadFilters(stationPlan, devicePlan model.ScopePlan, systemAdmin bool, offset int) (string, []any) {
	stationFilter, args := OverviewScopeFilter(stationPlan, systemAdmin, "s", offset)
	deviceFilter, deviceArgs := OverviewScopeFilter(devicePlan, systemAdmin, "d", offset+len(args))
	return "s.deleted_at IS NULL AND d.deleted_at IS NULL AND " + stationFilter + " AND " + deviceFilter, append(args, deviceArgs...)
}

func (r *DeviceRepository) GetOverviewStationDevices(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationID int64) ([]*model.Device, error) {
	filter, args := stationOverviewReadFilters(stationPlan, devicePlan, systemAdmin, 2)
	args = append([]any{stationID}, args...)
	query := "SELECT " + deviceListSelectColumns + ` FROM devices d
		JOIN stations s ON s.id=d.station_id LEFT JOIN device_models dm ON dm.id=d.model_id
		LEFT JOIN v_device_latest rd ON rd.device_sn=d.sn WHERE d.station_id=$1 AND ` + filter + " ORDER BY d.sort_order,d.id"
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	devices := make([]*model.Device, 0)
	for rows.Next() {
		var d model.Device
		var station sql.NullInt64
		var lastOnline sql.NullTime
		if err := rows.Scan(&d.ID, &d.SN, &d.Model, &d.ModelID, &d.ModelCategory, &d.Manufacturer,
			&d.FirmwareArm, &d.FirmwareEsp, &d.FirmwareDSP, &d.FirmwareBMS, &d.MainVersion, &d.DeviceType,
			&d.RatedPower, &d.RatedVoltage, &d.RatedFreq, &d.BatteryVoltage, &d.BatteryType, &d.CellCount,
			&station, &d.UserID, &d.Status, &d.Timezone, &d.CurrentPower, &d.DailyEnergy, &lastOnline,
			&d.CreatedAt, &d.UpdatedAt, &d.StationName, &d.Alias, &d.Remark, &d.RatedPowerW, &d.TelemetryUpdatedAt); err != nil {
			return nil, err
		}
		if station.Valid {
			d.StationID = &station.Int64
		}
		if lastOnline.Valid {
			d.LastOnlineAt = &lastOnline.Time
		}
		devices = append(devices, &d)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	r.attachDeviceListBMS(ctx, devices)
	return devices, nil
}

type StationOverviewPower struct {
	PV      float64
	Load    float64
	Battery float64
	SOC     float64
}

func (r *DeviceRepository) GetOverviewStationPower(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationID int64) (StationOverviewPower, error) {
	filter, args := stationOverviewReadFilters(stationPlan, devicePlan, systemAdmin, 2)
	args = append([]any{stationID}, args...)
	rows, err := r.db.Query(ctx, `SELECT d.sn,l.pv_total_power,l.ac_active_power,l.battery_power,l.battery_soc
		FROM devices d JOIN stations s ON s.id=d.station_id JOIN device_latest_state l ON l.device_sn=d.sn
		WHERE d.station_id=$1 AND d.status IN (1,2) AND l.updated_at>NOW()-INTERVAL '5 minutes' AND l.updated_at<=NOW() AND `+filter, args...)
	if err != nil {
		return StationOverviewPower{}, err
	}
	defer rows.Close()
	type batteryReading struct {
		sn         string
		power, soc *float64
	}
	var readings []batteryReading
	var sns []string
	var result StationOverviewPower
	finite := func(v *float64) bool { return v != nil && !math.IsNaN(*v) && !math.IsInf(*v, 0) }
	for rows.Next() {
		var b batteryReading
		var pv, load *float64
		if err := rows.Scan(&b.sn, &pv, &load, &b.power, &b.soc); err != nil {
			return StationOverviewPower{}, err
		}
		if finite(pv) {
			result.PV += *pv
		}
		if finite(load) {
			result.Load += *load
		}
		readings = append(readings, b)
		sns = append(sns, b.sn)
	}
	if err := rows.Err(); err != nil {
		return StationOverviewPower{}, err
	}
	rows.Close()
	summaries := r.batchBMSSummaries(ctx, sns)
	socCount := 0
	for _, b := range readings {
		if summary, ok := summaries[b.sn]; ok {
			// A CMD08 snapshot replaces this inverter's legacy battery, including when stale/offline.
			if summary["bms_online"] != float64(1) || summary["layout"] != float64(0) {
				continue
			}
			voltage, vok := summary["voltage"].(float64)
			current, iok := summary["current"].(float64)
			power := voltage * current
			if vok && iok && finite(&power) {
				result.Battery += power
			}
			if soc, ok := summary["soc"].(float64); ok && soc >= 0 && soc <= 100 {
				result.SOC += soc
				socCount++
			}
		} else {
			if finite(b.power) {
				result.Battery += *b.power
			}
			if finite(b.soc) && *b.soc >= 0 && *b.soc <= 100 {
				result.SOC += *b.soc
				socCount++
			}
		}
	}
	if socCount > 0 {
		result.SOC /= float64(socCount)
	}
	return result, nil
}

func (r *StationRepository) GetOverviewStatistics(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error) {
	args := []any{stationID, startDate, endDate}
	query := `SELECT e.stat_date::timestamptz,ROUND(COALESCE(SUM(e.pv_energy),0)::numeric,2)::float8,SUM(e.max_ac_power),NULL::double precision,
		ROUND(COALESCE(SUM(e.pv_energy),0)::numeric,2)::float8,ROUND(COALESCE(SUM(e.charge_energy),0)::numeric,2)::float8,
		ROUND(COALESCE(SUM(e.discharge_energy),0)::numeric,2)::float8,ROUND(COALESCE(SUM(e.load_energy),0)::numeric,2)::float8
		FROM device_energy_day e JOIN devices d ON d.sn=e.device_sn JOIN stations s ON s.id=d.station_id
		WHERE d.station_id=$1 AND e.stat_date >= $2::date AND e.stat_date <= $3::date AND `
	end := " GROUP BY e.stat_date ORDER BY e.stat_date"
	if period == "hour" {
		args = append(args, tz)
		query = `SELECT h.bucket,SUM(h.avg_pv_power),SUM(h.avg_ac_power),SUM(h.avg_battery_power),
			ROUND(COALESCE(SUM(h.daily_pv_energy),0)::numeric,2)::float8,
			SUM(GREATEST(h.avg_battery_power,0))/1000.0,SUM(GREATEST(-h.avg_battery_power,0))/1000.0,SUM(h.avg_ac_power)/1000.0
			FROM device_telemetry_hour h JOIN devices d ON d.sn=h.device_sn JOIN stations s ON s.id=d.station_id
			WHERE d.station_id=$1 AND h.bucket>=($2::date::timestamp AT TIME ZONE $4)
			AND h.bucket<(($3::date+1)::timestamp AT TIME ZONE $4) AND `
		end = " GROUP BY h.bucket ORDER BY h.bucket"
	}
	filter, scopeArgs := stationOverviewReadFilters(stationPlan, devicePlan, systemAdmin, len(args)+1)
	args = append(args, scopeArgs...)
	rows, err := r.db.Query(ctx, query+filter+end, args...)
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
