package model

// OTA 升级来源
const (
	OTASourceAdmin = "admin"
	OTASourceApp   = "app"
	OTASourceLocal = "local"
)

// 升级包发布范围
const (
	RolloutTypeAll     = "all"
	RolloutTypeModel   = "model"
	RolloutTypeUser    = "user"
	RolloutTypeDevice  = "device"
)

// 升级任务类型
const (
	TaskTypeSingle  = "single"
	TaskTypePackage = "package"
)

// 升级任务状态
const (
	TaskStatusDraft          = "draft"
	TaskStatusPending        = "pending"
	TaskStatusScheduled      = "scheduled"
	TaskStatusRunning        = "running"
	TaskStatusCompleted      = "completed"
	TaskStatusPartialSuccess = "partial_success"
	TaskStatusFailed         = "failed"
	TaskStatusCancelled      = "cancelled"
	TaskStatusSkipped        = "skipped"
	TaskStatusBlocked        = "blocked"
	TaskStatusTimeout        = "timeout"
)

// 固件发布生命周期
const (
	FirmwareReleaseDraft     = "draft"
	FirmwareReleasePublished = "published"
	FirmwareReleaseDisabled  = "disabled"
)

// 独立模块目标芯片顺序：ESP 最后（通讯模块最后升级，避免断连）
var FirmwareTargetOrder = []string{"bms", "arm", "dsp", "esp"}

// 旧升级包退役错误码
const (
	ErrCodeLegacyPackageRetired = "legacy_package_retired"
)

// 设备芯片当前版本字段名
const (
	TargetChipARM = "arm"
	TargetChipESP = "esp"
	TargetChipDSP = "dsp"
	TargetChipBMS = "bms"
)

// 升级执行模式
const (
	ExecuteModeImmediate = "immediate"
	ExecuteModeScheduled = "scheduled"
	ExecuteModeManual    = "manual"
)

// 设备升级状态
const (
	UpgradeStatusPending     = "pending"
	UpgradeStatusDownloading = "downloading"
	UpgradeStatusUpgrading   = "upgrading"
	UpgradeStatusSuccess     = "success"
	UpgradeStatusFailed      = "failed"
	UpgradeStatusCancelled   = "cancelled"
)
