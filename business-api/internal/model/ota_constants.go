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
