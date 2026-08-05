package repository

import (
	"testing"

	"inv-device-server/internal/model"

	"github.com/stretchr/testify/require"
)

// schema 样例：set_battery_type 枚举、set_max_charge_current 范围、set_soc_cutoff/set_soc_back_utl 互斥。
func testConfigSchemas() map[string]model.ConfigParamSchema {
	min0, max2 := 0.0, 2.0
	min5, max100 := 5.0, 100.0
	min10, max90 := 10.0, 90.0
	min20, max100 := 20.0, 100.0
	return map[string]model.ConfigParamSchema{
		"set_battery_type": {
			ParamKey: "set_battery_type", ControlType: "enum", Min: &min0, Max: &max2,
			EnumMap: map[string]any{"0": true, "1": true, "2": true},
		},
		"set_max_charge_current": {
			ParamKey: "set_max_charge_current", ControlType: "number", Min: &min5, Max: &max100,
		},
		"set_soc_cutoff": {
			ParamKey: "set_soc_cutoff", ControlType: "number", Min: &min10, Max: &max90,
			Validation: map[string]any{model.ValidationLTE: "set_soc_back_utl"},
		},
		"set_soc_back_utl": {
			ParamKey: "set_soc_back_utl", ControlType: "number", Min: &min20, Max: &max100,
			Validation: map[string]any{model.ValidationGTE: "set_soc_cutoff"},
		},
	}
}

func TestValidateConfigV2ParamsValid(t *testing.T) {
	values := map[string]any{
		"set_battery_type":        float64(1),
		"set_max_charge_current":  float64(50),
		"set_soc_cutoff":          float64(20),
		"set_soc_back_utl":        float64(40),
	}
	valid, invalid := ValidateConfigV2Params(values, testConfigSchemas())
	require.Empty(t, invalid)
	require.Len(t, valid, 4)
}

func TestValidateConfigV2ParamsRejectsOutOfRange(t *testing.T) {
	values := map[string]any{
		"set_max_charge_current": float64(500), // 超出 max=100
		"set_battery_type":       float64(3),   // 超出枚举
	}
	valid, invalid := ValidateConfigV2Params(values, testConfigSchemas())
	require.Len(t, valid, 0)
	require.ElementsMatch(t, []string{"set_battery_type", "set_max_charge_current"}, invalid)
}

func TestValidateConfigV2ParamsRejectsEnumMismatch(t *testing.T) {
	values := map[string]any{"set_battery_type": float64(9)}
	valid, invalid := ValidateConfigV2Params(values, testConfigSchemas())
	require.Len(t, valid, 0)
	require.ElementsMatch(t, []string{"set_battery_type"}, invalid)
}

func TestValidateConfigV2ParamsRejectsCrossKeyMutualExclusion(t *testing.T) {
	// set_soc_cutoff(60) > set_soc_back_utl(40)：违反 lte 约束，两侧键都应剔除
	values := map[string]any{
		"set_soc_cutoff":   float64(60),
		"set_soc_back_utl": float64(40),
	}
	valid, invalid := ValidateConfigV2Params(values, testConfigSchemas())
	require.Len(t, valid, 0)
	require.ElementsMatch(t, []string{"set_soc_back_utl", "set_soc_cutoff"}, invalid)
}

func TestValidateConfigV2ParamsSkipsUnknownKey(t *testing.T) {
	values := map[string]any{
		"set_battery_type": float64(1),
		"unknown_param":    float64(1),
	}
	valid, invalid := ValidateConfigV2Params(values, testConfigSchemas())
	require.Len(t, valid, 1)
	require.ElementsMatch(t, []string{"unknown_param"}, invalid)
}

func TestValidateConfigV2ParamsSkipsMissingReference(t *testing.T) {
	// 参照参数未上报时不阻断：set_soc_cutoff 单独上报合法
	values := map[string]any{"set_soc_cutoff": float64(30)}
	valid, invalid := ValidateConfigV2Params(values, testConfigSchemas())
	require.Len(t, valid, 1)
	require.Empty(t, invalid)
}
