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
