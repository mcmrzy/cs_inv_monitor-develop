package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
)

func (r *ModelRepository) BuildCommandArgs(ctx context.Context, sn, commandCode string, params map[string]interface{}) ([]interface{}, bool, error) {
	var raw []byte
	var enabled bool
	err := r.db.QueryRow(ctx, `
		SELECT c.parameter_schema,c.is_enabled
		FROM devices d JOIN device_model_commands c ON c.model_id=d.model_id
		WHERE d.sn=$1 AND d.deleted_at IS NULL AND c.command_code=$2`, sn, commandCode).Scan(&raw, &enabled)
	if err == pgx.ErrNoRows {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	if !enabled {
		return nil, true, fmt.Errorf("command is disabled")
	}
	args, err := validateAndBuildCommandArgs(raw, params)
	return args, true, err
}

func (r *ModelRepository) CommandCapability(ctx context.Context, sn, commandCode string) (bool, bool, error) {
	var enabled bool
	err := r.db.QueryRow(ctx, `SELECT c.is_enabled FROM devices d
		JOIN device_model_commands c ON c.model_id=d.model_id
		WHERE d.sn=$1 AND d.deleted_at IS NULL AND c.command_code=$2`, sn, commandCode).Scan(&enabled)
	if err == pgx.ErrNoRows {
		return false, false, nil
	}
	return true, enabled, err
}

func scanJSONRows(rows interface {
	Next() bool
	Scan(...any) error
	Err() error
	Close()
}) ([]map[string]any, error) {
	defer rows.Close()
	result := make([]map[string]any, 0)
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, err
		}
		var item map[string]any
		if err := json.Unmarshal(raw, &item); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}

func (r *ModelRepository) ListFieldCatalog(ctx context.Context) ([]map[string]any, error) {
	rows, err := r.db.Query(ctx, `SELECT to_jsonb(c) FROM telemetry_field_catalog c ORDER BY category,field_key`)
	if err != nil {
		return nil, err
	}
	return scanJSONRows(rows)
}

func (r *ModelRepository) ListFieldCapabilities(ctx context.Context, modelID int64) ([]map[string]any, error) {
	rows, err := r.db.Query(ctx, `
		SELECT jsonb_build_object(
			'id',f.id,'model_id',$1,'field_key',c.field_key,'field_type',c.field_type,
			'base_unit',c.base_unit,'category',c.category,'display_name_key',f.display_name_key,
			'group_code',COALESCE(f.group_code,c.category),'display_unit',f.display_unit,
			'decimal_places',COALESCE(f.decimal_places,1),'sort_order',COALESCE(f.sort_order,0),
			'is_supported',COALESCE(f.is_supported,false),'is_visible',COALESCE(f.is_visible,false),
			'show_realtime',COALESCE(f.show_realtime,false),'show_history',COALESCE(f.show_history,false),
			'allow_compare',COALESCE(f.allow_compare,false),'allow_alarm_rule',COALESCE(f.allow_alarm_rule,false),
			'default_chart',COALESCE(f.default_chart,false))
		FROM telemetry_field_catalog c LEFT JOIN device_model_fields f ON f.field_key=c.field_key AND f.model_id=$1
		WHERE c.status='active' ORDER BY c.category,COALESCE(f.sort_order,0),c.field_key`, modelID)
	if err != nil {
		return nil, err
	}
	return scanJSONRows(rows)
}

func (r *ModelRepository) ListModelCommandsV2(ctx context.Context, modelID int64) ([]map[string]any, error) {
	rows, err := r.db.Query(ctx, `SELECT to_jsonb(c) FROM device_model_commands c WHERE model_id=$1 ORDER BY risk_level,command_code`, modelID)
	if err != nil {
		return nil, err
	}
	return scanJSONRows(rows)
}

func (r *ModelRepository) GetProtocolSchema(ctx context.Context, modelID int64) (map[string]any, error) {
	var raw []byte
	err := r.db.QueryRow(ctx, `
		SELECT jsonb_build_object(
			'id',p.id,'protocol_code',p.protocol_code,'version',p.version,'schema_hash',p.schema_hash,
			'status',p.status,'released_at',p.released_at,
			'fields',COALESCE((SELECT jsonb_agg(jsonb_build_object(
				'group_code',f.group_code,'field_index',f.field_index,'field_key',f.field_key,
				'wire_type',f.wire_type,'scale',f.scale,'minimum',f.minimum,'maximum',f.maximum,
				'nullable',f.nullable,'status',f.status) ORDER BY f.group_code,f.field_index)
				FROM device_protocol_fields f WHERE f.protocol_version_id=p.id),'[]'::jsonb))
		FROM device_models m JOIN device_protocol_versions p ON p.id=m.heartbeat_protocol_id
		WHERE m.id=$1`, modelID).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var result map[string]any
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	return result, nil
}

func (r *ModelRepository) RetireModel(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, `UPDATE device_models SET lifecycle_status='retired',is_active=false,updated_at=NOW(),lock_version=lock_version+1 WHERE id=$1`, id)
	return err
}

type FieldCapabilityUpdate struct {
	IsVisible      *bool `json:"is_visible"`
	ShowRealtime   *bool `json:"show_realtime"`
	ShowHistory    *bool `json:"show_history"`
	AllowCompare   *bool `json:"allow_compare"`
	AllowAlarmRule *bool `json:"allow_alarm_rule"`
	DefaultChart   *bool `json:"default_chart"`
}

func (r *ModelRepository) UpdateFieldCapability(ctx context.Context, modelID int64, fieldKey string, in FieldCapabilityUpdate) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_model_fields SET
			is_visible=COALESCE($3,is_visible),show_realtime=COALESCE($4,show_realtime),
			show_history=COALESCE($5,show_history),allow_compare=COALESCE($6,allow_compare),
			allow_alarm_rule=COALESCE($7,allow_alarm_rule),default_chart=COALESCE($8,default_chart),
			updated_at=NOW()
		WHERE model_id=$1 AND field_key=$2`, modelID, fieldKey, in.IsVisible, in.ShowRealtime,
		in.ShowHistory, in.AllowCompare, in.AllowAlarmRule, in.DefaultChart)
	return err
}

type CommandCapabilityUpdate struct {
	TimeoutSeconds *int  `json:"timeout_seconds"`
	RequiresOnline *bool `json:"requires_online"`
	IsEnabled      *bool `json:"is_enabled"`
}

func (r *ModelRepository) UpdateCommandCapability(ctx context.Context, modelID int64, commandCode string, in CommandCapabilityUpdate) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_model_commands SET timeout_seconds=COALESCE($3,timeout_seconds),
			requires_online=COALESCE($4,requires_online),is_enabled=COALESCE($5,is_enabled),updated_at=NOW()
		WHERE model_id=$1 AND command_code=$2`, modelID, commandCode, in.TimeoutSeconds, in.RequiresOnline, in.IsEnabled)
	return err
}

type FieldCatalogInput struct {
	FieldKey          string          `json:"field_key"`
	FieldType         string          `json:"field_type"`
	BaseUnit          *string         `json:"base_unit"`
	Category          string          `json:"category"`
	Description       string          `json:"description"`
	IsTimeseries      bool            `json:"is_timeseries"`
	IsAggregatable    bool            `json:"is_aggregatable"`
	AllowedAggregates json.RawMessage `json:"allowed_aggregates"`
	Status            string          `json:"status"`
}

func (r *ModelRepository) UpsertFieldCatalog(ctx context.Context, in FieldCatalogInput, operatorID int64) error {
	if len(in.AllowedAggregates) == 0 {
		in.AllowedAggregates = json.RawMessage(`[]`)
	}
	if in.Status == "" {
		in.Status = "active"
	}
	_, err := r.db.Exec(ctx, `INSERT INTO telemetry_field_catalog(field_key,field_type,base_unit,category,description,
		is_timeseries,is_aggregatable,allowed_aggregates,status,updated_at)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,NOW())
		ON CONFLICT(field_key) DO UPDATE SET field_type=EXCLUDED.field_type,base_unit=EXCLUDED.base_unit,
		category=EXCLUDED.category,description=EXCLUDED.description,is_timeseries=EXCLUDED.is_timeseries,
		is_aggregatable=EXCLUDED.is_aggregatable,allowed_aggregates=EXCLUDED.allowed_aggregates,
		status=EXCLUDED.status,updated_at=NOW()`, in.FieldKey, in.FieldType, in.BaseUnit, in.Category, in.Description,
		in.IsTimeseries, in.IsAggregatable, in.AllowedAggregates, in.Status)
	if err == nil {
		_, _ = r.db.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,detail)
		VALUES($1,'upsert','telemetry_field_catalog',jsonb_build_object('field_key',$2))`, operatorID, in.FieldKey)
	}
	return err
}

type FieldCapabilityPatch struct {
	FieldKey     string `json:"field_key"`
	IsSupported  *bool  `json:"is_supported"`
	IsVisible    *bool  `json:"is_visible"`
	ShowRealtime *bool  `json:"show_realtime"`
	ShowHistory  *bool  `json:"show_history"`
	AllowCompare *bool  `json:"allow_compare"`
	AllowAlarm   *bool  `json:"allow_alarm_rule"`
	DefaultChart *bool  `json:"default_chart"`
}

func (r *ModelRepository) BatchUpdateFieldCapabilities(ctx context.Context, modelID, operatorID int64, items []FieldCapabilityPatch) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for _, in := range items {
		_, err = tx.Exec(ctx, `INSERT INTO device_model_fields(model_id,field_key,group_code)
			SELECT $1,$2,c.category FROM telemetry_field_catalog c WHERE c.field_key=$2
			ON CONFLICT(model_id,field_key) DO UPDATE SET
			is_supported=COALESCE($3,device_model_fields.is_supported),is_visible=COALESCE($4,device_model_fields.is_visible),
			show_realtime=COALESCE($5,device_model_fields.show_realtime),show_history=COALESCE($6,device_model_fields.show_history),
			allow_compare=COALESCE($7,device_model_fields.allow_compare),allow_alarm_rule=COALESCE($8,device_model_fields.allow_alarm_rule),
			default_chart=COALESCE($9,device_model_fields.default_chart),updated_at=NOW()`, modelID, in.FieldKey, in.IsSupported,
			in.IsVisible, in.ShowRealtime, in.ShowHistory, in.AllowCompare, in.AllowAlarm, in.DefaultChart)
		if err != nil {
			return err
		}
	}
	_, err = tx.Exec(ctx, `UPDATE device_models SET lock_version=lock_version+1,updated_at=NOW() WHERE id=$1`, modelID)
	if err == nil {
		_, err = tx.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,resource_id,detail)
		VALUES($1,'batch_update','device_model_fields',$2,jsonb_build_object('count',$3))`, operatorID, modelID, len(items))
	}
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

type ModelCommandInput struct {
	CommandCode     string          `json:"command_code"`
	DisplayNameKey  string          `json:"display_name_key"`
	ParameterSchema json.RawMessage `json:"parameter_schema"`
	ResponseSchema  json.RawMessage `json:"response_schema"`
	TimeoutSeconds  int             `json:"timeout_seconds"`
	RiskLevel       int             `json:"risk_level"`
	RequiresOnline  bool            `json:"requires_online"`
	IsEnabled       bool            `json:"is_enabled"`
}

func (r *ModelRepository) UpsertModelCommand(ctx context.Context, modelID, operatorID int64, in ModelCommandInput) error {
	if len(in.ParameterSchema) == 0 {
		in.ParameterSchema = json.RawMessage(`{"args":[]}`)
	}
	if len(in.ResponseSchema) == 0 {
		in.ResponseSchema = json.RawMessage(`{}`)
	}
	if in.TimeoutSeconds == 0 {
		in.TimeoutSeconds = 30
	}
	if in.RiskLevel == 0 {
		in.RiskLevel = 1
	}
	_, err := r.db.Exec(ctx, `INSERT INTO device_model_commands(model_id,command_code,display_name_key,parameter_schema,response_schema,
		timeout_seconds,risk_level,requires_online,is_enabled,updated_at) VALUES($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7,$8,$9,NOW())
		ON CONFLICT(model_id,command_code) DO UPDATE SET display_name_key=EXCLUDED.display_name_key,
		parameter_schema=EXCLUDED.parameter_schema,response_schema=EXCLUDED.response_schema,timeout_seconds=EXCLUDED.timeout_seconds,
		risk_level=EXCLUDED.risk_level,requires_online=EXCLUDED.requires_online,is_enabled=EXCLUDED.is_enabled,updated_at=NOW()`,
		modelID, in.CommandCode, in.DisplayNameKey, in.ParameterSchema, in.ResponseSchema, in.TimeoutSeconds, in.RiskLevel, in.RequiresOnline, in.IsEnabled)
	if err == nil {
		_, _ = r.db.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,resource_id,detail)
		VALUES($1,'upsert','device_model_command',$2,jsonb_build_object('command_code',$3))`, operatorID, modelID, in.CommandCode)
	}
	return err
}

type ProtocolFieldInput struct {
	GroupCode  string   `json:"group_code"`
	FieldIndex int      `json:"field_index"`
	FieldKey   string   `json:"field_key"`
	WireType   string   `json:"wire_type"`
	Scale      float64  `json:"scale"`
	Minimum    *float64 `json:"minimum"`
	Maximum    *float64 `json:"maximum"`
	Nullable   bool     `json:"nullable"`
}
type ProtocolVersionInput struct {
	ProtocolCode string               `json:"protocol_code"`
	Version      int                  `json:"version"`
	SchemaHash   string               `json:"schema_hash"`
	Fields       []ProtocolFieldInput `json:"fields"`
}

func (r *ModelRepository) ListProtocolVersions(ctx context.Context) ([]map[string]any, error) {
	rows, err := r.db.Query(ctx, `SELECT jsonb_build_object('id',p.id,'protocol_code',p.protocol_code,'version',p.version,'schema_hash',p.schema_hash,
	'status',p.status,'released_at',p.released_at,'field_count',(SELECT COUNT(*) FROM device_protocol_fields f WHERE f.protocol_version_id=p.id))
	FROM device_protocol_versions p ORDER BY p.protocol_code,p.version DESC`)
	if err != nil {
		return nil, err
	}
	return scanJSONRows(rows)
}

func (r *ModelRepository) CreateProtocolVersion(ctx context.Context, operatorID int64, in ProtocolVersionInput) (int64, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)
	var id int64
	err = tx.QueryRow(ctx, `INSERT INTO device_protocol_versions(protocol_code,version,schema_hash,status) VALUES($1,$2,$3,'draft') RETURNING id`, in.ProtocolCode, in.Version, in.SchemaHash).Scan(&id)
	if err != nil {
		return 0, err
	}
	for _, f := range in.Fields {
		scale := f.Scale
		if scale == 0 {
			scale = 1
		}
		_, err = tx.Exec(ctx, `INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,scale,minimum,maximum,nullable)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, id, f.GroupCode, f.FieldIndex, f.FieldKey, f.WireType, scale, f.Minimum, f.Maximum, f.Nullable)
		if err != nil {
			return 0, err
		}
	}
	_, err = tx.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,resource_id,detail) VALUES($1,'create','protocol_version',$2,jsonb_build_object('field_count',$3))`, operatorID, id, len(in.Fields))
	if err != nil {
		return 0, err
	}
	return id, tx.Commit(ctx)
}

func (r *ModelRepository) ReleaseProtocolVersion(ctx context.Context, id, operatorID int64) error {
	tag, err := r.db.Exec(ctx, `UPDATE device_protocol_versions p SET status='released',released_at=NOW()
	WHERE p.id=$1 AND p.status='draft' AND EXISTS(SELECT 1 FROM device_protocol_fields f WHERE f.protocol_version_id=p.id)`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("draft protocol with fields not found")
	}
	_, _ = r.db.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,resource_id) VALUES($1,'release','protocol_version',$2)`, operatorID, id)
	return nil
}

func (r *ModelRepository) BindProtocolVersion(ctx context.Context, modelID, protocolID, operatorID int64) error {
	tag, err := r.db.Exec(ctx, `UPDATE device_models m SET heartbeat_protocol_id=p.id,lock_version=lock_version+1,updated_at=NOW()
	FROM device_protocol_versions p WHERE m.id=$1 AND p.id=$2 AND p.status='released'`, modelID, protocolID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("released protocol not found")
	}
	_, _ = r.db.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,resource_id,detail) VALUES($1,'bind_protocol','device_model',$2,jsonb_build_object('protocol_id',$3))`, operatorID, modelID, protocolID)
	return nil
}

func (r *ModelRepository) GetMigrationReport(ctx context.Context, modelID int64) (map[string]any, error) {
	var raw []byte
	err := r.db.QueryRow(ctx, `SELECT to_jsonb(r) FROM model_registry_migration_report r WHERE model_id=$1`, modelID).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return map[string]any{
			"model_id":         modelID,
			"migration_status": "pending",
			"details":          map[string]any{"note": "No legacy metadata was found for this model."},
		}, nil
	}
	if err != nil {
		return nil, err
	}
	var out map[string]any
	err = json.Unmarshal(raw, &out)
	return out, err
}

func (r *ModelRepository) ValidateModelRegistry(ctx context.Context, modelID int64) ([]string, error) {
	var protocolStatus *string
	var fieldCount, commandCount int
	err := r.db.QueryRow(ctx, `SELECT p.status,(SELECT COUNT(*) FROM device_model_fields f WHERE f.model_id=m.id AND f.is_supported),
	(SELECT COUNT(*) FROM device_model_commands c WHERE c.model_id=m.id AND c.is_enabled) FROM device_models m LEFT JOIN device_protocol_versions p ON p.id=m.heartbeat_protocol_id WHERE m.id=$1`, modelID).Scan(&protocolStatus, &fieldCount, &commandCount)
	if err != nil {
		return nil, err
	}
	issues := []string{}
	if protocolStatus == nil || *protocolStatus != "released" {
		issues = append(issues, "heartbeat protocol must be released")
	}
	if fieldCount == 0 {
		issues = append(issues, "at least one supported field is required")
	}
	if commandCount == 0 {
		issues = append(issues, "at least one enabled command is required")
	}
	return issues, nil
}

func (r *ModelRepository) ActivateModel(ctx context.Context, modelID, operatorID int64) error {
	issues, err := r.ValidateModelRegistry(ctx, modelID)
	if err != nil {
		return err
	}
	if len(issues) > 0 {
		return fmt.Errorf("model validation failed: %v", issues)
	}
	_, err = r.db.Exec(ctx, `UPDATE device_models SET lifecycle_status='active',is_active=true,lock_version=lock_version+1,updated_at=NOW() WHERE id=$1`, modelID)
	if err == nil {
		_, _ = r.db.Exec(ctx, `INSERT INTO audit_logs(operator_id,action,resource_type,resource_id) VALUES($1,'activate','device_model',$2)`, operatorID, modelID)
	}
	return err
}

func (r *ModelRepository) GetModelDataPreview(ctx context.Context, modelID int64) (map[string]any, error) {
	var raw []byte
	err := r.db.QueryRow(ctx, `SELECT to_jsonb(l) FROM devices d JOIN device_latest_state l ON l.device_sn=d.sn WHERE d.model_id=$1 AND d.deleted_at IS NULL ORDER BY l.event_time DESC LIMIT 1`, modelID).Scan(&raw)
	if err == pgx.ErrNoRows {
		return map[string]any{}, nil
	}
	if err != nil {
		return nil, err
	}
	var out map[string]any
	err = json.Unmarshal(raw, &out)
	return out, err
}
