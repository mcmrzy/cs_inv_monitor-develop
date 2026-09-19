package model

import "time"

// 设备调试会话状态机。
// starting -> active -> stopping -> stopped
//                    |         \-> expired（到期兜底，设备侧 TTL 最终收敛）
//                    \-> interrupted（样本中断/设备离线，恢复后须重新开启）
// starting 超时无命令回执 -> failed
const (
	DebugSessionStarting    = "starting"
	DebugSessionActive      = "active"
	DebugSessionStopping    = "stopping"
	DebugSessionStopped     = "stopped"
	DebugSessionExpired     = "expired"
	DebugSessionInterrupted = "interrupted"
	DebugSessionFailed      = "failed"
)

// IsDebugSessionOccupying 会话是否处于「占用中」状态（阻止同设备开启新会话）。
func IsDebugSessionOccupying(status string) bool {
	switch status {
	case DebugSessionStarting, DebugSessionActive, DebugSessionStopping:
		return true
	}
	return false
}

// IsDebugSessionTerminal 会话是否已终结。
func IsDebugSessionTerminal(status string) bool {
	return !IsDebugSessionOccupying(status)
}

// 调试会话开启来源
const (
	DebugSourceWeb = "web"
	DebugSourceApp = "app"
)

// DeviceDebugSession 单设备调试会话。曲线样本不入本表，仅保存调试意图与生命周期。
type DeviceDebugSession struct {
	ID              int64      `json:"id"`
	DeviceSN        string     `json:"device_sn"`
	RequestID       string     `json:"request_id"`
	Status          string     `json:"status"`
	IntervalSeconds int        `json:"interval_seconds"`
	DurationSeconds int        `json:"duration_seconds"`
	StartedAt       time.Time  `json:"started_at"`
	ExpiresAt       time.Time  `json:"expires_at"`
	StoppedAt       *time.Time `json:"stopped_at"`
	RequestedBy     int64      `json:"requested_by"`
	Source          string     `json:"source"`
	StartTaskID     string     `json:"start_task_id"`
	StopTaskID      string     `json:"stop_task_id"`
	LastSampleAt    *time.Time `json:"last_sample_at"`
	FailureReason   string     `json:"failure_reason"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// DebugSamplePoint 调试曲线原始样本点。
// 字段为白名单直读 device_telemetry_3min，不含 raw_envelope。
// 指标为可证实的真实测点：MPPT 电流为 Buck 电流（协议无独立 PV 输入电流），
// 逆变组为直流母线电压 + 逆变电流，负载组为交流输出测点。
type DebugSamplePoint struct {
	Time            time.Time          `json:"time"`
	ReceivedAt      *time.Time         `json:"received_at"`
	QualityFlags    int                `json:"quality_flags"`
	ProtocolVersion int                `json:"protocol_version"`
	Metrics         DebugSampleMetrics `json:"metrics"`
}

// DebugSampleMetrics 四组曲线的原始指标（指针语义：null = 该点无数据，绘图断线）。
type DebugSampleMetrics struct {
	PV1Voltage     *float64 `json:"pv1_voltage"`
	Buck1Current   *float64 `json:"buck1_current"`
	PV2Voltage     *float64 `json:"pv2_voltage"`
	Buck2Current   *float64 `json:"buck2_current"`
	BatteryVoltage *float64 `json:"battery_voltage"`
	BatteryCurrent *float64 `json:"battery_current"`
	DCBusVoltage   *float64 `json:"dc_bus_voltage"`
	InvCurrent     *float64 `json:"inv_current"`
	ACVoltage      *float64 `json:"ac_voltage"`
	ACCurrent      *float64 `json:"ac_current"`
}
