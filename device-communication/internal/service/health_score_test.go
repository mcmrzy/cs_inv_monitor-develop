package service

import (
	"testing"

	"inv-device-server/internal/model"
	telemetryv2 "inv-device-server/internal/telemetry"

	"github.com/stretchr/testify/require"
)

func floatPtr(v float64) *float64 { return &v }

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
