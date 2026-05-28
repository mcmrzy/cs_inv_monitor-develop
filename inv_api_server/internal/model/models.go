package model

import "time"

type User struct {
	ID           int64      `json:"id"`
	Phone        string     `json:"phone"`
	Email        string     `json:"email"`
	PasswordHash string     `json:"-"`
	Nickname     string     `json:"nickname"`
	Avatar       string     `json:"avatar"`
	Role         int        `json:"role"`
	RegionID     *int64     `json:"region_id"`
	Status       int        `json:"status"`
	LastLoginAt  *time.Time `json:"last_login_at"`
	LastLoginIP  string     `json:"last_login_ip"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

type Station struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	Name        string     `json:"name"`
	Province    string     `json:"province"`
	City        string     `json:"city"`
	District    string     `json:"district"`
	Address     string     `json:"address"`
	Capacity    float64    `json:"capacity"`
	PanelCount  int        `json:"panel_count"`
	PeakPrice   float64    `json:"peak_price"`
	ValleyPrice float64    `json:"valley_price"`
	Latitude    float64    `json:"latitude"`
	Longitude   float64    `json:"longitude"`
	Status      int        `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	DeletedAt   *time.Time `json:"-"`
}

type Device struct {
	ID              int64      `json:"id"`
	SN              string     `json:"sn"`
	Model           string     `json:"model"`
	RatedPower      float64    `json:"rated_power"`
	FirmwareVersion string     `json:"firmware_version"`
	HardwareVersion string     `json:"hardware_version"`
	MACAddress      string     `json:"mac_address"`
	StationID       *int64     `json:"station_id"`
	UserID          int64      `json:"user_id"`
	Status          int        `json:"status"`
	LastOnlineAt    *time.Time `json:"last_online_at"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

type DeviceRealtimeData struct {
	DeviceSN             string                 `json:"device_sn"`
	DataTime             time.Time              `json:"data_time"`
	Online               bool                   `json:"online"`
	Manufacturer         string                 `json:"manufacturer"`
	Model                string                 `json:"model"`
	DeviceTypeCode       int                    `json:"device_type_code"`
	ArmVersion           string                 `json:"arm_version"`
	DSPVersion           string                 `json:"dsp_version"`
	ProtocolNumber       int                    `json:"protocol_number"`
	ProtocolVersion      int                    `json:"protocol_version"`
	NominalActivePower   float64                `json:"nominal_active_power"`
	NominalReactivePower float64                `json:"nominal_reactive_power"`
	OutputType           int                    `json:"output_type"`
	DailyPowerYields     float64                `json:"daily_power_yields"`
	TotalPowerYields     float64                `json:"total_power_yields"`
	TotalPowerYields01   float64                `json:"total_power_yields_01"`
	MonthlyPowerYields   float64                `json:"monthly_power_yields"`
	TotalRunningTime     int                    `json:"total_running_time"`
	DailyRunningTime     int                    `json:"daily_running_time"`
	InternalTemperature  float64                `json:"internal_temperature"`
	MPPTVoltage          []float64              `json:"mppt_voltage"`
	MPPTCurrent          []float64              `json:"mppt_current"`
	TotalDCPower         float64                `json:"total_dc_power"`
	PhaseAVoltage        float64                `json:"phase_a_voltage"`
	PhaseBVoltage        float64                `json:"phase_b_voltage"`
	PhaseCVoltage        float64                `json:"phase_c_voltage"`
	PhaseACurrent        float64                `json:"phase_a_current"`
	PhaseBCurrent        float64                `json:"phase_b_current"`
	PhaseCCurrent        float64                `json:"phase_c_current"`
	TotalActivePower     float64                `json:"total_active_power"`
	TotalReactivePower   float64                `json:"total_reactive_power"`
	TotalApparentPower   float64                `json:"total_apparent_power"`
	PowerFactor          float64                `json:"power_factor"`
	GridFrequency        float64                `json:"grid_frequency"`
	WorkState1           string                 `json:"work_state_1"`
	WorkState1Code       int                    `json:"work_state_1_code"`
	WorkState2           int                    `json:"work_state_2"`
	InverterState1       int                    `json:"inverter_state_1"`
	InverterState2       int                    `json:"inverter_state_2"`
	InsulationResistance int                    `json:"insulation_resistance"`
	BusVoltage           float64                `json:"bus_voltage"`
	NegativeGroundVoltage float64               `json:"negative_ground_voltage"`
	PIDWorkState         int                    `json:"pid_work_state"`
	PIDAlarmCode         int                    `json:"pid_alarm_code"`
	CountryCode          int                    `json:"country_code"`
	MeterTotalPower      float64                `json:"meter_total_power"`
	MeterPhaseAPower     float64                `json:"meter_phase_a_power"`
	MeterPhaseBPower     float64                `json:"meter_phase_b_power"`
	MeterPhaseCPower     float64                `json:"meter_phase_c_power"`
	LoadPower            float64                `json:"load_power"`
	DailyFeedEnergy      float64                `json:"daily_feed_energy"`
	TotalFeedEnergy      float64                `json:"total_feed_energy"`
	DailyGridImport      float64                `json:"daily_grid_import"`
	TotalGridImport      float64                `json:"total_grid_import"`
	StringCurrents       []float64              `json:"string_currents"`
	ActivePowerSetting   float64                `json:"active_power_setting"`
	ReactivePowerSetting float64                `json:"reactive_power_setting"`
	PowerFactorSetting   float64                `json:"power_factor_setting"`
	ESP32Timestamp       int                    `json:"esp32_timestamp"`
}

type Alarm struct {
	ID           int64      `json:"id"`
	DeviceSN     string     `json:"device_sn"`
	StationID    *int64     `json:"station_id"`
	UserID       int64      `json:"user_id"`
	AlarmLevel   int        `json:"alarm_level"`
	FaultCode    string     `json:"fault_code"`
	FaultMessage string     `json:"fault_message"`
	FaultDetail  string     `json:"fault_detail"`
	Status       int        `json:"status"`
	OccurredAt   time.Time  `json:"occurred_at"`
	RecoveredAt  *time.Time `json:"recovered_at"`
	HandledAt    *time.Time `json:"handled_at"`
	HandledBy    *int64     `json:"handled_by"`
	CreatedAt    time.Time  `json:"created_at"`
}

type DeviceShare struct {
	ID            int64     `json:"id"`
	DeviceSN      string    `json:"device_sn"`
	OwnerID       int64     `json:"owner_id"`
	ShareToUserID int64     `json:"share_to_user_id"`
	Permission    string    `json:"permission"`
	CreatedAt     time.Time `json:"created_at"`
}

type DeviceDayData struct {
	DeviceSN      string    `json:"device_sn"`
	DataDate      time.Time `json:"data_date"`
	EnergyProduce float64   `json:"energy_produce"`
	EnergyConsume float64   `json:"energy_consume"`
	EnergySell    float64   `json:"energy_sell"`
	EnergyBuy     float64   `json:"energy_buy"`
	MaxPower      float64   `json:"max_power"`
	AvgSOC        int       `json:"avg_soc"`
	RunMinutes    int       `json:"run_minutes"`
	Income        float64   `json:"income"`
}

type StationDayData struct {
	StationID     int64     `json:"station_id"`
	DataDate      time.Time `json:"data_date"`
	EnergyProduce float64   `json:"energy_produce"`
	EnergyConsume float64   `json:"energy_consume"`
	EnergySell    float64   `json:"energy_sell"`
	EnergyBuy     float64   `json:"energy_buy"`
	MaxPower      float64   `json:"max_power"`
	DeviceCount   int       `json:"device_count"`
	OnlineCount   int       `json:"online_count"`
	FaultCount    int       `json:"fault_count"`
	Income        float64   `json:"income"`
}

type UserNotifySetting struct {
	ID               int64     `json:"id"`
	UserID           int64     `json:"user_id"`
	PushEnabled      bool      `json:"push_enabled"`
	AlarmPush        bool      `json:"alarm_push"`
	OfflinePush      bool      `json:"offline_push"`
	SystemPush       bool      `json:"system_push"`
	QuietHoursStart  string    `json:"quiet_hours_start"`
	QuietHoursEnd    string    `json:"quiet_hours_end"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type Message struct {
	ID        int64     `json:"id"`
	UserID    int64     `json:"user_id"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	Type      string    `json:"type"`
	IsRead    bool      `json:"is_read"`
	ExtraData string    `json:"extra_data"`
	CreatedAt time.Time `json:"created_at"`
}

type VerificationCode struct {
	ID        int64     `json:"id"`
	Phone     string    `json:"phone"`
	Code      string    `json:"code"`
	Type      string    `json:"type"`
	ExpiresAt time.Time `json:"expires_at"`
	Used      bool      `json:"used"`
	CreatedAt time.Time `json:"created_at"`
}

type OperationLog struct {
	ID              int64     `json:"id"`
	UserID          int64     `json:"user_id"`
	DeviceSN        string    `json:"device_sn"`
	OperationType   string    `json:"operation_type"`
	OperationDetail string    `json:"operation_detail"`
	Result          string    `json:"result"`
	ErrorMessage    string    `json:"error_message"`
	IPAddress       string    `json:"ip_address"`
	CreatedAt       time.Time `json:"created_at"`
}
