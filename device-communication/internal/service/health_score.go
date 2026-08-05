package service

import (
	"inv-device-server/internal/model"
	telemetryv2 "inv-device-server/internal/telemetry"
)

// ComputeHealth 按 V2.1 文档 14.4 计算健康度评分：
// 基础 100，扣分项（活跃 fault -30 / 活跃 warning -10 / 温度>75°C -15 /
// 风扇<30% -15 / SOC<20 -10 / 并机掉线 -5），下限 0。
// 分级：≥90 健康 / 70-89 良好 / 50-69 注意 / <50 需维护。
func ComputeHealth(s *telemetryv2.Sample, active []model.DiagnosticEvent, specs model.DiagnosticSpecs) model.HealthResult {
	score := 100.0
	factors := make(map[string]float64)

	hasFault, hasWarning, parallelOffline := classifyActiveDiagnostics(active)
	if hasFault {
		score -= specs.DeductFault
		factors["active_fault"] = specs.DeductFault
	}
	if hasWarning {
		score -= specs.DeductWarning
		factors["active_warning"] = specs.DeductWarning
	}
	if parallelOffline {
		score -= specs.DeductParallelOffline
		factors["parallel_offline"] = specs.DeductParallelOffline
	}
	if tempHigh(s, specs.HealthTempHighC) {
		score -= specs.DeductTempHigh
		factors["temp_high"] = specs.DeductTempHigh
	}
	if fanAbnormal(s, specs.FanSpeedLowPercent) {
		score -= specs.DeductFanAbnormal
		factors["fan_abnormal"] = specs.DeductFanAbnormal
	}
	if lowSOC(s) {
		score -= specs.DeductLowSOC
		factors["low_soc"] = specs.DeductLowSOC
	}

	if score < 0 {
		score = 0
	}
	return model.HealthResult{
		Score:   score,
		Level:   healthLevel(score),
		Factors: factors,
	}
}

func classifyActiveDiagnostics(active []model.DiagnosticEvent) (hasFault, hasWarning, parallelOffline bool) {
	for _, e := range active {
		switch e.Level {
		case "fault":
			hasFault = true
		case "warning":
			hasWarning = true
		}
		if e.RuleCode == model.RuleParallelSlaveOffline {
			parallelOffline = true
		}
	}
	return hasFault, hasWarning, parallelOffline
}

// tempHigh 任一核心温度超过健康扣分阈值（inverter/boost，见 14.4）。
func tempHigh(s *telemetryv2.Sample, threshold float64) bool {
	for _, v := range []*float64{s.System.InverterTemperature, s.System.BoostTemperature} {
		if v != nil && *v > threshold {
			return true
		}
	}
	return false
}

// fanAbnormal 任一风扇转速低于阈值（见 14.4）。
func fanAbnormal(s *telemetryv2.Sample, threshold float64) bool {
	for _, v := range []*float64{s.Fan.MPPTSpeed, s.Fan.InvSpeed} {
		if v != nil && *v < threshold {
			return true
		}
	}
	return false
}

func lowSOC(s *telemetryv2.Sample) bool {
	return s.Battery.SOC != nil && *s.Battery.SOC < 20
}

func healthLevel(score float64) string {
	switch {
	case score >= 90:
		return model.HealthLevelHealthy
	case score >= 70:
		return model.HealthLevelGood
	case score >= 50:
		return model.HealthLevelAttention
	default:
		return model.HealthLevelMaintenance
	}
}
