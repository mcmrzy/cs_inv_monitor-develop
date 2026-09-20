package service

import (
	"testing"

	"inv-device-server/internal/model"
	telemetryv2 "inv-device-server/internal/telemetry"

	"github.com/stretchr/testify/require"
)

func floatPtr(v float64) *float64 { return &v }

// l10Specs 模拟 CS-L10-6K2 迁移 124 后的诊断规格：10 个字段型号固件未实现。
// 现场实证：mppt_fan_speed/inv_fan_speed 恒填 0；inv_current/pv_temperature/transformer_temperature/
// paired_socket/online_socket/on_socket 从未赋值（随机堆内存）；parallel_charge_current/work_time_total 恒填 0。
func l10Specs() model.DiagnosticSpecs {
	specs := model.DefaultDiagnosticSpecs()
	specs.UnsupportedFields = []string{
		model.FieldKeyMpptFanSpeed, model.FieldKeyInvFanSpeed,
		model.FieldKeyParallelChargeCurrent, model.FieldKeyWorkTimeTotal,
		model.FieldKeyInvCurrent, model.FieldKeyPVTemperature,
		model.FieldKeyTransformerTemperature,
		model.FieldKeyPairedSocket, model.FieldKeyOnlineSocket, model.FieldKeyOnSocket,
	}
	return specs
}

// l10FanSample 现场实景：温度正常（43/50°C 带载）、风扇上报 0（未实现）、SOC 正常。
func l10FanSample() *telemetryv2.Sample {
	s := healthySample()
	*s.Fan.InvSpeed = 0  // ARM 恒填 0（未实现）
	*s.Fan.MPPTSpeed = 0 // ARM 恒填 0（未实现）
	return s
}

func testHealthSpecs() model.DiagnosticSpecs {
	return model.DefaultDiagnosticSpecs()
}

// 构造一个"健康"样本：温度正常、风扇正常、SOC 充足、无并机。
func healthySample() *telemetryv2.Sample {
	invT, boostT := 45.0, 50.0
	invFan, mpptFan := 80.0, 85.0
	soc := 60.0
	return &telemetryv2.Sample{
		System: telemetryv2.System{
			InverterTemperature: &invT,
			BoostTemperature:    &boostT,
		},
		Fan: telemetryv2.Fan{
			InvSpeed:  &invFan,
			MPPTSpeed: &mpptFan,
		},
		Battery: telemetryv2.Battery{SOC: &soc},
	}
}

func TestComputeHealthHealthy(t *testing.T) {
	h := ComputeHealth(healthySample(), nil, testHealthSpecs())
	require.Equal(t, 100.0, h.Score)
	require.Equal(t, model.HealthLevelHealthy, h.Level)
	require.Empty(t, h.Factors)
}

func TestComputeHealthDeductFault(t *testing.T) {
	active := []model.DiagnosticEvent{{RuleCode: model.RuleThermalOverheat, Level: "fault"}}
	h := ComputeHealth(healthySample(), active, testHealthSpecs())
	require.Equal(t, 70.0, h.Score)
	require.Equal(t, model.HealthLevelGood, h.Level)
	require.InDelta(t, testHealthSpecs().DeductFault, h.Factors["active_fault"], 0.0001)
}

func TestComputeHealthDeductWarning(t *testing.T) {
	active := []model.DiagnosticEvent{{RuleCode: model.RuleConfigDrift, Level: "warning"}}
	h := ComputeHealth(healthySample(), active, testHealthSpecs())
	require.Equal(t, 90.0, h.Score)
	require.Equal(t, model.HealthLevelHealthy, h.Level)
}

func TestComputeHealthDeductTempHigh(t *testing.T) {
	s := healthySample()
	*s.System.InverterTemperature = 80 // > 75
	h := ComputeHealth(s, nil, testHealthSpecs())
	require.Equal(t, 85.0, h.Score)
	require.Equal(t, model.HealthLevelGood, h.Level)
	require.InDelta(t, testHealthSpecs().DeductTempHigh, h.Factors["temp_high"], 0.0001)
}

func TestComputeHealthDeductFanAbnormal(t *testing.T) {
	s := healthySample()
	*s.Fan.InvSpeed = 20 // < 30
	h := ComputeHealth(s, nil, testHealthSpecs())
	require.Equal(t, 85.0, h.Score)
	require.InDelta(t, testHealthSpecs().DeductFanAbnormal, h.Factors["fan_abnormal"], 0.0001)
}

func TestComputeHealthDeductLowSOC(t *testing.T) {
	s := healthySample()
	*s.Battery.SOC = 15 // < 20
	h := ComputeHealth(s, nil, testHealthSpecs())
	require.Equal(t, 90.0, h.Score)
	require.InDelta(t, testHealthSpecs().DeductLowSOC, h.Factors["low_soc"], 0.0001)
}

func TestComputeHealthDeductParallelOffline(t *testing.T) {
	active := []model.DiagnosticEvent{{RuleCode: model.RuleParallelSlaveOffline, Level: "warning"}}
	h := ComputeHealth(healthySample(), active, testHealthSpecs())
	require.Equal(t, 85.0, h.Score) // warning -10 + parallel -5
}

func TestComputeHealthFloorAtZero(t *testing.T) {
	s := healthySample()
	*s.System.InverterTemperature = 90
	*s.Fan.InvSpeed = 10
	*s.Battery.SOC = 10
	active := []model.DiagnosticEvent{
		{RuleCode: model.RuleThermalOverheat, Level: "fault"},
		{RuleCode: model.RuleInvFanAbnormal, Level: "fault"},
		{RuleCode: model.RuleParallelSlaveOffline, Level: "warning"},
	}
	h := ComputeHealth(s, active, testHealthSpecs())
	require.Equal(t, 15.0, h.Score) // 100-30(fault)-10(warning)-5(parallel)-15(temp)-15(fan)-10(soc)
	require.Equal(t, model.HealthLevelMaintenance, h.Level)
}

func TestComputeHealthAttentionLevel(t *testing.T) {
	active := []model.DiagnosticEvent{{RuleCode: model.RuleThermalOverheat, Level: "fault"}}
	s := healthySample()
	*s.System.InverterTemperature = 80 // 再加 -15
	h := ComputeHealth(s, active, testHealthSpecs())
	require.Equal(t, 55.0, h.Score) // 100-30-15
	require.Equal(t, model.HealthLevelAttention, h.Level)
}

// ② 声明两个 fan 字段均未实现（L10）：风扇 0% 不扣分，factors 无 fan_abnormal。
func TestComputeHealthFanUnsupportedNoDeduct(t *testing.T) {
	specs := l10Specs()
	h := ComputeHealth(l10FanSample(), nil, specs)
	require.Equal(t, 100.0, h.Score)
	require.Equal(t, model.HealthLevelHealthy, h.Level)
	require.NotContains(t, h.Factors, "fan_abnormal")
	require.Empty(t, h.Factors)
}

// ③ 部分支持：仅声明 mppt_fan_speed 未实现时，mppt 归零不扣分，inv 字段仍生效。
func TestComputeHealthFanPartiallyUnsupported(t *testing.T) {
	specs := model.DefaultDiagnosticSpecs()
	specs.UnsupportedFields = []string{model.FieldKeyMpptFanSpeed}

	s := l10FanSample() // mppt=0（不参与判定）, inv=0（参与判定）
	h := ComputeHealth(s, nil, specs)
	require.Equal(t, 85.0, h.Score) // inv 风扇 0% < 30% → -15
	require.InDelta(t, specs.DeductFanAbnormal, h.Factors["fan_abnormal"], 0.0001)

	// inv 恢复正常（80%）后，仅剩未实现的 mppt 为 0 → 不扣分
	*s.Fan.InvSpeed = 80
	h = ComputeHealth(s, nil, specs)
	require.Equal(t, 100.0, h.Score)
	require.NotContains(t, h.Factors, "fan_abnormal")
}

// 反向支持：只声明 inv_fan_speed 未实现时，mppt 字段仍参与判定。
func TestComputeHealthFanPartialUnsupportedMpptStillJudged(t *testing.T) {
	specs := model.DefaultDiagnosticSpecs()
	specs.UnsupportedFields = []string{model.FieldKeyInvFanSpeed}

	s := healthySample()
	*s.Fan.MPPTSpeed = 10 // < 30，且未被声明为未实现
	h := ComputeHealth(s, nil, specs)
	require.Equal(t, 85.0, h.Score)
	require.InDelta(t, specs.DeductFanAbnormal, h.Factors["fan_abnormal"], 0.0001)
}

// 未声明 any 未实现字段时（现有型号）：风扇 0% 仍扣分（与 TestComputeHealthDeductFanAbnormal 同语义，
// 此处覆盖"两个字段同时为 0"的 L10 原始缺陷场景，确认向后兼容行为不变）。
func TestComputeHealthFanAbnormalBackwardCompatibleBothZero(t *testing.T) {
	specs := model.DefaultDiagnosticSpecs()
	require.Empty(t, specs.UnsupportedFields)

	h := ComputeHealth(l10FanSample(), nil, specs)
	require.Equal(t, 85.0, h.Score) // 未声明未支持 → 仍按原逻辑 -15
	require.InDelta(t, specs.DeductFanAbnormal, h.Factors["fan_abnormal"], 0.0001)
}
