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

// ==================== 型号字段能力门控（迁移 124，CS-L10-6K2） ====================

// deriveThermalStatus：声明 fan 未实现 → 43°C 正常带载（风扇恒 0）返回 normal。
func TestDeriveThermalStatusFanUnsupportedNormalOnLoad(t *testing.T) {
	invT, boostT := 43.0, 50.0 // 现场实证：正常带载温度
	invFan, mpptFan := 0.0, 0.0
	s := &telemetryv2.Sample{
		System: telemetryv2.System{InverterTemperature: &invT, BoostTemperature: &boostT},
		Fan:    telemetryv2.Fan{InvSpeed: &invFan, MPPTSpeed: &mpptFan},
	}
	require.Equal(t, "normal", deriveThermalStatus(s, l10Specs()))
	// 对照：未声明未支持（其它型号/旧行为）→ 风扇 0% 使状态恒 warning
	require.Equal(t, "warning", deriveThermalStatus(s, testHealthSpecs()))
}

// deriveThermalStatus：门控只作用于风扇判据，温度超限仍返回 warning / fault。
func TestDeriveThermalStatusFanUnsupportedTempStillJudged(t *testing.T) {
	invFan, mpptFan := 0.0, 0.0
	specs := l10Specs()

	// 72°C > fan_abnormal_temp_c(70) 且 < overheat_temp_c(85) → warning（highTemp 保留）
	invT, boostT := 72.0, 50.0
	s := &telemetryv2.Sample{
		System: telemetryv2.System{InverterTemperature: &invT, BoostTemperature: &boostT},
		Fan:    telemetryv2.Fan{InvSpeed: &invFan, MPPTSpeed: &mpptFan},
	}
	require.Equal(t, "warning", deriveThermalStatus(s, specs))

	// 90°C > overheat_temp_c(85) → fault（overheat 保留）
	invT = 90.0
	require.Equal(t, "fault", deriveThermalStatus(s, specs))

	// boost 侧同样生效（boostT=75 走 highTemp）
	invT, boostT = 43.0, 75.0
	require.Equal(t, "warning", deriveThermalStatus(s, specs))
}

// evaluateRules：fan 未实现时不产生 INV_FAN_ABNORMAL / MPPT_FAN_ABNORMAL（即使温度组合命中）。
func TestEvaluateRulesFanUnsupportedNoFanEvents(t *testing.T) {
	invT, boostT := 80.0, 80.0 // > fan_abnormal_temp_c(70)，< overheat_temp_c(85)
	invFan, mpptFan := 0.0, 0.0
	s := &telemetryv2.Sample{
		System: telemetryv2.System{InverterTemperature: &invT, BoostTemperature: &boostT},
		Fan:    telemetryv2.Fan{InvSpeed: &invFan, MPPTSpeed: &mpptFan},
	}
	require.Empty(t, testEngine().evaluateRules(context.Background(), "sn", s, l10Specs()))

	// 对照：未声明未支持时，两侧风扇异常均触发（fault）
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 2)
}

// evaluateRules：门控不吞掉过温事件（温度判据与风扇无关）。
func TestEvaluateRulesFanUnsupportedOverheatStillFaults(t *testing.T) {
	invT := 90.0 // > 85
	invFan, mpptFan := 0.0, 0.0
	s := &telemetryv2.Sample{
		System: telemetryv2.System{InverterTemperature: &invT},
		Fan:    telemetryv2.Fan{InvSpeed: &invFan, MPPTSpeed: &mpptFan},
	}
	events := testEngine().evaluateRules(context.Background(), "sn", s, l10Specs())
	require.Len(t, events, 1)
	require.Equal(t, model.RuleThermalOverheat, events[0].RuleCode)
	require.Equal(t, "fault", events[0].Level)
}

// evaluateRules：部分支持（只声明 mppt 未实现）时 inv 风扇判据仍生效。
func TestEvaluateRulesFanPartiallyUnsupported(t *testing.T) {
	specs := model.DefaultDiagnosticSpecs()
	specs.UnsupportedFields = []string{model.FieldKeyMpptFanSpeed}

	invT, boostT := 80.0, 80.0
	invFan, mpptFan := 0.0, 0.0
	s := &telemetryv2.Sample{
		System: telemetryv2.System{InverterTemperature: &invT, BoostTemperature: &boostT},
		Fan:    telemetryv2.Fan{InvSpeed: &invFan, MPPTSpeed: &mpptFan},
	}
	events := testEngine().evaluateRules(context.Background(), "sn", s, specs)
	require.Len(t, events, 1)
	require.Equal(t, model.RuleInvFanAbnormal, events[0].RuleCode)
}

// evaluateRules：work_time_total 未实现时不判定 MAINTENANCE_DUE。
// 关键证据：恒填 0 时该判据本就不会触发（cur=0 < 阈值），但门控同时保证即使上游灌入
// 任意值也不会走 repo 查询——testEngine() 的 repo 为 nil，一旦进入判定分支会 panic。
func TestEvaluateRulesWorkTimeUnsupportedNoMaintenance(t *testing.T) {
	workTime := 9999.0 * 3600 // 远超 maintenance_hours=5000h
	s := &telemetryv2.Sample{Diag: telemetryv2.Diag{WorkTimeTotal: &workTime}}

	require.Empty(t, testEngine().evaluateRules(context.Background(), "sn", s, l10Specs()))
	// 未声明未支持时会进入判定分支（nil repo → panic），故此处不对照调用；语义由
	// 现有 TestEvaluateRulesNoTrigger（不设置 WorkTimeTotal）与 14.3 文档覆盖。
}

// evaluateRules：paired_socket 被声明为未实现时整条并机判据跳过——垃圾掩码不再产生并机事件。
func TestEvaluateRulesSockUnsupportedNoParallelEvents(t *testing.T) {
	paired, online, on := uint32(3), uint32(1), uint32(1) // 3 配对、1 在线（在线者均在运行）
	s := &telemetryv2.Sample{Sock: telemetryv2.Sock{PairedSocket: &paired, OnlineSocket: &online, OnSocket: &on}}

	// 对照：未声明未实现（其它型号/旧行为）→ 仍判 PARALLEL_SLAVE_OFFLINE
	events := testEngine().evaluateRules(context.Background(), "sn", s, testHealthSpecs())
	require.Len(t, events, 1)
	require.Equal(t, model.RuleParallelSlaveOffline, events[0].RuleCode)
	require.Equal(t, uint32(2), events[0].Detail["offline_mask"])

	// 声明 unsupported（迁移 124 的 L10 规格）→ 0 条并机事件
	require.Empty(t, testEngine().evaluateRules(context.Background(), "sn", s, l10Specs()))

	// 部分支持：仅 paired_socket 未实现 → 同样不判定（online>on 的 info 事件也不产生，避免半截解读）
	partial := model.DefaultDiagnosticSpecs()
	partial.UnsupportedFields = []string{model.FieldKeyPairedSocket}
	require.Empty(t, testEngine().evaluateRules(context.Background(), "sn", s, partial))

	// 字段缺失（nil）时仍不判定：门控未改变"缺失即跳过"的既有收口语义
	s2 := &telemetryv2.Sample{Sock: telemetryv2.Sock{}}
	require.Empty(t, testEngine().evaluateRules(context.Background(), "sn", s2, l10Specs()))
	require.Empty(t, testEngine().evaluateRules(context.Background(), "sn", s2, testHealthSpecs()))
}
