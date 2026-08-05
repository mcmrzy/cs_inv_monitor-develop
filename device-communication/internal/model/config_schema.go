package model

// ==================== config v2 参数 schema（V2.1，CS-L10-6K2） ====================
// 对应表 device_config_schema（42 键），服务端校验 + SchemaGroupPanel 分组渲染共用。

// ConfigParamSchema device_config_schema 行结构（工程单位语义）。
type ConfigParamSchema struct {
	ParamKey         string         `json:"param_key"`
	GroupCode        string         `json:"group_code"`  // general / application / hybrid / parallel
	SubGroup         string         `json:"sub_group"`   // hybrid 内细分：charge/discharge/soc/equalize/gen
	ControlType      string         `json:"control_type"` // number / enum / boolean
	Scale            float64        `json:"scale"`
	Unit             string         `json:"unit"`
	Min              *float64       `json:"min"`
	Max              *float64       `json:"max"`
	EnumMap          map[string]any `json:"enum_map"`
	Step             *float64       `json:"step"`
	PermissionCode   string         `json:"permission_code"`
	ConfirmationMode string         `json:"confirmation_mode"`
	DisplayNameKey   string         `json:"display_name_key"`
	SortOrder        int            `json:"sort_order"`
	Visibility       map[string]any `json:"visibility"`
	Validation       map[string]any `json:"validation"`
}

// 枚举/互斥校验辅助（validation jsonb 结构，如 {"lte":"set_soc_back_utl"}）。
const (
	ValidationLTE = "lte" // 本参数 ≤ 指定参数
	ValidationGTE = "gte" // 本参数 ≥ 指定参数
)
