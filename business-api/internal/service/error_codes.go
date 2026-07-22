package service

// 设备拒绝码常量 — 统一覆盖命令校验链中所有可预期的拒绝场景。
// 前端可根据 code 字段做精确提示和 i18n 映射。
const (
	ErrUnsupportedCommand            = "UNSUPPORTED_COMMAND"
	ErrUnsupportedInCurrentMode      = "UNSUPPORTED_IN_CURRENT_MODE"
	ErrDeviceOffline                 = "DEVICE_OFFLINE"
	ErrDeviceBusy                    = "DEVICE_BUSY"
	ErrRequiresStopped               = "REQUIRES_STOPPED"
	ErrActiveFault                   = "ACTIVE_FAULT"
	ErrBMSOffline                    = "BMS_OFFLINE"
	ErrBMSLimitExceeded              = "BMS_LIMIT_EXCEEDED"
	ErrBatteryProfileMismatch        = "BATTERY_PROFILE_MISMATCH"
	ErrTemperatureDerating           = "TEMPERATURE_DERATING"
	ErrInvalidRange                  = "INVALID_RANGE"
	ErrInvalidRelation               = "INVALID_RELATION"
	ErrConfigRevisionConflict        = "CONFIG_REVISION_CONFLICT"
	ErrTopologyConflict              = "TOPOLOGY_CONFLICT"
	ErrAuthorizationExpired           = "AUTHORIZATION_EXPIRED"
	ErrPhysicalConfirmationRequired  = "PHYSICAL_CONFIRMATION_REQUIRED"
)

// CommandError 带拒绝码的命令错误
type CommandError struct {
	Code       string
	Message    string
	StatusCode int // HTTP 状态码
}

func (e *CommandError) Error() string {
	return e.Code + ": " + e.Message
}

func NewCommandError(code, message string, statusCode int) *CommandError {
	return &CommandError{Code: code, Message: message, StatusCode: statusCode}
}
