package handler

import (
	"encoding/json"

	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// ConfigHandler 运行时配置只读端点（供 App 端动态拉取，如帮助中心）
type ConfigHandler struct {
	cfgSvc *service.ConfigService
}

func NewConfigHandler(cfgSvc *service.ConfigService) *ConfigHandler {
	return &ConfigHandler{cfgSvc: cfgSvc}
}

// FAQItem 帮助中心常见问题条目
type FAQItem struct {
	Q string `json:"q"`
	A string `json:"a"`
}

// HelpCenterConfig 帮助中心配置（文档 URL / 客服电话 / FAQ 列表）
// 整体以 JSON 字符串存于 system_configs 表（key=help_center），
// 由管理后台 PATCH /admin/system-config 维护；缺省返回内置默认值。
type HelpCenterConfig struct {
	Docs  map[string]string `json:"docs"`
	Phone string            `json:"phone"`
	FAQs  []FAQItem         `json:"faqs"`
}

func defaultHelpCenterConfig() HelpCenterConfig {
	return HelpCenterConfig{
		Docs: map[string]string{
			"device": "",
			"app":    "",
			"system": "",
		},
		Phone: "400-888-8888",
		FAQs: []FAQItem{
			{Q: "如何查看设备实时数据？", A: "进入「电站」页面选择对应电站，即可查看发电功率、日发电量等实时数据。"},
			{Q: "设备离线了怎么办？", A: "请检查设备电源与网络连接；若长时间离线，可通过 App 本地模式直连设备排查。"},
			{Q: "如何提交故障工单？", A: "在帮助中心「我的工单」中点击提交，填写标题与问题描述，可附上现场图片便于快速定位。"},
		},
	}
}

// GetHelpCenter 获取帮助中心配置（登录即可，公开只读）
func (h *ConfigHandler) GetHelpCenter(c *gin.Context) {
	defaultCfg := defaultHelpCenterConfig()
	defaultJSON, _ := json.Marshal(defaultCfg)
	raw := h.cfgSvc.GetWithDefault(c.Request.Context(), "help_center", string(defaultJSON))
	var cfg HelpCenterConfig
	if err := json.Unmarshal([]byte(raw), &cfg); err != nil {
		cfg = defaultCfg
	}
	// 部分字段缺失时补齐默认值，保证 App 端结构完整
	if cfg.Docs == nil {
		cfg.Docs = defaultCfg.Docs
	}
	if cfg.Phone == "" {
		cfg.Phone = defaultCfg.Phone
	}
	if cfg.FAQs == nil {
		cfg.FAQs = defaultCfg.FAQs
	}
	response.Success(c, cfg)
}
