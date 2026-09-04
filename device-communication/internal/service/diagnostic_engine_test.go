package service

import (
	"context"
	"testing"

	"inv-device-server/internal/model"
	telemetryv2 "inv-device-server/internal/telemetry"

	"github.com/stretchr/testify/require"
)

// evaluateRules 散热/并机规则不依赖 DB（NewDiagnosticEngine(nil,nil) 可测）。
// 注意：不设置 Diag.WorkTimeTotal，避免触发 MAINTENANCE_DUE 的 repo 调用。
func testEngine() *DiagnosticEngine { return NewDiagnosticEngine(nil, nil) }

func TestEvaluateRulesInvFanAbnormal(t *testing.T) {
	invT := 80.0
	invFan := 20.0 // < 30%
	s := &telemetryv2.Sample{
		System: telemetryv2.System{InverterTemperature: &invT},
		Fan:    telemetryv2.Fan{InvSpeed: &invFan},
	}
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	e := events[0]
	require.Equal(t, model.RuleInvFanAbnormal, e.RuleCode)
	require.Equal(t, "fault", e.Level)
	require.Equal(t, "active", e.Status)
	require.InDelta(t, 20.0, e.Detail["inv_fan_speed"], 0.0001)
	require.InDelta(t, 80.0, e.Detail["inverter_temperature"], 0.0001)
}

func TestEvaluateRulesMpptFanAbnormal(t *testing.T) {
	boostT := 75.0
	mpptFan := 15.0 // < 30%
	s := &telemetryv2.Sample{
		System: telemetryv2.System{BoostTemperature: &boostT},
		Fan:    telemetryv2.Fan{MPPTSpeed: &mpptFan},
	}
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	require.Equal(t, model.RuleMpptFanAbnormal, events[0].RuleCode)
}

func TestEvaluateRulesThermalOverheat(t *testing.T) {
	invT := 90.0 // > 85
	s := &telemetryv2.Sample{System: telemetryv2.System{InverterTemperature: &invT}}
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	require.Equal(t, model.RuleThermalOverheat, events[0].RuleCode)
	require.Equal(t, "fault", events[0].Level)
}

func TestEvaluateRulesParallelSlaveOffline(t *testing.T) {
	paired, online, on := uint32(3), uint32(1), uint32(1) // 3 台配对、1 台在线（在线的均在运行）→ 2 台离线
	s := &telemetryv2.Sample{Sock: telemetryv2.Sock{PairedSocket: &paired, OnlineSocket: &online, OnSocket: &on}}
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	e := events[0]
	require.Equal(t, model.RuleParallelSlaveOffline, e.RuleCode)
	require.Equal(t, "warning", e.Level)
	require.Equal(t, uint32(2), e.Detail["offline_mask"]) // 3&^1
}

func TestEvaluateRulesParallelNotRunning(t *testing.T) {
	paired, online, on := uint32(2), uint32(2), uint32(1) // 2 台在线、1 台运行
	s := &telemetryv2.Sample{Sock: telemetryv2.Sock{PairedSocket: &paired, OnlineSocket: &online, OnSocket: &on}}
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	e := events[0]
	require.Equal(t, model.RuleParallelNotRunning, e.RuleCode)
	require.Equal(t, "info", e.Level)
	require.Equal(t, uint32(2), e.Detail["not_running_mask"]) // 2&^1
}

func TestEvaluateRulesNoTrigger(t *testing.T) {
	events := testEngine().evaluateRules(context.Background(), "sn", healthySample(), testHealthSpecs())
	require.Empty(t, events)
}

func TestEvaluateRulesFanSpeedNilNoFault(t *testing.T) {
	// 风扇数据缺失（旧固件）：即使温度过高也只触发过温，不触发风扇异常
	invT := 90.0 // > 85 过温阈值
	s := &telemetryv2.Sample{System: telemetryv2.System{InverterTemperature: &invT}}
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	require.Equal(t, model.RuleThermalOverheat, events[0].RuleCode)
}
