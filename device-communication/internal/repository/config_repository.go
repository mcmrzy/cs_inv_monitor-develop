package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"reflect"
	"sort"

	"inv-device-server/internal/model"
	"inv-device-server/internal/telemetry"
)

// LoadConfigSchema 加载 device_config_schema 全部参数定义（config v2 校验与 SchemaGroupPanel 渲染共用）。
func (r *DeviceRepository) LoadConfigSchema(ctx context.Context) (map[string]model.ConfigParamSchema, error) {
	rows, err := r.db.Query(ctx, `
		SELECT param_key, group_code, COALESCE(sub_group,''), control_type,
			scale, COALESCE(unit,''), min, max, enum_map, step,
			permission_code, COALESCE(confirmation_mode,''), display_name_key,
			sort_order, visibility, validation
		FROM device_config_schema ORDER BY sort_order`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	schemas := make(map[string]model.ConfigParamSchema, 42)
	for rows.Next() {
		var s model.ConfigParamSchema
		var min, max, step *float64
		var enumMap, visibility, validation []byte
		if err := rows.Scan(&s.ParamKey, &s.GroupCode, &s.SubGroup, &s.ControlType,
			&s.Scale, &s.Unit, &min, &max, &enumMap, &step,
			&s.PermissionCode, &s.ConfirmationMode, &s.DisplayNameKey,
			&s.SortOrder, &visibility, &validation); err != nil {
			return nil, err
		}
		s.Min, s.Max, s.Step = min, max, step
		_ = json.Unmarshal(enumMap, &s.EnumMap)
		_ = json.Unmarshal(visibility, &s.Visibility)
		_ = json.Unmarshal(validation, &s.Validation)
		schemas[s.ParamKey] = s
	}
	return schemas, rows.Err()
}

// ValidateConfigV2Params 按 schema 校验 config v2 params（范围/枚举/互斥，见 V2.1 文档 9.2 互斥约束）：
// 返回有效值与无效键清单；无效键不阻断整包（调用方剔除并记日志）。
func ValidateConfigV2Params(values map[string]any, schemas map[string]model.ConfigParamSchema) (map[string]any, []string) {
	valid := make(map[string]any, len(values))
	var invalid []string

	// 第一轮：单键校验（范围/枚举/布尔）
	for key, v := range values {
		schema, ok := schemas[key]
		if !ok {
			invalid = append(invalid, key) // 未注册参数键：忽略
			continue
		}
		num, ok := toFloat(v)
		if !ok {
			invalid = append(invalid, key)
			continue
		}
		if schema.Min != nil && num < *schema.Min {
			invalid = append(invalid, key)
			continue
		}
		if schema.Max != nil && num > *schema.Max {
			invalid = append(invalid, key)
			continue
		}
		if len(schema.EnumMap) > 0 {
			if _, ok := schema.EnumMap[fmt.Sprintf("%v", num)]; !ok {
				invalid = append(invalid, key)
				continue
			}
		}
		valid[key] = num
	}

	// 第二轮：跨键互斥校验（validation lte/gte），如 set_soc_cutoff ≤ set_soc_back_utl。
	// 先收集违反约束的键再统一删除：避免迭代中先删参照键导致另一方"参照缺失"而漏检。
	var toRemove []string
	for key, v := range valid {
		schema := schemas[key]
		check := func(op string) bool {
			ref, ok := schema.Validation[op]
			if !ok {
				return true
			}
			refKey, ok := ref.(string)
			if !ok {
				return true
			}
			refVal, ok := valid[refKey]
			if !ok {
				return true // 参照参数未上报，无法校验
			}
			refNum, ok := toFloat(refVal)
			if !ok {
				return true
			}
			curNum, _ := toFloat(v)
			if op == model.ValidationLTE {
				return curNum <= refNum
			}
			return curNum >= refNum
		}
		if !check(model.ValidationLTE) || !check(model.ValidationGTE) {
			toRemove = append(toRemove, key)
		}
	}
	for _, key := range toRemove {
		delete(valid, key)
		invalid = append(invalid, key)
	}
	sort.Strings(invalid)
	return valid, invalid
}

// SaveReportedConfigV2 处理 config v2 上报（见 V2.1 文档 9.3）：
//   - schema 校验（无效键剔除，不阻断整包）
//   - rev 防回退：新 rev < 旧 reported_revision 时拒绝更新
//   - 写入 device_control_state.reported + reported_revision，与 desired 比对更新 sync_status
//   - 审计：相对上次上报发生变化的参数写 device_config_changes（source=reported）
//
// 返回 sync_status 与无效键清单（供调用方日志/诊断）。
func (r *DeviceRepository) SaveReportedConfigV2(ctx context.Context, sn string, cfg *telemetry.ReportedConfig, schemas map[string]model.ConfigParamSchema) (string, []string, error) {
	validValues, invalidKeys := ValidateConfigV2Params(cfg.Values, schemas)

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return "", invalidKeys, err
	}
	defer tx.Rollback(ctx)

	var oldReported []byte
	var oldRev uint64
	_ = tx.QueryRow(ctx, `SELECT reported, reported_revision FROM device_control_state WHERE device_sn=$1 FOR UPDATE`, sn).Scan(&oldReported, &oldRev)
	if cfg.Revision < oldRev {
		return "", invalidKeys, nil // rev 回退：拒绝更新（防回退）
	}
	reported, err := json.Marshal(validValues)
	if err != nil {
		return "", invalidKeys, err
	}

	syncStatus := "unknown"
	if err := tx.QueryRow(ctx, `
		INSERT INTO device_control_state(device_sn,protocol_version,reported,reported_revision,sync_status,reported_at,updated_at)
		VALUES($1,2,$2::jsonb,$3,'unknown',$4,NOW())
		ON CONFLICT(device_sn) DO UPDATE SET
			protocol_version=2,
			reported=EXCLUDED.reported,
			reported_revision=EXCLUDED.reported_revision,
			reported_at=EXCLUDED.reported_at,
			sync_status=CASE
				WHEN device_control_state.desired='{}'::jsonb THEN 'unknown'
				WHEN device_control_state.desired=EXCLUDED.reported THEN 'synced'
				ELSE 'drifted' END,
			updated_at=NOW()
		RETURNING sync_status`, sn, reported, cfg.Revision, cfg.EventTime).Scan(&syncStatus); err != nil {
		return "", invalidKeys, fmt.Errorf("save reported config v2: %w", err)
	}

	// 审计：相对上次上报变化的参数（source=reported）
	if len(oldReported) > 0 {
		var oldValues map[string]any
		if json.Unmarshal(oldReported, &oldValues) == nil {
			for _, key := range changedParamKeys(oldValues, validValues) {
				oldV, newV := jsonOrNull(oldValues[key]), jsonOrNull(validValues[key])
				if _, err := tx.Exec(ctx, `
					INSERT INTO device_config_changes(device_sn,param_key,old_value,new_value,source,rev)
					VALUES($1,$2,$3::jsonb,$4::jsonb,'reported',$5)`,
					sn, key, oldV, newV, cfg.Revision); err != nil {
					return "", invalidKeys, err
				}
			}
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return "", invalidKeys, err
	}
	return syncStatus, invalidKeys, nil
}

// GetControlState 读取设备 desired/reported 配置与同步状态（诊断引擎 CONFIG_DRIFT 用）。
func (r *DeviceRepository) GetControlState(ctx context.Context, sn string) (desired, reported map[string]any, syncStatus string, err error) {
	var desiredRaw, reportedRaw []byte
	err = r.db.QueryRow(ctx, `
		SELECT desired, reported, COALESCE(sync_status,'unknown')
		FROM device_control_state WHERE device_sn=$1`, sn).Scan(&desiredRaw, &reportedRaw, &syncStatus)
	if err != nil {
		return nil, nil, "", err
	}
	desired, reported = map[string]any{}, map[string]any{}
	_ = json.Unmarshal(desiredRaw, &desired)
	_ = json.Unmarshal(reportedRaw, &reported)
	return desired, reported, syncStatus, nil
}

// changedParamKeys 返回两个 map 之间值发生变化的键（新增/删除/数值不同）。
func changedParamKeys(oldV, newV map[string]any) []string {
	keys := make(map[string]bool)
	for k := range oldV {
		keys[k] = true
	}
	for k := range newV {
		keys[k] = true
	}
	var changed []string
	for k := range keys {
		if !reflect.DeepEqual(oldV[k], newV[k]) {
			changed = append(changed, k)
		}
	}
	sort.Strings(changed)
	return changed
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case float32:
		return float64(n), true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	case json.Number:
		f, err := n.Float64()
		return f, err == nil
	}
	return 0, false
}

func jsonOrNull(v any) []byte {
	if v == nil {
		return []byte("null")
	}
	b, _ := json.Marshal(v)
	return b
}
