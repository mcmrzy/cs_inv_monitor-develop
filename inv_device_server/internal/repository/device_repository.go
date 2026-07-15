package repository

import (
	"context"
	"encoding/json"
	"log"

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

func (r *DeviceRepository) GetStationIDBySN(ctx context.Context, sn string) (int64, error) {
	var stationID int64
	query := `SELECT COALESCE(station_id, 0) FROM devices WHERE sn = $1`
	err := r.db.QueryRow(ctx, query, sn).Scan(&stationID)
	if err != nil {
		return 0, nil
	}
	return stationID, nil
}

func (r *DeviceRepository) GetAllActiveModels(ctx context.Context) ([]model.DeviceModel, error) {
	query := `SELECT id, model_code, model_name, manufacturer, category, rated_power_kw,
		data_fields, field_mapping, mqtt_topics, COALESCE(description, ''), is_active, created_at, updated_at
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
	// 迁移至 device_model_fields（复数，migration 023），缺失列用 NULL/默认值填充
	query := `SELECT id, model_id, field_key,
		COALESCE(display_name_key, '') AS field_name,
		''::text AS field_type,
		COALESCE(display_unit, '') AS unit,
		sort_order AS sort,
		is_visible AS is_show,
		false AS is_control,
		''::text AS parse_rule,
		group_code AS group_name,
		NULL::jsonb AS control_params,
		created_at, updated_at
		FROM device_model_fields WHERE model_id = $1 ORDER BY sort_order, field_key`

	rows, err := r.db.Query(ctx, query, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var fields []model.DeviceModelField
	for rows.Next() {
		var f model.DeviceModelField
		var controlParamsJSON []byte
		err := rows.Scan(&f.ID, &f.ModelID, &f.FieldKey, &f.FieldName, &f.FieldType,
			&f.Unit, &f.Sort, &f.IsShow, &f.IsControl, &f.ParseRule,
			&f.GroupName, &controlParamsJSON, &f.CreatedAt, &f.UpdatedAt)
		if err != nil {
			return nil, err
		}
		if controlParamsJSON != nil {
			_ = json.Unmarshal(controlParamsJSON, &f.ControlParams)
		}
		fields = append(fields, f)
	}
	return fields, nil
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
	query := `
		SELECT jsonb_build_object(
			'device_sn', s.device_sn,
			'ac', jsonb_build_object(
				'voltage', s.ac_voltage, 'current', s.ac_current,
				'power', s.ac_active_power, 'frequency', s.ac_frequency,
				'load_percent', s.load_percent),
			'battery', jsonb_build_object(
				'soc', s.battery_soc, 'soh', s.battery_soh,
				'voltage', s.battery_voltage, 'current', s.battery_current),
			'pv', jsonb_build_object(
				'pv_voltage', s.pv1_voltage, 'pv_current', s.pv1_current,
				'pv_power', s.pv_total_power, 'mppt_state', COALESCE(s.mppt_state::text, '')),
			'sys_status', jsonb_build_object(
				'state', COALESCE(s.work_state::text, ''), 'fault_code', s.fault_code,
				'alarm_code', s.alarm_code, 'temp_inv', s.inverter_temperature,
				'temp_mos', s.mos_temperature, 'efficiency', s.efficiency),
			'energy', jsonb_build_object(
				'daily_pv', s.daily_pv_energy, 'total_pv', s.total_pv_energy,
				'daily_charge', s.daily_charge_energy, 'total_charge', s.total_charge_energy,
				'daily_discharge', s.daily_discharge_energy, 'total_discharge', s.total_discharge_energy,
				'daily_load', s.daily_load_energy, 'total_load', s.total_load_energy,
				'runtime_hours', s.runtime_hours),
			'cells', CASE WHEN c.device_sn IS NULL THEN NULL ELSE jsonb_build_object(
				'cell_count', jsonb_array_length(c.voltages),
				'voltages', c.voltages, 'temps', c.temperatures) END,
			'updated_at', s.updated_at)
		FROM device_latest_state s
		LEFT JOIN device_latest_cells c ON c.device_sn=s.device_sn
		WHERE s.device_sn=$1`
	var rawJSON string
	err := r.db.QueryRow(ctx, query, sn).Scan(&rawJSON)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	var rt model.DeviceRealtime
	if err := json.Unmarshal([]byte(rawJSON), &rt); err != nil {
		return nil, err
	}
	return &rt, nil
}

type DeviceSummary struct {
	SN      string `json:"sn"`
	ModelID int32  `json:"model_id"`
	Model   string `json:"model"`
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

func (r *DeviceRepository) GetModelProtocols(ctx context.Context, modelID int32) ([]model.DeviceModelProtocol, error) {
	// 迁移说明：旧表 device_model_protocol 已被 device_protocol_versions 替代（migration 023）。
	// 新表通过 device_models.heartbeat_protocol_id 关联，但不含 topic_pattern / parse_config 列。
	// best-effort 映射：protocol_code → parse_type, status='released' → is_active。
	query := `SELECT dpv.id, dm.id AS model_id,
			''::text AS topic_pattern,
			dpv.protocol_code AS parse_type,
			''::text AS parse_config,
			(dpv.status = 'released') AS is_active,
			COALESCE(dpv.released_at, dpv.created_at) AS created_at
		FROM device_protocol_versions dpv
		JOIN device_models dm ON dm.heartbeat_protocol_id = dpv.id
		WHERE dm.id = $1 AND dpv.status = 'released'
		ORDER BY dpv.id`

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
	if len(protocols) > 0 {
		log.Printf("[device_repository] GetModelProtocols(modelID=%d): migrated to device_protocol_versions, %d protocols found (partial column mapping: topic_pattern/parse_config unavailable)", modelID, len(protocols))
	}
	return protocols, nil
}
