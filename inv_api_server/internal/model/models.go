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
	ID             int64      `json:"id"`
	SN             string     `json:"sn"`
	Model          string     `json:"model"`
	Manufacturer   string     `json:"manufacturer"`
	FirmwareArm    string     `json:"firmware_arm"`
	FirmwareEsp    string     `json:"firmware_esp"`
	DeviceType     string     `json:"device_type"`
	RatedPower     float64    `json:"rated_power"`
	RatedVoltage   float64    `json:"rated_voltage"`
	RatedFreq      float64    `json:"rated_freq"`
	BatteryVoltage float64    `json:"battery_voltage"`
	BatteryType    string     `json:"battery_type"`
	CellCount      int        `json:"cell_count"`
	StationID      *int64     `json:"station_id"`
	UserID         int64      `json:"user_id"`
	Status         int        `json:"status"`
	CurrentPower   float64    `json:"current_power"`
	DailyEnergy    float64    `json:"daily_energy"`
	LastOnlineAt   *time.Time `json:"last_online_at"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
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

type DeviceModel struct {
	ID            int64      `json:"id"`
	ModelCode     string     `json:"model_code"`
	ModelName     string     `json:"model_name"`
	Manufacturer  string     `json:"manufacturer"`
	Category      string     `json:"category"`
	RatedPowerKw  float64    `json:"rated_power_kw"`
	Description   string     `json:"description"`
	IsActive      bool       `json:"is_active"`
	DeviceCount   int        `json:"device_count"`
	CreatedAt     string     `json:"created_at"`
	UpdatedAt     string     `json:"updated_at"`
}

type DeviceModelField struct {
	ID        int64   `json:"id"`
	ModelID   int32   `json:"model_id"`
	FieldKey  string  `json:"field_key"`
	FieldName string  `json:"field_name"`
	FieldType string  `json:"field_type"`
	Unit      string  `json:"unit"`
	Sort      int     `json:"sort"`
	IsShow    bool    `json:"is_show"`
	IsControl bool    `json:"is_control"`
	ParseRule *string `json:"parse_rule"`
}

type AuditLog struct {
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

type RolePermission struct {
	ID        int64     `json:"id"`
	Role      int       `json:"role"`
	Resource  string    `json:"resource"`
	Action    string    `json:"action"`
	IsAllowed bool      `json:"is_allowed"`
	CreatedAt time.Time `json:"created_at"`
}

type Firmware struct {
	ID         int64      `json:"id"`
	Model      string     `json:"model"`
	Version    string     `json:"version"`
	FileURL    string     `json:"file_url"`
	FileSize   int64      `json:"file_size"`
	FileMD5    string     `json:"file_md5"`
	FileSHA256 string     `json:"file_sha256"`
	Changelog  string     `json:"changelog"`
	IsForce    bool       `json:"is_force"`
	UploadedBy int64      `json:"uploaded_by"`
	Status     int        `json:"status"`
	CreatedAt  time.Time  `json:"created_at"`
	UpdatedAt  time.Time  `json:"updated_at"`
	TargetChip string     `json:"target_chip"`
	MainVersion string    `json:"main_version"`
}

type OtaTask struct {
	ID              string     `json:"id"`
	Name            string     `json:"name"`
	FirmwareID      int64      `json:"firmware_id"`
	FirmwareVersion string     `json:"firmware_version"`
	Model           string     `json:"model"`
	TargetType      string     `json:"target_type"`
	TargetValue     string     `json:"target_value"`
	TotalCount      int        `json:"total_count"`
	SuccessCount    int        `json:"success_count"`
	FailCount       int        `json:"fail_count"`
	Status          string     `json:"status"`
	Description     string     `json:"description"`
	CreatedBy       int64      `json:"created_by"`
	PushStrategy    string     `json:"push_strategy"`
	PushPercentage  int        `json:"push_percentage"`
	BatchSize       int        `json:"batch_size"`
	CreatedAt       time.Time  `json:"created_at"`
	StartedAt       *time.Time `json:"started_at"`
	CompletedAt     *time.Time `json:"completed_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

type OtaTaskDevice struct {
	ID           int64      `json:"id"`
	TaskID       string     `json:"task_id"`
	DeviceSN     string     `json:"device_sn"`
	OldVersion   string     `json:"old_version"`
	NewVersion   string     `json:"new_version"`
	Status       string     `json:"status"`
	Progress     int        `json:"progress"`
	ErrorMessage string     `json:"error_message"`
	MQTTMessage  string     `json:"mqtt_message"`
	StartedAt    *time.Time `json:"started_at"`
	CompletedAt  *time.Time `json:"completed_at"`
	CreatedAt    time.Time  `json:"created_at"`
}

type ParallelConfig struct {
	ID                        int64     `json:"id"`
	GroupName                 string    `json:"group_name"`
	PhaseConfig               string    `json:"phase_config"`
	MasterSN                  string    `json:"master_sn"`
	SlaveSNs                  string    `json:"slave_sns"`
	CirculatingCurrentThreshold float64  `json:"circulating_current_threshold"`
	LoadBalanceDeviation      float64   `json:"load_balance_deviation"`
	CreatedBy                 int64     `json:"created_by"`
	Status                    int       `json:"status"`
	CreatedAt                 time.Time `json:"created_at"`
	UpdatedAt                 time.Time `json:"updated_at"`
}

type ParallelStatus struct {
	ID                int64     `json:"id"`
	ParallelID        int64     `json:"parallel_id"`
	DeviceSN          string    `json:"device_sn"`
	Role              string    `json:"role"`
	SyncStatus        string    `json:"sync_status"`
	OutputPower       float64   `json:"output_power"`
	CirculatingCurrent float64  `json:"circulating_current"`
	DataTime          time.Time `json:"data_time"`
}

type SystemConfig struct {
	ID          int64     `json:"id"`
	ConfigKey   string    `json:"config_key"`
	ConfigValue string    `json:"config_value"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
