package telemetry

import "time"

const (
	QualityNullValue uint32 = 1 << iota
	QualityOutOfRange
	QualityClockInvalid
	QualityOutOfOrder
	QualityCounterReset
	QualityCommFault
)

// Compatibility aliases used by the storage and query layers.
const (
	QualityClockSkew    = QualityClockInvalid
	QualityInconsistent = QualityOutOfRange
	QualityPartial      = QualityNullValue
	QualityBackfill     = QualityOutOfOrder
)

type Sample struct {
	ProtocolVersion uint16
	DeviceSN        string
	Sequence        uint32
	EventTime       time.Time
	ReceivedAt      time.Time
	QualityFlags    uint32
	DataHash        string
	RawEnvelope     []byte
	AC              AC
	Battery         Battery
	PV              PV
	System          System
	Energy          Energy
	Cells           Cells
	// V2.1 (CS-L10-6K2) 新增：风扇 / 诊断量 / 插座状态（57 值扩展）
	Fan             Fan
	Diag            Diag
	Sock            Sock
}

type AC struct {
	Voltage, Current, ActivePower, ApparentPower    *float64
	Frequency, PowerFactor, LoadPercent, VoltageTHD *float64
	// V2 (CS-L10-6K2) 扩展：电网/输入/旁路/AC 充电
	GridVoltage, GridFrequency                  *float64
	ACInputPower, ACInputApparentPower          *float64
	ACBypassPower, ACBypassApparentPower        *float64
	ACChargePower, ACChargeApparentPower        *float64
	ACChargeCurrent                             *float64
}

type Battery struct {
	SOC, SOH, Voltage, Current, Power                     *float64
	CapacityRemain, CapacityTotal                         *float64
	CycleCount                                            *uint32
	TempMax, TempMin, CellVoltageMax, CellVoltageMin      *float64
	CellVoltageDiff                                       *float64
	State                                                 *uint8
	ProtectStatus, FaultCode                              *uint32
	MaxChargeCurrent, MaxDischargeCurrent                 *float64
	ChargeVoltageRef, DischargeCutoffVoltage, Temperature *float64
	ChargeRequestCurrentX10, ChargeRequestVoltageX10      *uint32
	// V2 (CS-L10-6K2) 扩展：充/放电功率（battery_power 由两者推导）
	ChargePower, DischargePower                           *float64
}

type PV struct {
	PV1Voltage, PV1Current, PV1Power *float64
	PV2Voltage, PV2Current, PV2Power *float64
	TotalPower                       *float64
	MPPTState                        *uint8
	// V2 (CS-L10-6K2) 扩展：Buck 电流
	Buck1Current, Buck2Current       *float64
}

type System struct {
	WorkState            *uint8
	FaultCode, AlarmCode *uint32
	InverterTemperature  *float64
	MOSTemperature       *float64
	AmbientTemperature   *float64
	DCBusVoltage         *float64
	RuntimeHours         *uint32
	FanSpeedPercent      *uint8
	Efficiency           *float64
	SystemMode           *uint32
	// V2 (CS-L10-6K2) 扩展：状态位/告警/温度/过充
	SysStatus, BmsWarning              *uint32
	Warning                            *uint64
	BatteryOvercharge                  *uint8
	BoostTemperature, TransformerTemperature, PVTemperature *float64
}

type Energy struct {
	DailyPV, TotalPV               *float64
	DailyCharge, TotalCharge       *float64
	DailyDischarge, TotalDischarge *float64
	DailyLoad, TotalLoad           *float64
	TotalChargeCapacity            *float64
	TotalDischargeCapacity         *float64
	TotalChargeTime                *uint32
	TotalDischargeTime             *uint32
	// V2 (CS-L10-6K2) 扩展：发电机/AC 充电/旁路/输出电量
	GenDaily, GenTotal                       *float64
	ACChargeDaily, ACChargeTotal             *float64
	ACBypassDaily, ACBypassTotal             *float64
	OutputDaily, OutputTotal                 *float64
}

type Cells struct {
	Voltages     []*float64
	Temperatures []*float64
}

// Fan V2.1 (CS-L10-6K2) 风扇转速（%，0=停转 100=全速）。
// 散热诊断输入（与温度组合判定风扇异常）与健康度扣分项。
type Fan struct {
	MPPTSpeed *float64 // mppt_fan_speed（%）
	InvSpeed  *float64 // inv_fan_speed（%）
}

// Diag V2.1 (CS-L10-6K2) 诊断量。
// work_time_total 跨过维护阈值触发 MAINTENANCE_DUE。
type Diag struct {
	InvCurrent            *float64 // inv_current（A，0.1 缩放）
	ParallelChargeCurrent *float64 // parallel_charge_current（A）
	WorkTimeTotal         *float64 // work_time_total（s，u32）
}

// Sock V2.1 (CS-L10-6K2) 插座状态（u16 位掩码，每 bit 一个并联从机）。
// 并机拓扑诊断输入（paired/online/on）。
type Sock struct {
	PairedSocket *uint32 // paired_socket（已配对插座位掩码）
	OnlineSocket *uint32 // online_socket（在线插座位掩码）
	OnSocket     *uint32 // on_socket（运行中插座位掩码）
}
