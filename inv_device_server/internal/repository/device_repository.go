package repository

import (
	"context"
	"encoding/json"

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
	query := `SELECT id, model_id, field_key, field_name, field_type, COALESCE(unit, ''), sort,
		is_show, is_control, COALESCE(parse_rule, ''), created_at, updated_at
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
