package routes

import (
	"log"
	"net/http"
	"time"

	"api-gateway/internal/middleware"
	"api-gateway/internal/proxy"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Config struct {
	APIServer      string
	DeviceServer   string
	JWTSecret      string
	GlobalRate     float64
	GlobalBurst    int
	RouteLimits    []middleware.RouteRateLimitConfig
	RBAC           *middleware.RBACMiddleware
	AllowedOrigins []string
}

func Setup(cfg Config) *gin.Engine {
	r := gin.New()
	r.RedirectTrailingSlash = false

	apiProxy := proxy.NewReverseProxy(cfg.APIServer)
	deviceProxy := proxy.NewReverseProxy(cfg.DeviceServer)

	r.Use(middleware.TrailingSlashHandler())
	r.Use(gin.Recovery())
	r.Use(middleware.CORS(cfg.AllowedOrigins))
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.RequestLogger())
	r.Use(middleware.Prometheus())
	r.Use(middleware.RateLimit(cfg.GlobalRate, cfg.GlobalBurst))

	if len(cfg.RouteLimits) > 0 {
		r.Use(middleware.RouteRateLimits(cfg.RouteLimits))
	}

	r.Use(middleware.JWTAuth(cfg.JWTSecret))

	if cfg.RBAC != nil {
		r.Use(cfg.RBAC.RBACGuard())
	}

	registerGatewayEndpoints(r)
	registerAPIRoutes(r, apiProxy)
	registerDeviceRoutes(r, deviceProxy)
	registerFallback(r)

	return r
}

func registerGatewayEndpoints(r *gin.Engine) {
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "api-gateway",
			"time":    time.Now().Format(time.RFC3339),
		})
	})

	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	r.GET("/api/docs", func(c *gin.Context) {
		c.JSON(http.StatusOK, buildAPIDoc())
	})
}

func registerAPIRoutes(r *gin.Engine, p *proxy.ReverseProxy) {
	r.Any("/api/v1/auth/*action", p.Handler())
	r.GET("/api/v1/timezones", p.Handler())
	r.Any("/api/v1/stations/*action", p.Handler())
	r.Any("/api/v1/stations", p.Handler())
	r.Any("/api/v1/devices/*action", p.Handler())
	r.Any("/api/v1/devices", p.Handler())
	r.Any("/api/v1/alarms/*action", p.Handler())
	r.Any("/api/v1/alarms", p.Handler())
	r.Any("/api/v1/alerts/*action", p.RewriteHandler("/api/v1/alarms"))
	r.Any("/api/v1/alerts", p.RewriteHandler("/api/v1/alarms"))
	r.Any("/api/v1/notifications/*action", p.Handler())
	r.Any("/api/v1/notifications", p.Handler())
	r.Any("/api/v1/alert-rules/*action", p.Handler())
	r.Any("/api/v1/alert-rules", p.Handler())
	r.Any("/api/v1/models/*action", p.Handler())
	r.Any("/api/v1/models", p.Handler())
	r.Any("/api/v1/users/*action", p.Handler())
	r.Any("/api/v1/users", p.Handler())
	r.Any("/api/v1/dashboard/*action", p.Handler())
	r.Any("/api/v1/dashboard", p.Handler())
	r.Any("/api/v1/ota/*action", p.Handler())
	r.Any("/api/v1/firmwares/*action", p.RewriteHandler("/api/v1/ota/firmware"))
	r.Any("/api/v1/firmwares", p.RewriteHandler("/api/v1/ota/firmware"))
	r.Any("/api/v1/work-orders/*action", p.Handler())
	r.Any("/api/v1/work-orders", p.Handler())
	r.Any("/api/v1/parallel-groups/*action", p.RewriteHandler("/api/v1/parallel"))
	r.Any("/api/v1/parallel-groups", p.RewriteHandler("/api/v1/parallel"))
	r.Any("/api/v1/admin/*action", p.Handler())
	r.Any("/api/v1/parallel/*action", p.Handler())
	r.Any("/api/v1/internal/*action", p.Handler())
	r.Any("/ws/*action", p.Handler())
	r.Any("/uploads/*action", p.Handler())
	r.Any("/firmware/*action", p.Handler())
}

func registerDeviceRoutes(r *gin.Engine, p *proxy.ReverseProxy) {
	r.Any("/api/v1/device/*action", p.Handler())
	r.Any("/api/v1/stats/*action", p.Handler())
}

func registerFallback(r *gin.Engine) {
	r.NoRoute(func(c *gin.Context) {
		log.Printf("[DEBUG-INSTRUMENT] NoRoute: %s %s (headers: Authorization=%v, X-User-ID=%v)",
			c.Request.Method, c.Request.URL.Path,
			c.GetHeader("Authorization") != "",
			c.GetHeader("X-User-ID"))
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
	Backend     string `json:"backend"`
}

func buildAPIDoc() APIDoc {
	return APIDoc{
		Title:       "INV-MQTT API Gateway",
		Version:     "2.0.0",
		Description: "光伏逆变器监控系统 API 网关 — 统一入口，RBAC 权限控制，业务接口统一转发至 api-server",
		BaseURL:     "/api/v1",
		Endpoints: []Endpoint{
			{Path: "/health", Method: "GET", Description: "健康检查", Auth: false, Backend: "gateway"},
			{Path: "/metrics", Method: "GET", Description: "Prometheus 指标", Auth: false, Backend: "gateway"},
			{Path: "/api/docs", Method: "GET", Description: "API 文档", Auth: false, Backend: "gateway"},

			{Path: "/api/v1/auth/login", Method: "POST", Description: "用户登录", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/register", Method: "POST", Description: "用户注册", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/send-code", Method: "POST", Description: "发送验证码", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/reset-password", Method: "POST", Description: "重置密码", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/email-register", Method: "POST", Description: "邮箱注册", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/email-login", Method: "POST", Description: "邮箱登录", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/send-email-code", Method: "POST", Description: "发送邮箱验证码", Auth: false, Backend: "api-server"},
			{Path: "/api/v1/auth/logout", Method: "POST", Description: "用户登出", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/auth/change-password", Method: "POST", Description: "修改密码", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/auth/profile", Method: "GET", Description: "获取用户资料", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/auth/profile", Method: "PUT", Description: "更新用户资料", Auth: true, Backend: "api-server"},

			{Path: "/api/v1/stations", Method: "GET", Description: "获取电站列表", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/stations", Method: "POST", Description: "创建电站", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/stations/:id", Method: "GET", Description: "获取电站详情", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/stations/:id", Method: "PUT", Description: "更新电站", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/stations/:id", Method: "DELETE", Description: "删除电站", Auth: true, Backend: "api-server"},

			{Path: "/api/v1/devices", Method: "GET", Description: "获取设备列表", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/devices/:sn", Method: "GET", Description: "获取设备详情", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/devices/bind", Method: "POST", Description: "绑定设备", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/devices/:sn/control", Method: "POST", Description: "设备控制", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/device/:sn/online", Method: "GET", Description: "查询设备在线状态", Auth: true, Backend: "device-server"},
			{Path: "/api/v1/device/:sn/data", Method: "GET", Description: "查询设备实时缓存数据", Auth: true, Backend: "device-server"},

			{Path: "/api/v1/models", Method: "GET", Description: "获取型号列表", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/models/:id", Method: "GET", Description: "获取型号详情", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/models/:id/fields", Method: "GET", Description: "获取型号字段定义", Auth: true, Backend: "api-server"},

			{Path: "/api/v1/alarms", Method: "GET", Description: "获取告警列表", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/alarms/:id", Method: "GET", Description: "获取告警详情", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/alarms/:id/handle", Method: "PUT", Description: "处理告警", Auth: true, Backend: "api-server"},

			{Path: "/api/v1/admin/*", Method: "ALL", Description: "管理后台接口", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/users/*", Method: "ALL", Description: "用户管理接口", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/ota/*", Method: "ALL", Description: "OTA 升级管理", Auth: true, Backend: "api-server"},
			{Path: "/api/v1/parallel/*", Method: "ALL", Description: "并机配置管理", Auth: true, Backend: "api-server"},
			{Path: "/uploads/*", Method: "GET", Description: "静态文件上传目录", Auth: false, Backend: "api-server"},
		},
	}
}
