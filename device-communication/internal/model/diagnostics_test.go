package model

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

// 迁移 124 写入 device_models.specifications.diagnostics 的实际 JSON（键名契约）：
// repository.GetModelDiagnosticSpecs 以 DefaultDiagnosticSpecs 为底反序列化该段。
const l10DiagnosticsJSON = `{
  "fan_speed_low_percent": 30,
  "fan_abnormal_temp_c": 70,
  "overheat_temp_c": 85,
  "health_temp_high_c": 75,
  "maintenance_hours": 5000,
  "deduct_fault": 30,
  "deduct_warning": 10,
  "deduct_temp_high": 15,
  "deduct_fan_abnormal": 15,
  "deduct_low_soc": 10,
  "deduct_parallel_offline": 5,
  "unsupported_fields": ["mppt_fan_speed", "inv_fan_speed", "parallel_charge_current", "work_time_total",
                         "inv_current", "pv_temperature", "transformer_temperature",
                         "paired_socket", "online_socket", "on_socket"]
}`

func TestDiagnosticSpecsUnsupportedFieldsJSON(t *testing.T) {
	specs := DefaultDiagnosticSpecs()
	require.NoError(t, json.Unmarshal([]byte(l10DiagnosticsJSON), &specs))

	require.Len(t, specs.UnsupportedFields, 10)
	for _, key := range []string{
		FieldKeyMpptFanSpeed, FieldKeyInvFanSpeed, FieldKeyParallelChargeCurrent, FieldKeyWorkTimeTotal,
		FieldKeyInvCurrent, FieldKeyPVTemperature, FieldKeyTransformerTemperature,
		FieldKeyPairedSocket, FieldKeyOnlineSocket, FieldKeyOnSocket,
	} {
		require.True(t, specs.IsUnsupported(key), "key %q should be unsupported", key)
	}
	// 未列入的字段不受影响（阈值判据继续生效）
	require.False(t, specs.IsUnsupported("inverter_temperature"))
	require.False(t, specs.IsUnsupported(""))
	// 阈值随 JSON 正常覆盖
	require.Equal(t, 30.0, specs.FanSpeedLowPercent)
	require.Equal(t, 5000.0, specs.MaintenanceHours)
}

// 未配置 unsupported_fields（其它型号 / 迁移 124 之前）→ 空列表，IsUnsupported 恒 false，行为不变。
func TestDiagnosticSpecsUnsupportedFieldsAbsent(t *testing.T) {
	specs := DefaultDiagnosticSpecs()
	require.NoError(t, json.Unmarshal([]byte(`{"fan_speed_low_percent":30}`), &specs))

	require.Empty(t, specs.UnsupportedFields)
	require.False(t, specs.IsUnsupported(FieldKeyMpptFanSpeed))
	require.False(t, specs.IsUnsupported(FieldKeyInvFanSpeed))
	require.Equal(t, 30.0, specs.FanSpeedLowPercent)
}

// 默认规格不含未实现字段声明（向后兼容基线）。
func TestDefaultDiagnosticSpecsNoUnsupportedFields(t *testing.T) {
	require.Empty(t, DefaultDiagnosticSpecs().UnsupportedFields)
}

// 非法 JSON 片段（diagnostics 缺失/为 null）不得影响默认值。
func TestDiagnosticSpecsNullUnsupportedFields(t *testing.T) {
	specs := DefaultDiagnosticSpecs()
	require.NoError(t, json.Unmarshal([]byte(`{"unsupported_fields":null}`), &specs))
	require.Empty(t, specs.UnsupportedFields)
	require.False(t, specs.IsUnsupported(FieldKeyPairedSocket))
}
