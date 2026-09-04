package model

import "time"

// ==================== 诊断与健康度（V2.1，CS-L10-6K2） ====================
// 规则与阈值见 docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md 第 14 节。

// DiagnosticSpecs 诊断与健康度阈值，来源 device_models.specifications.diagnostics jsonb。
// 阈值均为建议值（待厂家签字），读取失败时使用 DefaultDiagnosticSpecs 兜底。
type DiagnosticSpecs struct {
	FanSpeedLowPercent    float64 `json:"fan_speed_low_percent"`    // 风扇低速阈值（%）
	FanAbnormalTempC      float64 `json:"fan_abnormal_temp_c"`      // 风扇异常组合温度阈值（°C）
	OverheatTempC         float64 `json:"overheat_temp_c"`          // 过温阈值（°C）
	HealthTempHighC       float64 `json:"health_temp_high_c"`       // 健康度温度扣分阈值（°C）
	MaintenanceHours      float64 `json:"maintenance_hours"`        // 维护提醒累计时长阈值（h）
	DeductFault           float64 `json:"deduct_fault"`             // 活跃故障扣分
	DeductWarning         float64 `json:"deduct_warning"`           // 活跃告警扣分
	DeductTempHigh        float64 `json:"deduct_temp_high"`         // 温度过高扣分
	DeductFanAbnormal     float64 `json:"deduct_fan_abnormal"`      // 风扇异常扣分
	DeductLowSOC          float64 `json:"deduct_low_soc"`           // 低电量扣分
	DeductParallelOffline float64 `json:"deduct_parallel_offline"`  // 并机掉线扣分
}

// DefaultDiagnosticSpecs 返回默认阈值（与迁移 096 写入 device_models.specifications 的初值一致）。
func DefaultDiagnosticSpecs() DiagnosticSpecs {
	return DiagnosticSpecs{
		FanSpeedLowPercent:    30,
		FanAbnormalTempC:      70,
		OverheatTempC:         85,
		HealthTempHighC:       75,
		MaintenanceHours:      5000,
		DeductFault:           30,
		DeductWarning:         10,
		DeductTempHigh:        15,
		DeductFanAbnormal:     15,
		DeductLowSOC:          10,
		DeductParallelOffline: 5,
	}
}

// 诊断规则码（与 V2.1 文档 14.1-14.3 一致）。
const (
	RuleInvFanAbnormal      = "INV_FAN_ABNORMAL"      // 逆变风扇异常（fault）
	RuleMpptFanAbnormal     = "MPPT_FAN_ABNORMAL"     // MPPT 风扇异常（fault）
	RuleThermalOverheat     = "THERMAL_OVERHEAT"      // 过温（fault）
	RuleParallelSlaveOffline = "PARALLEL_SLAVE_OFFLINE" // 并机从机离线（warning）
	RuleParallelNotRunning  = "PARALLEL_SLAVE_NOT_RUNNING" // 并机从机未运行（info）
	RuleMaintenanceDue      = "MAINTENANCE_DUE"       // 维护提醒（warning）
	RuleConfigDrift         = "CONFIG_DRIFT"          // 配置漂移（warning，见 V2.1 文档 9.4）

	// 恢复判定窗口：持续 3 个心跳周期（180s×3）内触发条件不成立即恢复。
	ResolveHeartbeatPeriods = 3
	HeartbeatPeriodSeconds  = 180
)

// DiagnosticEvent 单条诊断事件（device_diagnostics 行 + 聚合信息）。
type DiagnosticEvent struct {
	RuleCode string         `json:"rule_code"`
	Level    string         `json:"level"` // fault / warning / info
	Status   string         `json:"status"`
	Detail   map[string]any `json:"detail"`
	FirstAt  time.Time      `json:"first_at"`
	LastAt   time.Time      `json:"last_at"`
	Count    int            `json:"count"`
}

// HealthResult 健康度评分结果（14.4：基础 100 扣分制，下限 0）。
type HealthResult struct {
	Score   float64            `json:"score"`
	Level   string             `json:"level"` // healthy / good / attention / maintenance
	Factors map[string]float64 `json:"factors"`
}

// 健康度分级（14.4）。
const (
	HealthLevelHealthy     = "healthy"     // ≥90 健康
	HealthLevelGood        = "good"        // 70-89 良好
	HealthLevelAttention   = "attention"   // 50-69 注意
	HealthLevelMaintenance = "maintenance" // <50 需维护
)
