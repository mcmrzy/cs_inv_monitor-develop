package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"inv-device-server/internal/model"
	"inv-device-server/pkg/sn"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type DeviceRepository struct {
	db *pgxpool.Pool
}

func NewDeviceRepository(db *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{db: db}
}

func (r *DeviceRepository) Db() *pgxpool.Pool {
	return r.db
}

func (r *DeviceRepository) UpsertRealtime(ctx context.Context, rt *model.DeviceRealtime) error {
	rawBytes, _ := json.Marshal(rt)
	rawJSON := string(rawBytes)

	sn := rt.DeviceSN

	var totalPower float64 = 0
	var dailyEnergy float64 = 0
	var workState string
	var faultCode string
	var internalTemp float64 = 0
	var pvPower float64 = 0
	var battVoltage float64 = 0
	var battCurrent float64 = 0
	var battSoc float64 = 0

	if rt.AC != nil {
		totalPower = rt.AC.Power
	}
	if rt.PV != nil {
		pvPower = rt.PV.PVPower
	}
	if rt.Battery != nil {
		battVoltage = rt.Battery.Voltage
		battCurrent = rt.Battery.Current
		battSoc = rt.Battery.SOC
	}
	if rt.Energy != nil {
		dailyEnergy = rt.Energy.DailyPV
	}
	if rt.SysStatus != nil {
		workState = rt.SysStatus.State
		faultCode = fmt.Sprintf("%d", rt.SysStatus.FaultCode)
		internalTemp = rt.SysStatus.TempInv
	}

	telemetryQuery := `INSERT INTO device_telemetry (device_sn, topic, data, total_active_power, daily_energy, work_state, fault_code, internal_temperature, time, created_at) VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $8, NOW(), NOW())`
	_, err := r.db.Exec(ctx, telemetryQuery, sn, "data/realtime", rawJSON, totalPower, dailyEnergy, workState, faultCode, internalTemp)
	if err != nil {
		return fmt.Errorf("insert telemetry: %w", err)
	}

	rtQuery := `
		INSERT INTO device_realtime_data (device_sn, daily_power_yields, total_active_power, total_power,
			pv1_power, output_power, battery_voltage, battery_current, battery_soc, data_time, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
		ON CONFLICT (device_sn) DO UPDATE SET
			daily_power_yields = EXCLUDED.daily_power_yields,
			total_active_power = EXCLUDED.total_active_power,
			total_power = EXCLUDED.total_power,
			pv1_power = EXCLUDED.pv1_power,
			output_power = EXCLUDED.output_power,
			battery_voltage = EXCLUDED.battery_voltage,
			battery_current = EXCLUDED.battery_current,
			battery_soc = EXCLUDED.battery_soc,
			data_time = NOW(),
			updated_at = NOW()
	`
	_, err = r.db.Exec(ctx, rtQuery, sn, dailyEnergy, totalPower, totalPower, pvPower, totalPower, battVoltage, battCurrent, battSoc)
	if err != nil {
		return fmt.Errorf("upsert realtime: %w", err)
	}
	return nil
}

func (r *DeviceRepository) UpsertDeviceInfo(ctx context.Context, info *model.DeviceInfo) error {
	if !sn.ValidateSN(info.SN) {
		return fmt.Errorf("invalid SN format: %s", info.SN)
	}

	rawBytes, _ := json.Marshal(info)
	rawJSON := string(rawBytes)

	query := `INSERT INTO device_telemetry (device_sn, topic, data, time, created_at) VALUES ($1, $2, $3::jsonb, NOW(), NOW())`
	_, err := r.db.Exec(ctx, query, info.SN, "info", rawJSON)
	if err != nil {
		return fmt.Errorf("insert device info telemetry: %w", err)
	}

	upsertQuery := `
		INSERT INTO devices (sn, model, manufacturer, firmware_arm, firmware_esp, device_type,
			rated_power, rated_voltage, rated_freq, battery_voltage, battery_type, cell_count,
			user_id, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 0, 1, NOW(), NOW())
		ON CONFLICT (sn) DO UPDATE SET
			model = EXCLUDED.model,
			manufacturer = EXCLUDED.manufacturer,
			firmware_arm = EXCLUDED.firmware_arm,
			firmware_esp = EXCLUDED.firmware_esp,
			device_type = EXCLUDED.device_type,
			rated_power = EXCLUDED.rated_power,
			rated_voltage = EXCLUDED.rated_voltage,
			rated_freq = EXCLUDED.rated_freq,
			battery_voltage = EXCLUDED.battery_voltage,
			battery_type = EXCLUDED.battery_type,
			cell_count = EXCLUDED.cell_count,
			updated_at = NOW()
	`

	_, err = r.db.Exec(ctx, upsertQuery,
		info.SN, info.Model, info.Manufacturer,
		info.FirmwareARM, info.FirmwareESP,
		info.Type,
		info.RatedPower, info.RatedVoltage, info.RatedFreq,
		info.BatteryVoltage, info.BatteryType, info.CellCount,
	)

	if err != nil {
		return fmt.Errorf("upsert device info: %w", err)
	}
	return nil
}

func (r *DeviceRepository) InsertAlarm(ctx context.Context, alarm *model.AlarmData) error {
	triggerJSON, _ := json.Marshal(alarm.Trigger)

	query := `
		INSERT INTO device_alarms (device_sn, event_type, source, fault_code, fault_desc, alarm_code, trigger_info, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW())
	`

	_, err := r.db.Exec(ctx, query,
		alarm.SN, alarm.Event, alarm.Source,
		alarm.FaultCode, alarm.FaultDesc, alarm.AlarmCode,
		string(triggerJSON),
	)

	if err != nil {
		return fmt.Errorf("insert alarm: %w", err)
	}
	return nil
}

func (r *DeviceRepository) UpsertDayData(ctx context.Context, sn string, energy *model.EnergyData) error {
	runMinutes := int(energy.RuntimeHours * 60)
	query := `
		INSERT INTO device_day_data (device_sn, data_date, energy_produce, run_minutes, created_at)
		VALUES ($1, CURRENT_DATE, $2, $3, NOW())
		ON CONFLICT (device_sn, data_date) DO UPDATE SET
			energy_produce = EXCLUDED.energy_produce,
			run_minutes = EXCLUDED.run_minutes
	`
	_, err := r.db.Exec(ctx, query, sn, energy.DailyPV, runMinutes)
	if err != nil {
		return fmt.Errorf("upsert day data: %w", err)
	}
	return nil
}

func (r *DeviceRepository) UpsertStationDayData(ctx context.Context, stationID int64, energy float64, income float64) error {
	query := `
		INSERT INTO station_day_data (station_id, data_date, energy_produce, income, device_count, online_count, fault_count, created_at)
		VALUES ($1, CURRENT_DATE, $2, $3, 0, 0, 0, NOW())
		ON CONFLICT (station_id, data_date) DO UPDATE SET
			energy_produce = (
				SELECT COALESCE(SUM(energy_produce), 0)
				FROM device_day_data
				WHERE device_sn IN (
					SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL
				) AND data_date = CURRENT_DATE
			),
			income = station_day_data.income + EXCLUDED.income
	`
	_, err := r.db.Exec(ctx, query, stationID, energy, income)
	if err != nil {
		return fmt.Errorf("upsert station day data: %w", err)
	}
	return nil
}

func (r *DeviceRepository) GetStationIDBySN(ctx context.Context, sn string) (int64, error) {
	var stationID int64
	query := `SELECT COALESCE(station_id, 0) FROM devices WHERE sn = $1`
	err := r.db.QueryRow(ctx, query, sn).Scan(&stationID)
	if err != nil {
		return 0, nil
	}
	return stationID, nil
}

func (r *DeviceRepository) InsertCmdLog(ctx context.Context, sn string, cmd string, result string, message string) error {
	query := `
		INSERT INTO device_cmd_logs (device_sn, cmd, result, message, sent_at)
		VALUES ($1, $2, $3, $4, NOW())
	`
	_, err := r.db.Exec(ctx, query, sn, cmd, result, message)
	return err
}

func (r *DeviceRepository) GetDeviceBySN(ctx context.Context, sn string) (*model.Device, error) {
	query := `
		SELECT id, sn, model, rated_power, firmware_arm, firmware_esp,
			   status, last_online_at, ip_address, city,
			   created_at, updated_at
		FROM devices WHERE sn = $1 AND deleted_at IS NULL
	`

	var device model.Device
	err := r.db.QueryRow(ctx, query, sn).Scan(
		&device.ID, &device.SN, &device.Model, &device.RatedPower,
		&device.FirmwareARM, &device.FirmwareESP,
		&device.Status, &device.LastOnlineAt,
		&device.IPAddress, &device.City,
		&device.CreatedAt, &device.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &device, nil
}

func (r *DeviceRepository) UpdateDeviceStatus(ctx context.Context, sn string, status int) error {
	query := `
		UPDATE devices SET
			status = $1,
			last_online_at = CASE WHEN $1 = 1 THEN NOW() ELSE last_online_at END,
			updated_at = NOW()
		WHERE sn = $2
	`
	result, err := r.db.Exec(ctx, query, status, sn)
	if err != nil {
		return fmt.Errorf("update devices status: %w", err)
	}

	if result.RowsAffected() == 0 {
		insertQuery := `INSERT INTO devices (sn, status, last_online_at, created_at, updated_at) VALUES ($1, $2, CASE WHEN $2=1 THEN NOW() ELSE NULL END, NOW(), NOW())`
		_, err = r.db.Exec(ctx, insertQuery, sn, status)
		if err != nil {
			return fmt.Errorf("insert new device: %w", err)
		}
	}

	return nil
}
