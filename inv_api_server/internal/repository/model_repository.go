package repository

import (
	"context"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ModelRepository struct {
	db *pgxpool.Pool
}

func NewModelRepository(db *pgxpool.Pool) *ModelRepository {
	return &ModelRepository{db: db}
}

func (r *ModelRepository) ListModels(ctx context.Context) ([]model.DeviceModel, error) {
	rows, err := r.db.Query(ctx, `
		SELECT m.id, m.model_code, m.model_name, m.protocol_type,
			COALESCE((SELECT COUNT(*) FROM devices WHERE model_id = m.id), 0) AS device_count,
			m.create_time, m.update_time
		FROM device_model m
		ORDER BY m.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var models []model.DeviceModel
	for rows.Next() {
		var m model.DeviceModel
		if err := rows.Scan(&m.ID, &m.ModelCode, &m.ModelName, &m.ProtocolType,
			&m.DeviceCount, &m.CreateTime, &m.UpdateTime); err != nil {
			continue
		}
		models = append(models, m)
	}
	return models, nil
}

func (r *ModelRepository) GetModelByID(ctx context.Context, id int64) (*model.DeviceModel, error) {
	var m model.DeviceModel
	err := r.db.QueryRow(ctx, `
		SELECT id, model_code, model_name, protocol_type, create_time, update_time
		FROM device_model WHERE id = $1`, id).Scan(
		&m.ID, &m.ModelCode, &m.ModelName, &m.ProtocolType, &m.CreateTime, &m.UpdateTime)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

func (r *ModelRepository) GetModelByCode(ctx context.Context, code string) (*model.DeviceModel, error) {
	var m model.DeviceModel
	err := r.db.QueryRow(ctx, `
		SELECT id, model_code, model_name, protocol_type, create_time, update_time
		FROM device_model WHERE model_code = $1`, code).Scan(
		&m.ID, &m.ModelCode, &m.ModelName, &m.ProtocolType, &m.CreateTime, &m.UpdateTime)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

func (r *ModelRepository) CreateModel(ctx context.Context, m *model.DeviceModel) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO device_model (model_code, model_name, protocol_type)
		VALUES ($1, $2, $3)
		RETURNING id, create_time, update_time`,
		m.ModelCode, m.ModelName, m.ProtocolType).Scan(&m.ID, &m.CreateTime, &m.UpdateTime)
}

func (r *ModelRepository) UpdateModel(ctx context.Context, id int64, name *string, protocol *string) error {
	if name != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model SET model_name = $1, update_time = NOW() WHERE id = $2`, *name, id); err != nil {
			return err
		}
	}
	if protocol != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model SET protocol_type = $1, update_time = NOW() WHERE id = $2`, *protocol, id); err != nil {
			return err
		}
	}
	return nil
}

func (r *ModelRepository) DeleteModel(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, `DELETE FROM device_model WHERE id = $1`, id)
	return err
}

func (r *ModelRepository) GetFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, model_id, field_key, field_name, field_type, unit, sort, is_show, is_control, parse_rule
		FROM device_model_field
		WHERE model_id = $1
		ORDER BY sort, id`, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var fields []model.DeviceModelField
	for rows.Next() {
		var f model.DeviceModelField
		if err := rows.Scan(&f.ID, &f.ModelID, &f.FieldKey, &f.FieldName, &f.FieldType,
			&f.Unit, &f.Sort, &f.IsShow, &f.IsControl, &f.ParseRule); err != nil {
			continue
		}
		fields = append(fields, f)
	}
	return fields, nil
}

func (r *ModelRepository) CreateField(ctx context.Context, f *model.DeviceModelField) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO device_model_field (model_id, field_key, field_name, field_type, unit, sort, is_show, is_control, parse_rule)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id`,
		f.ModelID, f.FieldKey, f.FieldName, f.FieldType, f.Unit, f.Sort, f.IsShow, f.IsControl, f.ParseRule).Scan(&f.ID)
}

func (r *ModelRepository) UpdateField(ctx context.Context, fieldID int64, name *string, fieldType *string,
	unit *string, sort *int, isShow *bool, isControl *bool, parseRule *string) error {

	if name != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET field_name = $1 WHERE id = $2`, *name, fieldID); err != nil {
			return err
		}
	}
	if fieldType != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET field_type = $1 WHERE id = $2`, *fieldType, fieldID); err != nil {
			return err
		}
	}
	if unit != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET unit = $1 WHERE id = $2`, *unit, fieldID); err != nil {
			return err
		}
	}
	if sort != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET sort = $1 WHERE id = $2`, *sort, fieldID); err != nil {
			return err
		}
	}
	if isShow != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET is_show = $1 WHERE id = $2`, *isShow, fieldID); err != nil {
			return err
		}
	}
	if isControl != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET is_control = $1 WHERE id = $2`, *isControl, fieldID); err != nil {
			return err
		}
	}
	if parseRule != nil {
		if _, err := r.db.Exec(ctx, `UPDATE device_model_field SET parse_rule = $1 WHERE id = $2`, *parseRule, fieldID); err != nil {
			return err
		}
	}
	return nil
}

func (r *ModelRepository) DeleteField(ctx context.Context, fieldID int64) error {
	_, err := r.db.Exec(ctx, `DELETE FROM device_model_field WHERE id = $1`, fieldID)
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
		SELECT id, model_id, field_key, field_name, field_type, unit, sort, is_show, is_control, parse_rule
		FROM device_model_field
		WHERE model_id = $1 AND is_control = true
		ORDER BY sort, id`, modelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var fields []model.DeviceModelField
	for rows.Next() {
		var f model.DeviceModelField
		if err := rows.Scan(&f.ID, &f.ModelID, &f.FieldKey, &f.FieldName, &f.FieldType,
			&f.Unit, &f.Sort, &f.IsShow, &f.IsControl, &f.ParseRule); err != nil {
			continue
		}
		fields = append(fields, f)
	}
	return fields, nil
}

func (r *ModelRepository) GetUserAllowedSNs(ctx context.Context, userID int64) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT device_sn FROM user_device_rel WHERE user_id = $1`, userID)
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

	if _, err := tx.Exec(ctx, `DELETE FROM device_model_field WHERE model_id = $1`, modelID); err != nil {
		return err
	}

	for _, f := range fields {
		isShow := true
		if f.IsShow != nil {
			isShow = *f.IsShow
		}
		isControl := false
		if f.IsControl != nil {
			isControl = *f.IsControl
		}

		if _, err := tx.Exec(ctx, `
			INSERT INTO device_model_field (model_id, field_key, field_name, field_type, unit, sort, is_show, is_control, parse_rule)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
			modelID, f.FieldKey, f.FieldName, f.FieldType, f.Unit, f.Sort, isShow, isControl, f.ParseRule); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}


