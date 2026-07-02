package model

import "time"

// ==================== 设备型号注册表 ====================
type DeviceModel struct {
	ID            int32     `json:"id"`
	ModelCode     string    `json:"model_code"`
	ModelName     string    `json:"model_name"`
	Manufacturer  string    `json:"manufacturer"`
	Category      string    `json:"category"`
	RatedPowerKW  float64   `json:"rated_power_kw"`
	DataFields    string    `json:"data_fields"` // JSONB
	FieldMapping  string    `json:"field_mapping"` // JSONB
	MQTTTopics    string    `json:"mqtt_topics"` // JSONB
	Description   string    `json:"description"`
	IsActive      bool      `json:"is_active"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// ==================== 型号字段定义 ====================
type DeviceModelField struct {
	ID          int64     `json:"id"`
	ModelID     int32     `json:"model_id"`
	FieldKey    string    `json:"field_key"`
	FieldName   string    `json:"field_name"`
	FieldType   string    `json:"field_type"`
	Unit        string    `json:"unit"`
	Sort        int       `json:"sort"`
	IsShow      bool      `json:"is_show"`
	IsControl   bool      `json:"is_control"`
	ParseRule     string                 `json:"parse_rule"`
	GroupName     string                 `json:"group_name" db:"group_name"`
	ControlParams map[string]interface{} `json:"control_params,omitempty" db:"control_params"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// ==================== 型号协议配置 ====================
type DeviceModelProtocol struct {
	ID          int64     `json:"id"`
	ModelID     int32     `json:"model_id"`
	TopicPattern string  `json:"topic_pattern"`
	ParseType   string    `json:"parse_type"`
	ParseConfig string    `json:"parse_config"` // JSONB
	IsActive    bool      `json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
}

// ==================== 字段解析结果（统一结构） ====================
type ParsedField struct {
	Key    string      `json:"key"`
	Name   string      `json:"name"`
	Type   string      `json:"type"`
	Unit   string      `json:"unit"`
	Value  interface{} `json:"value"`
}

// ==================== 型号元数据缓存（运行时加载） ====================
type ModelMetadata struct {
	Model       *DeviceModel
	Fields      map[string]*DeviceModelField // field_key -> Field
	FieldOrder  []*DeviceModelField          // 排序后的字段列表
	Protocols   []*DeviceModelProtocol       // 协议配置
}

// ==================== RBAC 相关 ====================
type SysRole struct {
	ID          int64     `json:"id"`
	RoleCode    string    `json:"role_code"`
	RoleName    string    `json:"role_name"`
	RoleLevel   int       `json:"role_level"`
	Description string    `json:"description"`
	IsSystem    bool      `json:"is_system"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type SysPermission struct {
	ID          int64     `json:"id"`
	PermCode    string    `json:"perm_code"`
	Resource    string    `json:"resource"`
	Action      string    `json:"action"`
	PermName    string    `json:"perm_name"`
	Description string    `json:"description"`
}

type SysRolePermission struct {
	ID           int64     `json:"id"`
	RoleID       int64     `json:"role_id"`
	PermissionID int64     `json:"permission_id"`
}

type SysUserRole struct {
	ID      int64     `json:"id"`
	UserID  int64     `json:"user_id"`
	RoleID  int64     `json:"role_id"`
}

type UserDeviceRel struct {
	ID              int64     `json:"id"`
	UserID          int64     `json:"user_id"`
	DeviceID        int64     `json:"device_id"`
	PermissionLevel string    `json:"permission_level"` // view/control/manage
	CreatedAt       time.Time `json:"created_at"`
}

// ==================== 设备分组 ====================
type DeviceGroup struct {
	ID          int64     `json:"id"`
	GroupName   string    `json:"group_name"`
	ParentID    int64     `json:"parent_id"`
	GroupPath   string    `json:"group_path"`
	CreatedBy   int64     `json:"created_by"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// ==================== 用户设备权限视图 ====================
type UserDeviceAccess struct {
	UserID          int64  `json:"user_id"`
	UserRole        int    `json:"user_role"`
	DeviceID        int64  `json:"device_id"`
	DeviceSN        string `json:"device_sn"`
	Model           string `json:"model"`
	DeviceStatus    int    `json:"device_status"`
	PermissionLevel string `json:"permission_level"`
}
