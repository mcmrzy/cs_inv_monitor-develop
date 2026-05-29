package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"inv-device-server/internal/model"

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

	if rt.AC != nil {
		totalPower = rt.AC.Power
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

	// 更新设备状态为在线
	statusQuery := `
		UPDATE devices SET status = 1, last_online_at = NOW(), updated_at = NOW() 
		WHERE sn = $1
	`
	_, err = r.db.Exec(ctx, statusQuery, sn)
	if err != nil {
		return fmt.Errorf("update device status: %w", err)
	}

	return nil
}

func (r *DeviceRepository) UpsertDeviceInfo(ctx context.Context, info *model.DeviceInfo) error {
	rawBytes, _ := json.Marshal(info)
	rawJSON := string(rawBytes)

	query := `
		INSERT INTO device_telemetry (device_sn, model_code, topic, data, time, created_at)
		VALUES ($1, $2, $3, $4::jsonb, NOW(), NOW())
	`
	_, err := r.db.Exec(ctx, query, info.SN, info.Model, "info", rawJSON)
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

	r.syncDeviceModelID(ctx, info.SN, info.Model)

	return nil
}

func (r *DeviceRepository) syncDeviceModelID(ctx context.Context, sn, modelCode string) {
	_, err := r.db.Exec(ctx, `
		UPDATE devices SET model_id = dm.id
		FROM device_models dm
		WHERE devices.sn = $1 AND dm.model_code = $2 AND devices.model_id IS NULL
	`, sn, modelCode)
	if err != nil {
	}
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

// ==================== 新增：型号元数据查询 ====================

func (r *DeviceRepository) GetAllActiveModels(ctx context.Context) ([]model.DeviceModel, error) {
	query := `SELECT id, model_code, model_name, manufacturer, category, rated_power_kw,
		data_fields, field_mapping, mqtt_topics, description, is_active, created_at, updated_at
		FROM device_models WHERE is_active = true ORDER BY id`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var models []model.DeviceModel
	for rows.Next() {
		var m model.DeviceModel
		err := rows.Scan(&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer, &m.Category,
			&m.RatedPowerKW, &m.DataFields, &m.FieldMapping, &m.MQTTTopics,
			&m.Description, &m.IsActive, &m.CreatedAt, &m.UpdatedAt)
		if err != nil {
			return nil, err
		}
		models = append(models, m)
	}
	return models, nil
}

func (r *DeviceRepository) GetModelFields(ctx context.Context, modelID int32) ([]model.DeviceModelField, error) {
	query := `SELECT id, model_id, field_key, field_name, field_type, unit, sort,
		is_show, is_control, parse_rule, created_at, updated_at
		FROM device_model_field WHERE model_id = $1 ORDER BY sort, field_key`

	rows, err := r.db.Query(ctx, query, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var fields []model.DeviceModelField
	for rows.Next() {
		var f model.DeviceModelField
		err := rows.Scan(&f.ID, &f.ModelID, &f.FieldKey, &f.FieldName, &f.FieldType,
			&f.Unit, &f.Sort, &f.IsShow, &f.IsControl, &f.ParseRule,
			&f.CreatedAt, &f.UpdatedAt)
		if err != nil {
			return nil, err
		}
		fields = append(fields, f)
	}
	return fields, nil
}

func (r *DeviceRepository) GetModelByCode(ctx context.Context, modelCode string) (*model.DeviceModel, error) {
	query := `SELECT id, model_code, model_name, manufacturer, category, rated_power_kw,
		data_fields, field_mapping, mqtt_topics, description, is_active, created_at, updated_at
		FROM device_models WHERE model_code = $1`

	var m model.DeviceModel
	err := r.db.QueryRow(ctx, query, modelCode).Scan(
		&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer, &m.Category,
		&m.RatedPowerKW, &m.DataFields, &m.FieldMapping, &m.MQTTTopics,
		&m.Description, &m.IsActive, &m.CreatedAt, &m.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &m, nil
}

func (r *DeviceRepository) GetDeviceModelID(ctx context.Context, sn string) (int32, error) {
	var modelID int32
	err := r.db.QueryRow(ctx, `SELECT COALESCE(model_id, 0) FROM devices WHERE sn = $1`, sn).Scan(&modelID)
	if err != nil {
		return 0, nil
	}
	return modelID, nil
}

func (r *DeviceRepository) GetLatestRealtimeData(ctx context.Context, sn string) (*model.DeviceRealtime, error) {
	query := `SELECT data FROM device_telemetry WHERE device_sn = $1 ORDER BY time DESC LIMIT 1`
	var rawJSON string
	err := r.db.QueryRow(ctx, query, sn).Scan(&rawJSON)
	if err != nil {
		return nil, err
	}
	var rt model.DeviceRealtime
	if err := json.Unmarshal([]byte(rawJSON), &rt); err != nil {
		return nil, err
	}
	return &rt, nil
}

type DeviceSummary struct {
	SN       string `json:"sn"`
	ModelID  int32  `json:"model_id"`
	Model    string `json:"model"`
}

func (r *DeviceRepository) GetAllDevices(ctx context.Context) ([]DeviceSummary, error) {
	rows, err := r.db.Query(ctx, `SELECT sn, COALESCE(model_id, 0) FROM devices WHERE sn != ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []DeviceSummary
	for rows.Next() {
		var d DeviceSummary
		if err := rows.Scan(&d.SN, &d.ModelID); err != nil {
			continue
		}
		devices = append(devices, d)
	}
	return devices, nil
}

func (r *DeviceRepository) InsertTelemetry(ctx context.Context, sn string, topic string, data []byte) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO device_telemetry (device_sn, topic, data, time)
		VALUES ($1, $2, $3::jsonb, NOW())
	`, sn, topic, string(data))
	return err
}

func (r *DeviceRepository) GetModelProtocols(ctx context.Context, modelID int32) ([]model.DeviceModelProtocol, error) {
	query := `SELECT id, model_id, topic_pattern, parse_type, parse_config, is_active, created_at
		FROM device_model_protocol WHERE model_id = $1 AND is_active = true ORDER BY id`

	rows, err := r.db.Query(ctx, query, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var protocols []model.DeviceModelProtocol
	for rows.Next() {
		var p model.DeviceModelProtocol
		err := rows.Scan(&p.ID, &p.ModelID, &p.TopicPattern, &p.ParseType,
			&p.ParseConfig, &p.IsActive, &p.CreatedAt)
		if err != nil {
			return nil, err
		}
		protocols = append(protocols, p)
	}
	return protocols, nil
}
