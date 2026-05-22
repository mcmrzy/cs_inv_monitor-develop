package model

import (
	"encoding/json"
	"time"
)

// ==================== 设备信息 (cs_inv/{sn}/info) ====================
type DeviceInfo struct {
	SN              string   `json:"sn"`
	Model           string   `json:"model"`
	Manufacturer    string   `json:"manufacturer"`
	FirmwareARM     string   `json:"firmware_arm"`
	FirmwareESP     string   `json:"firmware_esp"`
	Type            string   `json:"type"`
	Phase           string   `json:"phase"`
	RatedPower      int      `json:"rated_power"`
	RatedVoltage    int      `json:"rated_voltage"`
	RatedFreq       int      `json:"rated_freq"`
	BatteryVoltage  int      `json:"battery_voltage"`
	BatteryTypes    []string `json:"battery_types"`
	MPPTCount       int      `json:"mppt_count"`
	PVMaxVoltage    int      `json:"pv_max_voltage"`
	PVMaxPower      int      `json:"pv_max_power"`
	BMSCount        int      `json:"bms_count"`
	CellCount       int      `json:"cell_count"`
}

// ==================== 在线状态 (cs_inv/{sn}/status) ====================
type OnlineStatus struct {
	Online   bool              `json:"online"`
	RSSI     int               `json:"rssi"`
	Location *LocationInfo     `json:"location"`
}

type LocationInfo struct {
	IP   string `json:"ip"`
	City string `json:"city"`
}

// ==================== 交流输出 (cs_inv/{sn}/data/ac) ====================
type ACData struct {
	Voltage      float64 `json:"voltage"`
	Current      float64 `json:"current"`
	Power        float64 `json:"power"`
	Apparent     float64 `json:"apparent"`
	Reactive     float64 `json:"reactive"`
	Frequency    float64 `json:"frequency"`
	PF           float64 `json:"pf"`
	LoadPercent  float64 `json:"load_percent"`
	THDV         float64 `json:"thd_v"`
	THDI         float64 `json:"thd_i"`
	DCInjection  float64 `json:"dc_injection"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 电池 BMS (cs_inv/{sn}/data/battery) ====================
type BatteryData struct {
	SOC              float64 `json:"soc"`
	SOH              float64 `json:"soh"`
	Voltage          float64 `json:"voltage"`
	Current          float64 `json:"current"`
	Power            float64 `json:"power"`
	CapacityRemain   float64 `json:"capacity_remain"`
	CapacityTotal    float64 `json:"capacity_total"`
	CycleCount       int     `json:"cycle_count"`
	TempMax          float64 `json:"temp_max"`
	TempMin          float64 `json:"temp_min"`
	CellVoltMax      float64 `json:"cell_volt_max"`
	CellVoltMin      float64 `json:"cell_volt_min"`
	CellVoltDiff     float64 `json:"cell_volt_diff"`
	ChargeState      string  `json:"charge_state"`
	BatteryType      string  `json:"battery_type"`
	ProtectStatus1   int     `json:"protect_status1"`
	ProtectStatus2   int     `json:"protect_status2"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 光伏 MPPT (cs_inv/{sn}/data/pv) ====================
type PVData struct {
	PVVoltage  float64 `json:"pv_voltage"`
	PVCurrent  float64 `json:"pv_current"`
	PVPower    float64 `json:"pv_power"`
	MPPTState  string  `json:"mppt_state"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 系统状态 (cs_inv/{sn}/data/status) ====================
type SystemStatus struct {
	State       string  `json:"state"`
	FaultCode   int     `json:"fault_code"`
	AlarmCode   int     `json:"alarm_code"`
	TempInv     float64 `json:"temp_inv"`
	TempMOS     float64 `json:"temp_mos"`
	TempAmbient float64 `json:"temp_ambient"`
	DCBusVoltage float64 `json:"dc_bus_voltage"`
	FanSpeed    int     `json:"fan_speed"`
	Efficiency  float64 `json:"efficiency"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 能量统计 (cs_inv/{sn}/data/energy) ====================
type EnergyData struct {
	DailyPV         float64 `json:"daily_pv"`
	TotalPV         float64 `json:"total_pv"`
	DailyCharge     float64 `json:"daily_charge"`
	TotalCharge     float64 `json:"total_charge"`
	DailyDischarge  float64 `json:"daily_discharge"`
	TotalDischarge  float64 `json:"total_discharge"`
	DailyLoad       float64 `json:"daily_load"`
	TotalLoad       float64 `json:"total_load"`
	RuntimeHours    int     `json:"runtime_hours"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 电芯数据 (cs_inv/{sn}/data/cells) ====================
type CellsData struct {
	CellCount        int       `json:"cell_count"`
	Voltages         []float64 `json:"voltages"`
	Temps            []float64 `json:"temps"`
	ChargeAhTotal    float64   `json:"charge_ah_total"`
	DischargeAhTotal float64   `json:"discharge_ah_total"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 告警事件 (cs_inv/{sn}/data/alarm) ====================
type AlarmData struct {
	Event     string                 `json:"event"`
	Timestamp int64                  `json:"timestamp"`
	Source    string                 `json:"source"`
	FaultCode int                    `json:"fault_code"`
	FaultDesc string                 `json:"fault_desc"`
	AlarmCode int                    `json:"alarm_code"`
	Trigger   map[string]interface{} `json:"trigger"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 命令响应 (cs_inv/{sn}/cmd/response) ====================
type CommandResponse struct {
	Result    string `json:"result"`
	Cmd       string `json:"cmd"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`

	SN         string    `json:"-"`
	ReceivedAt time.Time `json:"-"`
}

// ==================== 命令下发 ====================
type DeviceCommand struct {
	DeviceSN string                 `json:"device_sn"`
	CmdType  string                 `json:"cmd_type"`
	Params   map[string]interface{} `json:"params"`
	ReqID    string                 `json:"req_id"`
}

// ==================== 设备表模型 ====================
type Device struct {
	ID             int64      `json:"id"`
	SN             string     `json:"sn"`
	Model          string     `json:"model"`
	RatedPower     float64    `json:"rated_power"`
	FirmwareARM    string     `json:"firmware_arm"`
	FirmwareESP    string     `json:"firmware_esp"`
	Status         int        `json:"status"`
	LastOnlineAt   *time.Time `json:"last_online_at"`
	IPAddress      string     `json:"ip_address"`
	City           string     `json:"city"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

// ==================== 运行时聚合缓存 ====================
type DeviceRealtime struct {
	DeviceSN string     `json:"device_sn"`
	AC       *ACData    `json:"ac,omitempty"`
	Battery  *BatteryData `json:"battery,omitempty"`
	PV       *PVData    `json:"pv,omitempty"`
	SysStatus *SystemStatus `json:"sys_status,omitempty"`
	Energy   *EnergyData `json:"energy,omitempty"`
	Cells    *CellsData  `json:"cells,omitempty"`
	OnlineStatus *OnlineStatus `json:"online_status,omitempty"`
	UpdatedAt time.Time  `json:"updated_at"`
}

// ==================== JSON 辅助 ====================
func (d *ACData) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *BatteryData) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *PVData) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *SystemStatus) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *EnergyData) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *CellsData) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *AlarmData) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *CommandResponse) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}

func (d *DeviceInfo) RawJSON() json.RawMessage {
	b, _ := json.Marshal(d)
	return b
}
