package routes

import (
	"net/http"
	"time"

	"api-gateway/internal/middleware"
	"api-gateway/internal/proxy"

	"github.com/gin-gonic/gin"
)

type Config struct {
	APIServer      string
	DeviceServer   string
	JWTSecret      string
	JWTIssuer      string
	JWTAudience    string
	GlobalRate     float64
	GlobalBurst    int
	RouteLimits    []middleware.RouteRateLimitConfig
	RBAC           *middleware.RBACMiddleware
	AllowedOrigins []string
	TrustedProxies []string
}

func Setup(cfg Config) *gin.Engine {
	r := gin.New()
	r.RedirectTrailingSlash = false
	if err := r.SetTrustedProxies(cfg.TrustedProxies); err != nil {
		panic("invalid trusted proxy configuration: " + err.Error())
	}

	apiProxy := proxy.NewReverseProxy(cfg.APIServer)
	deviceProxy := proxy.NewReverseProxy(cfg.DeviceServer)

	r.Use(middleware.TrailingSlashHandler())
	// Strip identity assertions before public routing and proxying as well as
	// before the authenticated groups. No client-controlled X-User/X-Tenant
	// header may reach an internal service.
	r.Use(middleware.StripUntrustedIdentityHeaders())
	r.Use(gin.Recovery())
	r.Use(middleware.BodyLimit())
	r.Use(middleware.GzipMiddleware())
	r.Use(middleware.CORS(cfg.AllowedOrigins))
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.SanitizeIdentityHeaders())
	r.Use(middleware.RequestLogger())
	r.Use(middleware.RateLimit(cfg.GlobalRate, cfg.GlobalBurst))

	if len(cfg.RouteLimits) > 0 {
		r.Use(middleware.RouteRateLimits(cfg.RouteLimits))
	}

	// 公开组 — 无需认证
	publicGroup := r.Group("/")

	// 用户组 — 需登录（JWT + RBAC）
	userGroup := r.Group("/")
	userGroup.Use(jwtMiddleware(cfg))
	if cfg.RBAC != nil {
		userGroup.Use(cfg.RBAC.RBACGuard())
	}

	// 管理员组 — 需管理员角色（JWT + RBAC + RequireRole）
	adminGroup := r.Group("/")
	adminGroup.Use(jwtMiddleware(cfg))
	if cfg.RBAC != nil {
		adminGroup.Use(cfg.RBAC.RBACGuard())
	}
	adminGroup.Use(middleware.RequireRole(1)) // role <= 1 (super_admin + admin)

	registerGatewayEndpoints(r)
	registerAPIRoutes(publicGroup, userGroup, adminGroup, apiProxy)
	registerDeviceRoutes(userGroup, deviceProxy)
	registerFallback(r)

	return r
}

func jwtMiddleware(cfg Config) gin.HandlerFunc {
	issuer := cfg.JWTIssuer
	if issuer == "" {
		issuer = middleware.DefaultJWTIssuer
	}
	audience := cfg.JWTAudience
	if audience == "" {
		audience = middleware.DefaultAccessAudience
	}
	return middleware.JWTAuthWithConfig(middleware.JWTAuthConfig{
		Secret: cfg.JWTSecret, Issuer: issuer, Audience: audience,
	})
}

func registerGatewayEndpoints(r *gin.Engine) {
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "api-gateway",
			"time":    time.Now().UTC().Format(time.RFC3339),
		})
	})

	r.GET("/api/docs", func(c *gin.Context) {
		c.JSON(http.StatusOK, buildAPIDoc())
	})

	// Swagger UI endpoints for API documentation
	r.GET("/api/swagger", func(c *gin.Context) {
		c.Redirect(http.StatusMovedPermanently, "/api/swagger/index.html")
	})
	r.Static("/api/swagger", "./docs/swagger")
	r.GET("/api/openapi.yaml", func(c *gin.Context) {
		c.File("./docs/openapi.yaml")
	})
}

func registerAPIRoutes(publicGroup, userGroup, adminGroup *gin.RouterGroup, p *proxy.ReverseProxy) {
	// Public — 无需认证（仅公开的 auth 子端点）
	publicGroup.Any("/api/v1/auth/login", p.Handler())
	publicGroup.Any("/api/v1/auth/register", p.Handler())
	publicGroup.Any("/api/v1/auth/send-code", p.Handler())
	publicGroup.Any("/api/v1/auth/reset-password", p.Handler())
	publicGroup.Any("/api/v1/auth/email-register", p.Handler())
	publicGroup.Any("/api/v1/auth/email-login", p.Handler())
	publicGroup.Any("/api/v1/auth/send-email-code", p.Handler())
	publicGroup.Any("/api/v1/auth/email-reset-password", p.Handler())
	publicGroup.Any("/api/v1/auth/phone-code-login", p.Handler())
	publicGroup.Any("/api/v1/auth/email-code-login", p.Handler())
	publicGroup.POST("/api/v1/auth/refresh", p.Handler())
	publicGroup.POST("/api/v1/auth/context", p.Handler())
	publicGroup.GET("/api/v1/timezones", p.Handler())
	publicGroup.Any("/api/v1/captcha/*action", p.Handler())
	publicGroup.Any("/uploads/*action", p.Handler())
	publicGroup.Any("/firmware/*action", p.Handler())
	publicGroup.Any("/ws/*action", p.Handler())

	// User — 需登录（具体 auth 子端点，不用通配符以避免与 publicGroup 冲突）
	userGroup.Any("/api/v1/auth/logout", p.Handler())
	userGroup.Any("/api/v1/auth/change-password", p.Handler())
	userGroup.Any("/api/v1/auth/profile", p.Handler())

	userGroup.Any("/api/v1/stations/*action", p.Handler())
	userGroup.Any("/api/v1/stations", p.Handler())
	userGroup.Any("/api/v1/devices/*action", p.Handler())
	userGroup.Any("/api/v1/devices", p.Handler())
	userGroup.Any("/api/v1/alarms/*action", p.Handler())
	userGroup.Any("/api/v1/alarms", p.Handler())
	userGroup.Any("/api/v1/alerts/*action", p.RewriteHandler("/api/v1/alarms"))
	userGroup.Any("/api/v1/alerts", p.RewriteHandler("/api/v1/alarms"))
	userGroup.Any("/api/v1/notifications/*action", p.Handler())
	userGroup.Any("/api/v1/notifications", p.Handler())
	userGroup.Any("/api/v1/alert-rules/*action", p.Handler())
	userGroup.Any("/api/v1/alert-rules", p.Handler())
	userGroup.Any("/api/v1/models/*action", p.Handler())
	userGroup.Any("/api/v1/models", p.Handler())
	userGroup.Any("/api/v1/field-catalog", p.Handler())
	userGroup.Any("/api/v1/protocol-versions/*action", p.Handler())
	userGroup.Any("/api/v1/protocol-versions", p.Handler())
	userGroup.Any("/api/v1/dashboard/*action", p.Handler())
	userGroup.Any("/api/v1/dashboard", p.Handler())
	userGroup.Any("/api/v1/ota/*action", p.Handler())
	userGroup.Any("/api/v1/firmwares/*action", p.RewriteHandler("/api/v1/ota/firmware"))
	userGroup.Any("/api/v1/firmwares", p.RewriteHandler("/api/v1/ota/firmware"))
	userGroup.Any("/api/v1/work-orders/*action", p.Handler())
	userGroup.Any("/api/v1/work-orders", p.Handler())

	// Channel Platform — 渠道平台管理（组织、邀请、成员、设备认领转移）
	userGroup.Any("/api/v1/organizations/*action", p.Handler())
	userGroup.Any("/api/v1/organizations", p.Handler())
	userGroup.Any("/api/v1/invitations/*action", p.Handler())
	userGroup.Any("/api/v1/members/*action", p.Handler())
	publicGroup.Any("/api/v1/invite/accept", p.Handler())

	// Admin — 需管理员（route-groups 单独注册，其余通过 admin/*action 通配符代理）
	adminGroup.GET("/api/v1/admin/route-groups", func(c *gin.Context) {
		c.JSON(http.StatusOK, buildRouteGroups())
	})
	adminGroup.Any("/api/v1/users/*action", p.Handler())
	adminGroup.Any("/api/v1/users", p.Handler())
	adminGroup.Any("/api/v1/parallel/*action", p.Handler())
	adminGroup.Any("/api/v1/parallel-groups/*action", p.Handler())
	adminGroup.Any("/api/v1/parallel-groups", p.Handler())
	adminGroup.Any("/api/v1/parallel", p.Handler())
	adminGroup.Any("/api/v1/internal/*action", p.Handler())
	// Admin 子路由代理 — 逐条注册以避免与 route-groups 通配符冲突
	adminGroup.Any("/api/v1/admin/models", p.Handler())
	adminGroup.Any("/api/v1/admin/models/*action", p.Handler())
	adminGroup.Any("/api/v1/admin/users", p.Handler())
	adminGroup.Any("/api/v1/admin/users/*action", p.Handler())
	adminGroup.Any("/api/v1/admin/permissions", p.Handler())
	adminGroup.Any("/api/v1/admin/permissions/*action", p.Handler())
	adminGroup.Any("/api/v1/admin/logs", p.Handler())
	adminGroup.Any("/api/v1/admin/logs/*action", p.Handler())
	adminGroup.Any("/api/v1/admin/system-health", p.Handler())
	adminGroup.Any("/api/v1/admin/system-config", p.Handler())
	adminGroup.Any("/api/v1/admin/tenants", p.Handler())
	adminGroup.Any("/api/v1/admin/tenants/*action", p.Handler())
	adminGroup.Any("/api/v1/admin/metrics", p.Handler())
}

func registerDeviceRoutes(userGroup *gin.RouterGroup, p *proxy.ReverseProxy) {
	userGroup.Any("/api/v1/device/*action", p.Handler())
	userGroup.Any("/api/v1/stats/*action", p.Handler())
	// parallel 路由已在 registerAPIRoutes 的 adminGroup 中注册，避免 Gin 通配符冲突
}

func registerFallback(r *gin.Engine) {
	r.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{
			"code":    404,
			"message": "接口不存在",
			"path":    c.Request.URL.Path,
		})
	})
}

type APIDoc struct {
	Title       string     `json:"title"`
	Version     string     `json:"version"`
	Description string     `json:"description"`
	BaseURL     string     `json:"base_url"`
	Endpoints   []Endpoint `json:"endpoints"`
}

type Endpoint struct {
	Path        string `json:"path"`
	Method      string `json:"method"`
	Description string `json:"description"`
	Auth        bool   `json:"auth"`
	Role        string `json:"role"`
	Backend     string `json:"backend"`
}

func buildAPIDoc() APIDoc {
	return APIDoc{
		Title:       "INV-MQTT API Gateway",
		Version:     "2.0.0",
		Description: "光伏逆变器监控系统 API 网关 — 统一入口，角色组分级 + RBAC 权限控制，业务接口统一转发至 api-server",
		BaseURL:     "/api/v1",
		Endpoints: []Endpoint{
			{Path: "/api/v1/devices/:sn/alarm-events", Method: "GET", Description: "Device alarm event history", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/devices/:sn/parallel-state", Method: "GET", Description: "Device parallel state", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/devices/:sn/three-phase", Method: "GET", Description: "Device three-phase telemetry", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/health", Method: "GET", Description: "健康检查", Auth: false, Role: "public", Backend: "gateway"},
			{Path: "/api/docs", Method: "GET", Description: "API 文档", Auth: false, Role: "public", Backend: "gateway"},

			{Path: "/api/v1/auth/login", Method: "POST", Description: "用户登录", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/register", Method: "POST", Description: "用户注册", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/send-code", Method: "POST", Description: "发送验证码", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/reset-password", Method: "POST", Description: "重置密码", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/email-register", Method: "POST", Description: "邮箱注册", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/email-login", Method: "POST", Description: "邮箱登录", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/send-email-code", Method: "POST", Description: "发送邮箱验证码", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/email-reset-password", Method: "POST", Description: "邮箱重置密码", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/phone-code-login", Method: "POST", Description: "手机验证码登录", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/email-code-login", Method: "POST", Description: "邮箱验证码登录", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/refresh", Method: "POST", Description: "刷新令牌", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/context", Method: "POST", Description: "切换活动组织并签发访问令牌", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/logout", Method: "POST", Description: "用户登出", Auth: true, Role: "user", Backend: "api-server"},

			{Path: "/api/v1/captcha/generate", Method: "GET", Description: "生成验证码图片", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/captcha/verify", Method: "POST", Description: "验证滑块位置", Auth: false, Role: "public", Backend: "api-server"},
			{Path: "/api/v1/auth/change-password", Method: "POST", Description: "修改密码", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/auth/profile", Method: "GET", Description: "获取用户资料", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/auth/profile", Method: "PUT", Description: "更新用户资料", Auth: true, Role: "user", Backend: "api-server"},

			{Path: "/api/v1/stations", Method: "GET", Description: "获取电站列表", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/stations", Method: "POST", Description: "创建电站", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/stations/:id", Method: "GET", Description: "获取电站详情", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/stations/:id", Method: "PUT", Description: "更新电站", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/stations/:id", Method: "DELETE", Description: "删除电站", Auth: true, Role: "user", Backend: "api-server"},

			{Path: "/api/v1/devices", Method: "GET", Description: "获取设备列表", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/devices/:sn", Method: "GET", Description: "获取设备详情", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/devices/bind", Method: "POST", Description: "绑定设备", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/devices/:sn/control", Method: "POST", Description: "设备控制", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/device/:sn/online", Method: "GET", Description: "查询设备在线状态", Auth: true, Role: "user", Backend: "device-server"},
			{Path: "/api/v1/device/:sn/data", Method: "GET", Description: "查询设备实时缓存数据", Auth: true, Role: "user", Backend: "device-server"},

			{Path: "/api/v1/models", Method: "GET", Description: "获取型号列表", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/models/:id", Method: "GET", Description: "获取型号详情", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/models/:id/fields", Method: "GET", Description: "获取型号字段定义", Auth: true, Role: "user", Backend: "api-server"},

			{Path: "/api/v1/alarms", Method: "GET", Description: "获取告警列表", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/alarms/:id", Method: "GET", Description: "获取告警详情", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/alarms/:id/handle", Method: "PUT", Description: "处理告警", Auth: true, Role: "user", Backend: "api-server"},

			{Path: "/api/v1/admin/*", Method: "ALL", Description: "管理后台接口", Auth: true, Role: "admin", Backend: "api-server"},
			{Path: "/api/v1/users/*", Method: "ALL", Description: "用户管理接口", Auth: true, Role: "admin", Backend: "api-server"},
			{Path: "/api/v1/ota/*", Method: "ALL", Description: "OTA 升级管理", Auth: true, Role: "user", Backend: "api-server"},
			{Path: "/api/v1/parallel/*", Method: "ALL", Description: "并机配置管理", Auth: true, Role: "admin", Backend: "api-server"},
			{Path: "/uploads/*", Method: "GET", Description: "静态文件上传目录", Auth: false, Role: "public", Backend: "api-server"},
		},
	}
}

// RouteGroup 路由分组信息
type RouteGroup struct {
	Name        string      `json:"name"`
	Label       string      `json:"label"`
	Description string      `json:"description"`
	Routes      []RouteInfo `json:"routes"`
}

// RouteInfo 路由信息
type RouteInfo struct {
	Path        string `json:"path"`
	Method      string `json:"method"`
	Description string `json:"description"`
	Backend     string `json:"backend"`
}

func buildRouteGroups() map[string][]RouteGroup {
	return map[string][]RouteGroup{
		"groups": {
			{
				Name: "public", Label: "公开接口", Description: "无需认证",
				Routes: []RouteInfo{
					{Path: "/health", Method: "GET", Description: "健康检查", Backend: "gateway"},
					{Path: "/api/docs", Method: "GET", Description: "API 文档", Backend: "gateway"},
					{Path: "/api/v1/auth/login", Method: "ALL", Description: "登录", Backend: "api-server"},
					{Path: "/api/v1/auth/register", Method: "ALL", Description: "注册", Backend: "api-server"},
					{Path: "/api/v1/auth/send-code", Method: "ALL", Description: "发送验证码", Backend: "api-server"},
					{Path: "/api/v1/auth/reset-password", Method: "ALL", Description: "重置密码", Backend: "api-server"},
					{Path: "/api/v1/auth/email-register", Method: "ALL", Description: "邮箱注册", Backend: "api-server"},
					{Path: "/api/v1/auth/email-login", Method: "ALL", Description: "邮箱登录", Backend: "api-server"},
					{Path: "/api/v1/auth/send-email-code", Method: "ALL", Description: "发送邮箱验证码", Backend: "api-server"},
					{Path: "/api/v1/auth/email-reset-password", Method: "ALL", Description: "邮箱重置密码", Backend: "api-server"},
					{Path: "/api/v1/auth/phone-code-login", Method: "ALL", Description: "手机验证码登录", Backend: "api-server"},
					{Path: "/api/v1/auth/email-code-login", Method: "ALL", Description: "邮箱验证码登录", Backend: "api-server"},
					{Path: "/api/v1/auth/refresh", Method: "ALL", Description: "刷新令牌", Backend: "api-server"},
					{Path: "/api/v1/auth/context", Method: "POST", Description: "切换活动组织", Backend: "api-server"},
					{Path: "/api/v1/captcha/*", Method: "ALL", Description: "验证码", Backend: "api-server"},
					{Path: "/api/v1/timezones", Method: "GET", Description: "时区列表", Backend: "api-server"},
					{Path: "/uploads/*", Method: "ALL", Description: "上传文件目录", Backend: "api-server"},
					{Path: "/firmware/*", Method: "ALL", Description: "固件文件下载", Backend: "api-server"},
					{Path: "/ws/*", Method: "ALL", Description: "WebSocket", Backend: "api-server"},
				},
			},
			{
				Name: "user", Label: "用户接口", Description: "需登录（JWT + RBAC）",
				Routes: []RouteInfo{
					{Path: "/api/v1/auth/logout", Method: "ALL", Description: "用户登出", Backend: "api-server"},
					{Path: "/api/v1/auth/change-password", Method: "ALL", Description: "修改密码", Backend: "api-server"},
					{Path: "/api/v1/auth/profile", Method: "ALL", Description: "用户资料", Backend: "api-server"},
					{Path: "/api/v1/stations", Method: "ALL", Description: "电站管理", Backend: "api-server"},
					{Path: "/api/v1/devices", Method: "ALL", Description: "设备管理", Backend: "api-server"},
					{Path: "/api/v1/alarms", Method: "ALL", Description: "告警管理", Backend: "api-server"},
					{Path: "/api/v1/alerts", Method: "ALL", Description: "告警管理（别名，重写到 /api/v1/alarms）", Backend: "api-server"},
					{Path: "/api/v1/notifications", Method: "ALL", Description: "通知管理", Backend: "api-server"},
					{Path: "/api/v1/alert-rules", Method: "ALL", Description: "告警规则", Backend: "api-server"},
					{Path: "/api/v1/models", Method: "ALL", Description: "设备型号", Backend: "api-server"},
					{Path: "/api/v1/dashboard", Method: "ALL", Description: "仪表盘", Backend: "api-server"},
					{Path: "/api/v1/ota/*", Method: "ALL", Description: "OTA升级（含APP端）", Backend: "api-server"},
					{Path: "/api/v1/firmwares", Method: "ALL", Description: "固件管理（别名，重写到 /api/v1/ota/firmware）", Backend: "api-server"},
					{Path: "/api/v1/work-orders", Method: "ALL", Description: "工单管理", Backend: "api-server"},
					{Path: "/api/v1/parallel", Method: "ALL", Description: "并机配置", Backend: "device-server"},
					{Path: "/api/v1/parallel-groups", Method: "ALL", Description: "并机配置（别名）", Backend: "device-server"},
					{Path: "/api/v1/device/*", Method: "ALL", Description: "设备服务", Backend: "device-server"},
					{Path: "/api/v1/stats/*", Method: "ALL", Description: "统计数据", Backend: "device-server"},
				},
			},
			{
				Name: "admin", Label: "管理接口", Description: "需管理员角色（JWT + RBAC + RequireRole）",
				Routes: []RouteInfo{
					{Path: "/api/v1/admin/route-groups", Method: "GET", Description: "路由分组信息（网关本地）", Backend: "gateway"},
					{Path: "/api/v1/users", Method: "ALL", Description: "用户管理", Backend: "api-server"},
					{Path: "/api/v1/parallel", Method: "ALL", Description: "并机配置", Backend: "api-server"},
					{Path: "/api/v1/parallel-groups", Method: "ALL", Description: "并机配置（别名，重写到 /api/v1/parallel）", Backend: "api-server"},
					{Path: "/api/v1/internal/*", Method: "ALL", Description: "内部接口", Backend: "api-server"},
				},
			},
		},
	}
}
