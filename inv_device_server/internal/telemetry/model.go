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
}

type PV struct {
	PV1Voltage, PV1Current, PV1Power *float64
	PV2Voltage, PV2Current, PV2Power *float64
	TotalPower                       *float64
	MPPTState                        *uint8
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
}

type Cells struct {
	Voltages     []*float64
	Temperatures []*float64
}
