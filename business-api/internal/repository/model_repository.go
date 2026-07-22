package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type ModelRepository struct {
	db  *pgxpool.Pool
	rdb *redis.Client
}

func NewModelRepository(db *pgxpool.Pool, rdb *redis.Client) *ModelRepository {
	return &ModelRepository{db: db, rdb: rdb}
}

func (r *ModelRepository) ListModels(ctx context.Context) ([]model.DeviceModel, error) {
	rows, err := r.db.Query(ctx, `
		SELECT m.id, m.model_code, m.model_name, COALESCE(m.manufacturer, ''), m.category, 
			CAST(m.rated_power_kw AS float8), COALESCE(m.description, ''), m.is_active,
			m.lifecycle_status, m.heartbeat_protocol_id, m.lock_version,
			COALESCE((SELECT COUNT(*) FROM devices WHERE model_id = m.id AND deleted_at IS NULL), 0) AS device_count,
			TO_CHAR(m.created_at, 'YYYY-MM-DD HH24:MI:SS'), TO_CHAR(m.updated_at, 'YYYY-MM-DD HH24:MI:SS')
		FROM device_models m
		ORDER BY m.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var models []model.DeviceModel
	for rows.Next() {
		var m model.DeviceModel
		var deviceCount int64
		if err := rows.Scan(&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer, &m.Category,
			&m.RatedPowerKw, &m.Description, &m.IsActive, &m.LifecycleStatus, &m.HeartbeatProtocolID,
			&m.LockVersion, &deviceCount, &m.CreatedAt, &m.UpdatedAt); err != nil {
			continue
		}
		m.DeviceCount = int(deviceCount)
		models = append(models, m)
	}
	return models, nil
}

func (r *ModelRepository) GetModelByID(ctx context.Context, id int64) (*model.DeviceModel, error) {
	var m model.DeviceModel
	err := r.db.QueryRow(ctx, `
		SELECT id, model_code, model_name, manufacturer, category, 
			rated_power_kw, description, is_active, lifecycle_status, heartbeat_protocol_id,
			lock_version, created_at, updated_at
		FROM device_models WHERE id = $1`, id).Scan(
		&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer, &m.Category,
		&m.RatedPowerKw, &m.Description, &m.IsActive, &m.LifecycleStatus,
		&m.HeartbeatProtocolID, &m.LockVersion, &m.CreatedAt, &m.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

func (r *ModelRepository) GetModelByCode(ctx context.Context, code string) (*model.DeviceModel, error) {
	var m model.DeviceModel
	err := r.db.QueryRow(ctx, `
		SELECT id, model_code, model_name, manufacturer, category, 
			rated_power_kw, description, is_active, lifecycle_status, heartbeat_protocol_id,
			lock_version, created_at, updated_at
		FROM device_models WHERE model_code = $1`, code).Scan(
		&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer, &m.Category,
		&m.RatedPowerKw, &m.Description, &m.IsActive, &m.LifecycleStatus,
		&m.HeartbeatProtocolID, &m.LockVersion, &m.CreatedAt, &m.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

func (r *ModelRepository) CreateModel(ctx context.Context, m *model.DeviceModel) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, description)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, created_at, updated_at`,
		m.ModelCode, m.ModelName, m.Manufacturer, m.Category, m.RatedPowerKw, m.Description).Scan(&m.ID, &m.CreatedAt, &m.UpdatedAt)
}

func (r *ModelRepository) UpdateModel(ctx context.Context, id int64, name *string, manufacturer *string, category *string, ratedPower *float64, description *string) error {
	if name != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_models SET model_name = $1, updated_at = NOW() WHERE id = $2`, *name, id); err != nil {
			return err
		}
	}
	if manufacturer != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_models SET manufacturer = $1, updated_at = NOW() WHERE id = $2`, *manufacturer, id); err != nil {
			return err
		}
	}
	if category != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_models SET category = $1, updated_at = NOW() WHERE id = $2`, *category, id); err != nil {
			return err
		}
	}
	if ratedPower != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_models SET rated_power_kw = $1, updated_at = NOW() WHERE id = $2`, *ratedPower, id); err != nil {
			return err
		}
	}
	if description != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_models SET description = $1, updated_at = NOW() WHERE id = $2`, *description, id); err != nil {
			return err
		}
	}
	return nil
}

func (r *ModelRepository) DeleteModel(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, `DELETE FROM device_models WHERE id = $1`, id)
	return err
}

func (r *ModelRepository) GetFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, model_id, field_key,
			COALESCE(display_name_key, '') AS field_name,
			NULL AS field_type,
			COALESCE(display_unit, '') AS unit,
			sort_order AS sort,
			is_visible AS is_show,
			false AS is_control,
			NULL AS parse_rule,
			COALESCE(group_code, '') AS group_name,
			'{}'::jsonb AS control_params
		FROM device_model_fields
		WHERE model_id = $1
		ORDER BY sort_order, id`, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var fields []model.DeviceModelField
	for rows.Next() {
		var f model.DeviceModelField
		var controlParamsJSON []byte
		if err := rows.Scan(&f.ID, &f.ModelID, &f.FieldKey, &f.FieldName, &f.FieldType,
			&f.Unit, &f.Sort, &f.IsShow, &f.IsControl, &f.ParseRule, &f.GroupName, &controlParamsJSON); err != nil {
			continue
		}
		if len(controlParamsJSON) > 0 {
			json.Unmarshal(controlParamsJSON, &f.ControlParams)
		}
		fields = append(fields, f)
	}
	return fields, nil
}

func (r *ModelRepository) CreateField(ctx context.Context, f *model.DeviceModelField) error {
	groupCode := f.GroupName
	if groupCode == "" {
		groupCode = "general"
	}
	return r.db.QueryRow(ctx, `
		INSERT INTO device_model_fields (model_id, field_key, display_name_key, display_unit, sort_order, is_visible, group_code)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id`,
		f.ModelID, f.FieldKey, f.FieldName, f.Unit, f.Sort, f.IsShow, groupCode).Scan(&f.ID)
}

func (r *ModelRepository) UpdateField(ctx context.Context, fieldID int64, name *string, fieldType *string,
	unit *string, sort *int, isShow *bool, isControl *bool, parseRule *string, groupName *string) error {

	if name != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_fields SET display_name_key = $1, updated_at = NOW() WHERE id = $2`, *name, fieldID); err != nil {
			return err
		}
	}
	// fieldType: no equivalent column in device_model_fields (deprecated)
	if unit != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_fields SET display_unit = $1, updated_at = NOW() WHERE id = $2`, *unit, fieldID); err != nil {
			return err
		}
	}
	if sort != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_fields SET sort_order = $1, updated_at = NOW() WHERE id = $2`, *sort, fieldID); err != nil {
			return err
		}
	}
	if isShow != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_fields SET is_visible = $1, updated_at = NOW() WHERE id = $2`, *isShow, fieldID); err != nil {
			return err
		}
	}
	// isControl: no equivalent column in device_model_fields (deprecated)
	// parseRule: no equivalent column in device_model_fields (deprecated)
	if groupName != nil {
		groupCode := *groupName
		if groupCode == "" {
			groupCode = "general"
		}
		if _, err := r.db.Exec(ctx, `UPDATE device_model_fields SET group_code = $1, updated_at = NOW() WHERE id = $2`, groupCode, fieldID); err != nil {
			return err
		}
	}
	return nil
}

func (r *ModelRepository) DeleteField(ctx context.Context, fieldID int64) error {
	_, err := r.db.Exec(ctx, `DELETE FROM device_model_fields WHERE id = $1`, fieldID)
	return err
}

type BatchFieldItem struct {
	ID        int64   `json:"id"`
	FieldKey  string  `json:"field_key"`
	FieldName string  `json:"field_name"`
	FieldType string  `json:"field_type"`
	Unit      string  `json:"unit"`
	Sort      int     `json:"sort"`
	IsShow    *bool   `json:"is_show"`
	IsControl *bool   `json:"is_control"`
	ParseRule *string `json:"parse_rule"`
	GroupName string  `json:"group_name"`
}

func (r *ModelRepository) GetModelIDByDeviceSN(ctx context.Context, sn string) (int64, error) {
	var modelID int64
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(d.model_id, 0) FROM devices d WHERE d.sn = $1 AND d.deleted_at IS NULL`, sn).Scan(&modelID)
	if err != nil {
		return 0, err
	}
	return modelID, nil
}

func (r *ModelRepository) GetControlFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, model_id, command_code AS field_key,
			COALESCE(display_name_key, '') AS field_name,
			'' AS field_type, '' AS unit, 0 AS sort,
			true AS is_show, true AS is_control,
			NULL AS parse_rule, '' AS group_name,
			c.parameter_schema AS control_params
		FROM device_model_commands AS c
		WHERE model_id = $1 AND is_enabled = true
		ORDER BY command_code, id`, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var fields []model.DeviceModelField
	for rows.Next() {
		var f model.DeviceModelField
		var controlParamsJSON []byte
		if err := rows.Scan(&f.ID, &f.ModelID, &f.FieldKey, &f.FieldName, &f.FieldType,
			&f.Unit, &f.Sort, &f.IsShow, &f.IsControl, &f.ParseRule, &f.GroupName, &controlParamsJSON); err != nil {
			continue
		}
		if len(controlParamsJSON) > 0 {
			json.Unmarshal(controlParamsJSON, &f.ControlParams)
		}
		fields = append(fields, f)
	}
	return fields, nil
}

// ==================== Protocol CRUD ====================

func (r *ModelRepository) GetProtocolsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelProtocol, error) {
	rows, err := r.db.Query(ctx, `
		SELECT p.id, $1 AS model_id,
			p.protocol_code AS topic_pattern,
			p.status AS parse_type,
			'{}'::jsonb AS parse_config,
			(p.status = 'released') AS is_active,
			COALESCE(TO_CHAR(p.released_at, 'YYYY-MM-DD HH24:MI:SS'), TO_CHAR(p.created_at, 'YYYY-MM-DD HH24:MI:SS'))
		FROM device_protocol_versions p
		JOIN device_models m ON m.heartbeat_protocol_id = p.id
		WHERE m.id = $1
		ORDER BY p.id`, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var protocols []model.DeviceModelProtocol
	for rows.Next() {
		var p model.DeviceModelProtocol
		var configJSON []byte
		if err := rows.Scan(&p.ID, &p.ModelID, &p.TopicPattern, &p.ParseType, &configJSON, &p.IsActive, &p.CreatedAt); err != nil {
			continue
		}
		if len(configJSON) > 0 {
			json.Unmarshal(configJSON, &p.ParseConfig)
		}
		protocols = append(protocols, p)
	}
	return protocols, nil
}

func (r *ModelRepository) CreateProtocol(ctx context.Context, p *model.DeviceModelProtocol) error {
	return fmt.Errorf("CreateProtocol is deprecated, use CreateProtocolVersion + BindProtocolVersion instead")
}

func (r *ModelRepository) UpdateProtocol(ctx context.Context, id int64, topicPattern *string, parseType *string, parseConfig map[string]interface{}, isActive *bool) error {
	return fmt.Errorf("UpdateProtocol is deprecated, use protocol version API instead")
}

func (r *ModelRepository) DeleteProtocol(ctx context.Context, id int64) error {
	return fmt.Errorf("DeleteProtocol is deprecated, use protocol version API instead")
}

// GetModelIDByDeviceSNWithFields returns model ID and whether the device has a model configured
func (r *ModelRepository) GetDeviceModelInfo(ctx context.Context, sn string) (modelID int64, modelCode string, err error) {
	err = r.db.QueryRow(ctx, `
		SELECT COALESCE(d.model_id, 0), COALESCE(d.model, '')
		FROM devices d WHERE d.sn = $1 AND d.deleted_at IS NULL`, sn).Scan(&modelID, &modelCode)
	return
}

func (r *ModelRepository) GetUserAllowedSNs(ctx context.Context, userID int64) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT device_sn FROM v_user_device_access WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sns []string
	for rows.Next() {
		var sn string
		if err := rows.Scan(&sn); err != nil {
			continue
		}
		sns = append(sns, sn)
	}
	return sns, nil
}

func (r *ModelRepository) BatchUpsertFields(ctx context.Context, modelID int64, fields []BatchFieldItem) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `DELETE FROM device_model_fields WHERE model_id = $1`, modelID); err != nil {
		return err
	}

	for _, f := range fields {
		isShow := true
		if f.IsShow != nil {
			isShow = *f.IsShow
		}
		groupCode := f.GroupName
		if groupCode == "" {
			groupCode = "general"
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO device_model_fields (model_id, field_key, display_name_key, display_unit, sort_order, is_visible, group_code)
			VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			modelID, f.FieldKey, f.FieldName, f.Unit, f.Sort, isShow, groupCode); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

type ModelWithCount struct {
	ID           int64   `json:"id"`
	ModelCode    string  `json:"model_code"`
	ModelName    string  `json:"model_name"`
	Manufacturer string  `json:"manufacturer"`
	Category     string  `json:"category"`
	RatedPowerKW float64 `json:"rated_power_kw"`
	Description  string  `json:"description"`
	IsActive     bool    `json:"is_active"`
	CreatedAt    string  `json:"created_at"`
	UpdatedAt    string  `json:"updated_at"`
	DeviceCount  int     `json:"device_count"`
}

func (r *ModelRepository) ListAllWithDeviceCount(ctx context.Context) ([]ModelWithCount, error) {
	rows, err := r.db.Query(ctx, `
		SELECT dm.id, dm.model_code, dm.model_name, COALESCE(dm.manufacturer, ''), dm.category,
		       CAST(dm.rated_power_kw AS float8), COALESCE(dm.description, ''), dm.is_active,
		       TO_CHAR(dm.created_at, 'YYYY-MM-DD HH24:MI:SS'), TO_CHAR(dm.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
		       COALESCE((SELECT COUNT(*) FROM devices WHERE model = dm.model_code AND deleted_at IS NULL), 0) AS device_count
		FROM device_models dm ORDER BY dm.id DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var models []ModelWithCount
	for rows.Next() {
		var m ModelWithCount
		var deviceCount int64
		if err := rows.Scan(&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer,
			&m.Category, &m.RatedPowerKW, &m.Description, &m.IsActive,
			&m.CreatedAt, &m.UpdatedAt, &deviceCount); err != nil {
			continue
		}
		m.DeviceCount = int(deviceCount)
		models = append(models, m)
	}
	return models, nil
}
