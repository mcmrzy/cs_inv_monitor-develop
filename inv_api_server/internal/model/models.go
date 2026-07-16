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
	ParentID     *int64     `json:"parent_id"`
	Status       int        `json:"status"`
	Timezone     string     `json:"timezone"`
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
	Timezone    string     `json:"timezone"`
	Status      int        `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	DeletedAt   *time.Time `json:"-"`
}

type Device struct {
	ID             int64      `json:"id"`
	SN             string     `json:"sn"`
	Model          string     `json:"model"`
	ModelID        int64      `json:"model_id"`
	Manufacturer   string     `json:"manufacturer"`
	FirmwareArm    string     `json:"firmware_arm"`
	FirmwareEsp    string     `json:"firmware_esp"`
	FirmwareDSP    string     `json:"firmware_dsp"`
	FirmwareBMS    string     `json:"firmware_bms"`
	MainVersion    string     `json:"main_version"`
	DeviceType     string     `json:"device_type"`
	RatedPower     float64    `json:"rated_power"`
	RatedVoltage   float64    `json:"rated_voltage"`
	RatedFreq      float64    `json:"rated_freq"`
	BatteryVoltage float64    `json:"battery_voltage"`
	BatteryType    string     `json:"battery_type"`
	CellCount      int        `json:"cell_count"`
	StationID      *int64     `json:"station_id"`
	StationName    string     `json:"station_name"`
	UserID         int64      `json:"user_id"`
	Timezone       string     `json:"timezone"`
	Status         int        `json:"status"`
	CurrentPower   float64    `json:"current_power"`
	DailyEnergy    float64    `json:"daily_energy"`
	LastOnlineAt   *time.Time `json:"last_online_at"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

type DeviceRealtimeData struct {
	DeviceSN              string    `json:"device_sn"`
	DataTime              time.Time `json:"data_time"`
	Online                bool      `json:"online"`
	Manufacturer          string    `json:"manufacturer"`
	Model                 string    `json:"model"`
	DeviceTypeCode        int       `json:"device_type_code"`
	ArmVersion            string    `json:"arm_version"`
	DSPVersion            string    `json:"dsp_version"`
	ProtocolNumber        int       `json:"protocol_number"`
	ProtocolVersion       int       `json:"protocol_version"`
	NominalActivePower    float64   `json:"nominal_active_power"`
	NominalReactivePower  float64   `json:"nominal_reactive_power"`
	OutputType            int       `json:"output_type"`
	DailyPowerYields      float64   `json:"daily_power_yields"`
	TotalPowerYields      float64   `json:"total_power_yields"`
	TotalPowerYields01    float64   `json:"total_power_yields_01"`
	MonthlyPowerYields    float64   `json:"monthly_power_yields"`
	TotalRunningTime      int       `json:"total_running_time"`
	DailyRunningTime      int       `json:"daily_running_time"`
	InternalTemperature   float64   `json:"internal_temperature"`
	MPPTVoltage           []float64 `json:"mppt_voltage"`
	MPPTCurrent           []float64 `json:"mppt_current"`
	TotalDCPower          float64   `json:"total_dc_power"`
	PhaseAVoltage         float64   `json:"phase_a_voltage"`
	PhaseBVoltage         float64   `json:"phase_b_voltage"`
	PhaseCVoltage         float64   `json:"phase_c_voltage"`
	PhaseACurrent         float64   `json:"phase_a_current"`
	PhaseBCurrent         float64   `json:"phase_b_current"`
	PhaseCCurrent         float64   `json:"phase_c_current"`
	TotalActivePower      float64   `json:"total_active_power"`
	TotalReactivePower    float64   `json:"total_reactive_power"`
	TotalApparentPower    float64   `json:"total_apparent_power"`
	PowerFactor           float64   `json:"power_factor"`
	GridFrequency         float64   `json:"grid_frequency"`
	WorkState1            string    `json:"work_state_1"`
	WorkState1Code        int       `json:"work_state_1_code"`
	WorkState2            int       `json:"work_state_2"`
	InverterState1        int       `json:"inverter_state_1"`
	InverterState2        int       `json:"inverter_state_2"`
	InsulationResistance  int       `json:"insulation_resistance"`
	BusVoltage            float64   `json:"bus_voltage"`
	NegativeGroundVoltage float64   `json:"negative_ground_voltage"`
	PIDWorkState          int       `json:"pid_work_state"`
	PIDAlarmCode          int       `json:"pid_alarm_code"`
	CountryCode           int       `json:"country_code"`
	MeterTotalPower       float64   `json:"meter_total_power"`
	MeterPhaseAPower      float64   `json:"meter_phase_a_power"`
	MeterPhaseBPower      float64   `json:"meter_phase_b_power"`
	MeterPhaseCPower      float64   `json:"meter_phase_c_power"`
	LoadPower             float64   `json:"load_power"`
	DailyFeedEnergy       float64   `json:"daily_feed_energy"`
	TotalFeedEnergy       float64   `json:"total_feed_energy"`
	DailyGridImport       float64   `json:"daily_grid_import"`
	TotalGridImport       float64   `json:"total_grid_import"`
	StringCurrents        []float64 `json:"string_currents"`
	ActivePowerSetting    float64   `json:"active_power_setting"`
	ReactivePowerSetting  float64   `json:"reactive_power_setting"`
	PowerFactorSetting    float64   `json:"power_factor_setting"`
	ESP32Timestamp        int       `json:"esp32_timestamp"`
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
	DeviceSN  string    `json:"device_sn"`
	DataDate  time.Time `json:"data_date"`
	Data      string    `json:"data"` // JSONB - 日聚合数据，字段通过 device_model_fields 表动态配置
	CreatedAt time.Time `json:"created_at"`
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
	ID              int64     `json:"id"`
	UserID          int64     `json:"user_id"`
	PushEnabled     bool      `json:"push_enabled"`
	AlarmPush       bool      `json:"alarm_push"`
	OfflinePush     bool      `json:"offline_push"`
	SystemPush      bool      `json:"system_push"`
	QuietHoursStart string    `json:"quiet_hours_start"`
	QuietHoursEnd   string    `json:"quiet_hours_end"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
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
	ID                  int64   `json:"id"`
	ModelCode           string  `json:"model_code"`
	ModelName           string  `json:"model_name"`
	Manufacturer        string  `json:"manufacturer"`
	Category            string  `json:"category"`
	RatedPowerKw        float64 `json:"rated_power_kw"`
	Description         string  `json:"description"`
	IsActive            bool    `json:"is_active"`
	LifecycleStatus     string  `json:"lifecycle_status"`
	HeartbeatProtocolID *int64  `json:"heartbeat_protocol_id"`
	LockVersion         int     `json:"lock_version"`
	DeviceCount         int     `json:"device_count"`
	CreatedAt           string  `json:"created_at"`
	UpdatedAt           string  `json:"updated_at"`
}

type DeviceModelField struct {
	ID            int64                  `json:"id"`
	ModelID       int32                  `json:"model_id"`
	FieldKey      string                 `json:"field_key"`
	FieldName     string                 `json:"field_name"`
	FieldType     string                 `json:"field_type"`
	Unit          string                 `json:"unit"`
	Sort          int                    `json:"sort"`
	IsShow        bool                   `json:"is_show"`
	IsControl     bool                   `json:"is_control"`
	ParseRule     *string                `json:"parse_rule"`
	GroupName     string                 `json:"group_name"`
	ControlParams map[string]interface{} `json:"control_params,omitempty"`
}

type DeviceModelProtocol struct {
	ID           int64                  `json:"id"`
	ModelID      int32                  `json:"model_id"`
	TopicPattern string                 `json:"topic_pattern"`
	ParseType    string                 `json:"parse_type"`
	ParseConfig  map[string]interface{} `json:"parse_config,omitempty"`
	IsActive     bool                   `json:"is_active"`
	CreatedAt    string                 `json:"created_at"`
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
	ID          int64     `json:"id"`
	Model       string    `json:"model"`
	Version     string    `json:"version"`
	FileURL     string    `json:"file_url"`
	FileSize    int64     `json:"file_size"`
	FileMD5     string    `json:"file_md5"`
	FileSHA256  string    `json:"file_sha256"`
	Changelog   string    `json:"changelog"`
	IsForce     bool      `json:"is_force"`
	UploadedBy  int64     `json:"uploaded_by"`
	Status      int       `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	TargetChip  string    `json:"target_chip"`
	MainVersion string    `json:"main_version"`
}

type DeviceUpgrade struct {
	ID               int64      `json:"id"`
	DeviceSN         string     `json:"device_sn"`
	FirmwareID       int64      `json:"firmware_id"`
	FirmwareVersion  string     `json:"firmware_version"`
	TargetChip       string     `json:"target_chip"`
	OldVersion       string     `json:"old_version"`
	Status           string     `json:"status"` // pending/downloading/upgrading/success/failed/cancelled
	Progress         int        `json:"progress"`
	ErrorMessage     string     `json:"error_message"`
	RetryCount       int        `json:"retry_count"`
	PushedBy         *int64     `json:"pushed_by"`
	Source           string     `json:"source"` // admin/app/local
	StartedAt        *time.Time `json:"started_at"`
	CompletedAt      *time.Time `json:"completed_at"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
	UpgradePackageID *int64     `json:"upgrade_package_id,omitempty"`
	TaskID           *int64     `json:"task_id,omitempty"`

	// 聚合查询用, 非数据库字段
	DeviceModel  string `json:"device_model,omitempty"`
	TotalDevices int    `json:"total_devices,omitempty"`
	SuccessCount int    `json:"success_count,omitempty"`
	FailedCount  int    `json:"failed_count,omitempty"`
	PendingCount int    `json:"pending_count,omitempty"`

	// 设备当前芯片版本（详情查询用）
	CurrentArmVersion string `json:"current_arm_version,omitempty"`
	CurrentEspVersion string `json:"current_esp_version,omitempty"`
	CurrentDspVersion string `json:"current_dsp_version,omitempty"`
	CurrentBmsVersion string `json:"current_bms_version,omitempty"`

	// 升级包相关
	PackageMainVersion string `json:"package_main_version,omitempty"`
}

// UpgradeTask 升级任务 - 统一管理所有升级操作
type UpgradeTask struct {
	ID             int64      `json:"id"`
	Name           string     `json:"name"`
	TaskType       string     `json:"task_type"` // 'single' | 'package'
	FirmwareID     *int64     `json:"firmware_id"`
	PackageID      *int64     `json:"package_id"`
	Model          string     `json:"model"`
	TargetVersion  string     `json:"target_version"`
	Status         string     `json:"status"`       // draft/pending/scheduled/running/completed/partial_success/failed/cancelled
	ExecuteMode    string     `json:"execute_mode"` // 'immediate' | 'scheduled' | 'manual'
	ScheduledAt    *time.Time `json:"scheduled_at"`
	RolloutPercent int        `json:"rollout_percent"`
	TotalDevices   int        `json:"total_devices"`
	SuccessCount   int        `json:"success_count"`
	FailedCount    int        `json:"failed_count"`
	CreatedBy      *int64     `json:"created_by"`
	Source         string     `json:"source"` // admin/app/local
	TriggeredBy    *int64     `json:"triggered_by"`
	Notes          string     `json:"notes"`
	CreatedAt      time.Time  `json:"created_at"`
	ExecutedAt     *time.Time `json:"executed_at"`
	CompletedAt    *time.Time `json:"completed_at"`
	UpdatedAt      time.Time  `json:"updated_at"`

	// 关联信息（非数据库字段，查询时填充）
	FirmwareVersion    string               `json:"firmware_version,omitempty"`
	FirmwareTargetChip string               `json:"firmware_target_chip,omitempty"`
	PackageMainVersion string               `json:"package_main_version,omitempty"`
	PackageItems       []UpgradePackageItem `json:"package_items,omitempty"`
}

// UpgradePackage 升级包 - 包含多个芯片固件的组合版本
type UpgradePackage struct {
	ID             int64                `json:"id"`
	Model          string               `json:"model"`
	MainVersion    string               `json:"main_version"`
	Changelog      string               `json:"changelog"`
	UserVersion    string               `json:"user_version"`    // 面向 App 用户的版本号
	UserChangelog  string               `json:"user_changelog"`  // 面向 App 用户的更新说明
	RolloutType    string               `json:"rollout_type"`    // all/model/user/device
	RolloutTargets string               `json:"rollout_targets"` // 逗号分隔的 model/user_id/sn
	IsPublished    bool                 `json:"is_published"`
	IsForce        bool                 `json:"is_force"`
	Status         int                  `json:"status"`
	CreatedBy      int64                `json:"created_by"`
	CreatedAt      time.Time            `json:"created_at"`
	UpdatedAt      time.Time            `json:"updated_at"`
	Items          []UpgradePackageItem `json:"items,omitempty"`
}

// UpgradePackageItem 升级包明细
type UpgradePackageItem struct {
	ID              int64  `json:"id"`
	PackageID       int64  `json:"package_id"`
	FirmwareID      int64  `json:"firmware_id"`
	TargetChip      string `json:"target_chip"`
	FirmwareVersion string `json:"firmware_version"`
	FileURL         string `json:"file_url,omitempty"`
	FileSize        int64  `json:"file_size,omitempty"`
	FileMD5         string `json:"file_md5,omitempty"`
	FileSHA256      string `json:"file_sha256,omitempty"`
}

type ParallelConfig struct {
	ID                          int64     `json:"id"`
	GroupName                   string    `json:"group_name"`
	PhaseConfig                 string    `json:"phase_config"`
	MasterSN                    string    `json:"master_sn"`
	SlaveSNs                    string    `json:"slave_sns"`
	CirculatingCurrentThreshold float64   `json:"circulating_current_threshold"`
	LoadBalanceDeviation        float64   `json:"load_balance_deviation"`
	CreatedBy                   int64     `json:"created_by"`
	Status                      int       `json:"status"`
	CreatedAt                   time.Time `json:"created_at"`
	UpdatedAt                   time.Time `json:"updated_at"`
}

type ParallelStatus struct {
	ID                 int64     `json:"id"`
	ParallelID         int64     `json:"parallel_id"`
	DeviceSN           string    `json:"device_sn"`
	Role               string    `json:"role"`
	SyncStatus         string    `json:"sync_status"`
	OutputPower        float64   `json:"output_power"`
	CirculatingCurrent float64   `json:"circulating_current"`
	DataTime           time.Time `json:"data_time"`
}

type SystemConfig struct {
	ID          int64     `json:"id"`
	ConfigKey   string    `json:"config_key"`
	ConfigValue string    `json:"config_value"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type AppVersion struct {
	ID                  int64      `json:"id"`
	Platform            string     `json:"platform"`
	VersionCode         int        `json:"version_code"`
	VersionName         string     `json:"version_name"`
	DownloadURL         string     `json:"download_url"`
	FileSize            int64      `json:"file_size"`
	FileMD5             string     `json:"file_md5"`
	Changelog           string     `json:"changelog"`
	IsForce             bool       `json:"is_force"`
	MinSupportedVersion int        `json:"min_supported_version"`
	RolloutPercentage   int        `json:"rollout_percentage"`
	IsRolledBack        bool       `json:"is_rolled_back"`
	RolledBackAt        *time.Time `json:"rolled_back_at"`
	Status              int        `json:"status"`
	CreatedBy           int64      `json:"created_by"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
}
