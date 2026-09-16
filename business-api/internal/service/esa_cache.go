package service

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"

	openapi "github.com/alibabacloud-go/darabonba-openapi/v2/client"
	"github.com/alibabacloud-go/tea/dara"
	"github.com/alibabacloud-go/tea/tea"
	"go.uber.org/zap"

	"inv-api-server/pkg/logger"
)

// CachePurger 在 App 发布等关键写入后刷新边缘缓存，并在启动时对齐 ESA 缓存规则。
type CachePurger interface {
	Enabled() bool
	RefreshAsync()
	EnsureCacheRulesAsync()
}

// NoopCachePurger 未配置 ESA 时的占位实现。
type NoopCachePurger struct{}

func (NoopCachePurger) Enabled() bool             { return false }
func (NoopCachePurger) RefreshAsync()             {}
func (NoopCachePurger) EnsureCacheRulesAsync()    {}

const (
	esaAPIEndpoint = "esa.aliyuncs.com"
	esaAPIVersion  = "2024-09-10"
)

// defaultAppReleaseCachePaths 下载页读取最新版本的公开路径。
// 页面实际请求带 ?platform=android，因此刷新时用 ignoreParams 覆盖任意 query。
var defaultAppReleaseCachePaths = []string{
	"/app-release-info",
	"/api/v1/ota/app/latest",
}

// ESACachePurger 调用阿里云 ESA OpenAPI 刷新指定 URL 的边缘缓存。
//
// 下载页依赖 /app-release-info 与 /api/v1/ota/app/latest 的实时元数据；
// ESA 在未遵循源站 no-store 时会对这些路径按默认 TTL 缓存，发布新 APK 后必须主动刷新。
//
// 注意：ESA 2024-09-10 的刷新接口是 PurgeCaches（不是旧 CDN 的 RefreshESAObjectCaches）。
type ESACachePurger struct {
	client      *openapi.Client
	ak          string
	sk          string
	siteID      string
	refreshURLs []string
	endpoint    string
}

// NewESACachePurger 创建 ESA 刷新器。host 为空时使用 download.jiuxiaoyw.online。
func NewESACachePurger(accessKeyID, accessKeySecret, siteID, host string) *ESACachePurger {
	h := strings.TrimSpace(host)
	h = strings.TrimPrefix(strings.TrimPrefix(h, "https://"), "http://")
	if i := strings.Index(h, "/"); i >= 0 {
		h = h[:i]
	}
	if h == "" {
		h = "download.jiuxiaoyw.online"
	}
	urls := make([]string, 0, len(defaultAppReleaseCachePaths)*2)
	for _, p := range defaultAppReleaseCachePaths {
		// 页面请求带 query；同时提交裸路径与带 platform 的变体，避免 cache key 漏刷。
		urls = append(urls,
			"https://"+h+p,
			"https://"+h+p+"?platform=android",
		)
	}
	return &ESACachePurger{
		ak:          strings.TrimSpace(accessKeyID),
		sk:          strings.TrimSpace(accessKeySecret),
		siteID:      strings.TrimSpace(siteID),
		refreshURLs: urls,
		endpoint:    esaAPIEndpoint,
	}
}

// NewESACachePurgerFromConfig 按配置构造：缺任一关键项则返回 Noop，发布流程无感。
func NewESACachePurgerFromConfig(ak, sk, siteID, appDownloadURL string) CachePurger {
	ak, sk, siteID = strings.TrimSpace(ak), strings.TrimSpace(sk), strings.TrimSpace(siteID)
	if ak == "" || sk == "" || siteID == "" {
		return NoopCachePurger{}
	}
	return NewESACachePurger(ak, sk, siteID, appDownloadURL)
}

func (p *ESACachePurger) Enabled() bool {
	return p != nil && p.siteID != "" && p.ak != "" && p.sk != ""
}

// RefreshPaths 返回将要刷新的完整 URL 列表。
func (p *ESACachePurger) RefreshPaths() []string {
	out := make([]string, len(p.refreshURLs))
	copy(out, p.refreshURLs)
	return out
}

// Refresh 同步刷新边缘缓存。未启用时直接返回 nil。
//
// 使用 PurgeCaches 的 ignoreParams 类型：去掉 query 后匹配，确保
// /app-release-info?platform=android 与裸路径一并失效。
func (p *ESACachePurger) Refresh() error {
	if !p.Enabled() {
		return nil
	}
	if err := p.ensureClient(); err != nil {
		return err
	}

	// ignoreParams 列表使用「去参数」后的 URL。
	ignore := make([]string, 0, len(defaultAppReleaseCachePaths))
	host := p.extractHost()
	for _, path := range defaultAppReleaseCachePaths {
		ignore = append(ignore, "https://"+host+path)
	}
	content, err := json.Marshal(map[string]interface{}{
		"IgnoreParams": ignore,
	})
	if err != nil {
		return fmt.Errorf("marshal purge content: %w", err)
	}

	result, err := p.callESA("PurgeCaches", map[string]*string{
		"Type":    tea.String("ignoreParams"),
		"Content": tea.String(string(content)),
		"SiteId":  tea.String(p.siteID),
		"Force":   tea.String("true"),
	})
	if err != nil {
		return err
	}
	taskID := ""
	if result != nil {
		if v, ok := result["TaskId"]; ok && v != nil {
			taskID = fmt.Sprint(v)
		}
	}
	logger.Info("ESA cache refresh submitted",
		zap.String("site_id", p.siteID),
		zap.Strings("urls", p.refreshURLs),
		zap.Strings("ignore_params", ignore),
		zap.String("task_id", taskID),
	)
	return nil
}

// RefreshAsync 异步刷新，不阻塞发布请求；失败只记日志。
func (p *ESACachePurger) RefreshAsync() {
	if !p.Enabled() {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				logger.Error("ESA cache refresh panic", zap.Any("panic", r))
			}
		}()
		if err := p.Refresh(); err != nil {
			logger.Error("ESA cache refresh failed",
				zap.String("site_id", p.siteID),
				zap.Error(err),
			)
		}
	}()
}

func (p *ESACachePurger) extractHost() string {
	h := strings.TrimSpace(p.refreshURLs[0])
	h = strings.TrimPrefix(strings.TrimPrefix(h, "https://"), "http://")
	if i := strings.Index(h, "/"); i >= 0 {
		h = h[:i]
	}
	if h == "" {
		return "download.jiuxiaoyw.online"
	}
	return h
}

// ListSites 查询账号下 ESA 站点（运维排查用）。
func (p *ESACachePurger) ListSites() (map[string]interface{}, error) {
	if err := p.ensureClient(); err != nil {
		return nil, err
	}
	return p.callESA("ListSites", map[string]*string{
		"PageSize": tea.String("50"),
	})
}

func (p *ESACachePurger) callESA(action string, query map[string]*string) (map[string]interface{}, error) {
	if err := p.ensureClient(); err != nil {
		return nil, err
	}
	params := &openapi.Params{
		Action:      tea.String(action),
		Version:     tea.String(esaAPIVersion),
		Protocol:    tea.String("HTTPS"),
		Method:      tea.String("POST"),
		AuthType:    tea.String("AK"),
		Style:       tea.String("RPC"),
		Pathname:    tea.String("/"),
		ReqBodyType: tea.String("form"),
		BodyType:    tea.String("json"),
	}
	return p.client.CallApi(params, &openapi.OpenApiRequest{Query: query}, &dara.RuntimeOptions{})
}

func (p *ESACachePurger) ensureClient() error {
	if p.client != nil {
		return nil
	}
	if p.ak == "" || p.sk == "" {
		return fmt.Errorf("esa access key not configured")
	}
	endpoint := p.endpoint
	protocol := "HTTPS"
	if strings.HasPrefix(endpoint, "http://") || strings.HasPrefix(endpoint, "https://") {
		u, err := url.Parse(endpoint)
		if err != nil {
			return fmt.Errorf("invalid esa endpoint %q: %w", endpoint, err)
		}
		protocol = strings.ToUpper(u.Scheme)
		endpoint = u.Host + strings.TrimSuffix(u.Path, "/")
	}
	client, err := openapi.NewClient(&openapi.Config{
		AccessKeyId:     tea.String(p.ak),
		AccessKeySecret: tea.String(p.sk),
		Endpoint:        tea.String(endpoint),
		Protocol:        tea.String(protocol),
		ReadTimeout:     tea.Int(20000),
		ConnectTimeout:  tea.Int(5000),
	})
	if err != nil {
		return fmt.Errorf("create esa openapi client: %w", err)
	}
	p.client = client
	return nil
}

// esaCacheRuleSpec 期望的 ESA 缓存规则（下载域 + API 域元数据路径）。
type esaCacheRuleSpec struct {
	Name             string
	Rule             string // ESA 规则表达式
	EdgeCacheMode    string // no_cache | follow_origin | override_origin | follow_origin_bypass | follow_origin_override
	BrowserCacheMode string // no_cache | follow_origin | override_origin
}

// desiredESACacheRules 与 deploy/CACHE_POLICY.md 对齐：
// 动态接口与最新版本元数据禁止边缘缓存，SPA 入口 follow_origin。
//
// 注意：ESA EdgeCacheMode 枚举是 no_cache（不是旧 CDN 的 off）。
func desiredESACacheRules() []esaCacheRuleSpec {
	return []esaCacheRuleSpec{
		{
			Name:             "cs-api-no-store",
			Rule:             `starts_with(http.request.uri.path, "/api/")`,
			EdgeCacheMode:    "no_cache",
			BrowserCacheMode: "no_cache",
		},
		{
			Name:             "cs-app-release-info-no-store",
			Rule:             `eq(http.request.uri.path, "/app-release-info")`,
			EdgeCacheMode:    "no_cache",
			BrowserCacheMode: "no_cache",
		},
		{
			Name:             "cs-spa-follow-origin",
			Rule:             `eq(http.request.uri.path, "/download") or eq(http.request.uri.path, "/")`,
			EdgeCacheMode:    "follow_origin_bypass",
			BrowserCacheMode: "follow_origin",
		},
	}
}

// EnsureCacheRules 对齐 ESA 缓存规则：不存在则创建，已存在同名规则则更新。
// 用于根治「源站 no-store 仍被边缘按默认 TTL 缓存」。
func (p *ESACachePurger) EnsureCacheRules() error {
	if !p.Enabled() {
		return nil
	}
	existing, err := p.listCacheRulesByName()
	if err != nil {
		return err
	}
	for _, spec := range desiredESACacheRules() {
		if id, ok := existing[spec.Name]; ok && id != "" {
			if err := p.updateCacheRule(id, spec); err != nil {
				return err
			}
			continue
		}
		if err := p.createCacheRule(spec); err != nil {
			return err
		}
	}
	logger.Info("ESA cache rules ensured",
		zap.String("site_id", p.siteID),
		zap.Int("rules", len(desiredESACacheRules())),
	)
	return nil
}

// EnsureCacheRulesAsync 启动时后台对齐缓存规则，不阻塞服务就绪。
func (p *ESACachePurger) EnsureCacheRulesAsync() {
	if !p.Enabled() {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				logger.Error("ESA ensure cache rules panic", zap.Any("panic", r))
			}
		}()
		if err := p.EnsureCacheRules(); err != nil {
			logger.Error("ESA ensure cache rules failed",
				zap.String("site_id", p.siteID),
				zap.Error(err),
			)
		}
	}()
}

func (p *ESACachePurger) listCacheRulesByName() (map[string]string, error) {
	result, err := p.callESA("ListCacheRules", map[string]*string{
		"SiteId":   tea.String(p.siteID),
		"PageSize": tea.String("100"),
	})
	if err != nil {
		return nil, fmt.Errorf("ListCacheRules: %w", err)
	}
	out := map[string]string{}
	if result == nil {
		return out, nil
	}
	list, _ := result["CacheRules"].([]interface{})
	for _, raw := range list {
		m, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		name, _ := m["RuleName"].(string)
		id := firstNonEmpty(m["Id"], m["ConfigId"], m["ConfigID"])
		if name != "" && id != "" {
			out[name] = id
		}
	}
	return out, nil
}

func (p *ESACachePurger) createCacheRule(spec esaCacheRuleSpec) error {
	query := map[string]*string{
		"SiteId":           tea.String(p.siteID),
		"RuleName":         tea.String(spec.Name),
		"RuleEnable":       tea.String("on"),
		"Rule":             tea.String(spec.Rule),
		"EdgeCacheMode":    tea.String(spec.EdgeCacheMode),
		"BrowserCacheMode": tea.String(spec.BrowserCacheMode),
	}
	if _, err := p.callESA("CreateCacheRule", query); err != nil {
		return fmt.Errorf("CreateCacheRule %s: %w", spec.Name, err)
	}
	logger.Info("ESA cache rule created",
		zap.String("site_id", p.siteID),
		zap.String("name", spec.Name),
		zap.String("edge_mode", spec.EdgeCacheMode),
	)
	return nil
}

func (p *ESACachePurger) updateCacheRule(id string, spec esaCacheRuleSpec) error {
	query := map[string]*string{
		"SiteId":           tea.String(p.siteID),
		"ConfigId":         tea.String(id),
		"RuleName":         tea.String(spec.Name),
		"RuleEnable":       tea.String("on"),
		"Rule":             tea.String(spec.Rule),
		"EdgeCacheMode":    tea.String(spec.EdgeCacheMode),
		"BrowserCacheMode": tea.String(spec.BrowserCacheMode),
	}
	if _, err := p.callESA("UpdateCacheRule", query); err != nil {
		return fmt.Errorf("UpdateCacheRule %s: %w", spec.Name, err)
	}
	logger.Info("ESA cache rule updated",
		zap.String("site_id", p.siteID),
		zap.String("name", spec.Name),
		zap.String("config_id", id),
		zap.String("edge_mode", spec.EdgeCacheMode),
	)
	return nil
}

func firstNonEmpty(vals ...interface{}) string {
	for _, v := range vals {
		if v == nil {
			continue
		}
		s := strings.TrimSpace(fmt.Sprint(v))
		if s != "" && s != "<nil>" {
			return s
		}
	}
	return ""
}
