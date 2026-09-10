package service

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/config"

	"github.com/redis/go-redis/v9"
	"github.com/jackc/pgx/v5/pgxpool"
)

const configCacheKey = "system:config:all"
const configCacheTTL = 5 * time.Minute

// ConfigService 从 system_configs 表读取运行时配置，带 Redis 缓存
// 优先从数据库读取，回退到启动时的环境变量配置
type ConfigService struct {
	db       *pgxpool.Pool
	rdb      *redis.Client
	baseCfg  config.Config
}

func NewConfigService(db *pgxpool.Pool, rdb *redis.Client, baseCfg config.Config) *ConfigService {
	return &ConfigService{db: db, rdb: rdb, baseCfg: baseCfg}
}

// Invalidate 清除配置缓存（保存配置后调用）
func (s *ConfigService) Invalidate() {
	if s.rdb != nil {
		s.rdb.Del(context.Background(), configCacheKey)
	}
}

// getAll 从数据库读取所有配置（带缓存）
func (s *ConfigService) getAll(ctx context.Context) (map[string]string, error) {
	// 尝试从缓存读取
	if s.rdb != nil {
		cached, err := s.rdb.Get(ctx, configCacheKey).Result()
		if err == nil {
			var m map[string]string
			if json.Unmarshal([]byte(cached), &m) == nil {
				return m, nil
			}
		}
	}

	// 从数据库读取
	m := make(map[string]string)
	if s.db != nil {
		rows, err := s.db.Query(ctx, `SELECT config_key, config_value FROM system_configs`)
		if err != nil {
			return m, nil
		}
		defer rows.Close()
		for rows.Next() {
			var key, value string
			if rows.Scan(&key, &value) == nil {
				m[key] = value
			}
		}
	}

	// 写入缓存
	if s.rdb != nil {
		data, _ := json.Marshal(m)
		s.rdb.Set(ctx, configCacheKey, string(data), configCacheTTL)
	}

	return m, nil
}

// Get 获取单个配置值，优先数据库，回退默认值
func (s *ConfigService) Get(ctx context.Context, key string) string {
	all, _ := s.getAll(ctx)
	if v, ok := all[key]; ok && v != "" {
		return v
	}
	return ""
}

// GetWithDefault 获取配置值，带默认值
func (s *ConfigService) GetWithDefault(ctx context.Context, key, defaultVal string) string {
	v := s.Get(ctx, key)
	if v == "" {
		return defaultVal
	}
	return v
}

// GetInt 获取整数配置值
func (s *ConfigService) GetInt(ctx context.Context, key string, defaultVal int) int {
	v := s.Get(ctx, key)
	if v == "" {
		return defaultVal
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return defaultVal
	}
	return n
}

// GetBool 获取布尔配置值
func (s *ConfigService) GetBool(ctx context.Context, key string, defaultVal bool) bool {
	v := s.Get(ctx, key)
	if v == "" {
		return defaultVal
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return defaultVal
	}
	return b
}

// ---------- 邮件配置 ----------

// GetEmailConfig 获取邮件配置（优先数据库，回退环境变量）
func (s *ConfigService) GetEmailConfig(ctx context.Context) config.EmailConfig {
	all, _ := s.getAll(ctx)

	get := func(key, fallback string) string {
		if v, ok := all[key]; ok && v != "" {
			return v
		}
		return fallback
	}

	port, _ := strconv.Atoi(get("email_port", fmt.Sprintf("%d", s.baseCfg.Email.Port)))

	return config.EmailConfig{
		Host:     get("email_host", s.baseCfg.Email.Host),
		Port:     port,
		Username: get("email_username", s.baseCfg.Email.Username),
		Password: get("email_password", s.baseCfg.Email.Password),
		From:     get("email_from", s.baseCfg.Email.From),
		UseSSL:   s.GetBool(ctx, "email_use_ssl", s.baseCfg.Email.UseSSL),
	}
}

// GetMQTTConfig 获取 MQTT 配置
func (s *ConfigService) GetMQTTConfig(ctx context.Context) map[string]string {
	all, _ := s.getAll(ctx)

	get := func(key, fallback string) string {
		if v, ok := all[key]; ok && v != "" {
			return v
		}
		return fallback
	}

	return map[string]string{
		"broker":        get("mqtt_broker", ""),
		"port":          get("mqtt_port", "8883"),
		"client_id":     get("mqtt_client_id", ""),
		"username":      get("mqtt_username", ""),
		"password":      get("mqtt_password", ""),
		"tls_insecure":  get("mqtt_tls_insecure", "false"),
	}
}

// GetSMSConfig 获取短信配置
func (s *ConfigService) GetSMSConfig(ctx context.Context) map[string]string {
	all, _ := s.getAll(ctx)

	get := func(key, fallback string) string {
		if v, ok := all[key]; ok && v != "" {
			return v
		}
		return fallback
	}

	return map[string]string{
		"access_key": get("sms_access_key", ""),
		"secret_key": get("sms_secret_key", ""),
		"sign_name":  get("sms_sign_name", ""),
		"template":   get("sms_template", ""),
	}
}

// ---------- 域名配置 ----------

// DomainConfig 站点域名配置：多服务器部署时由后端统一下发，客户端与下载页不硬编码域名。
// 以 JSON 对象存于 system_configs（key=domains），由管理后台「域名配置」维护。
type DomainConfig struct {
	DownloadBaseURL string `json:"download_base_url"` // 资源下载域（固件/安装包等）
	FrontendBaseURL string `json:"frontend_base_url"` // Web 管理后台域（邀请链接等）
}

// normalizeBaseURL 校验并规范基地址：仅接受 http/https，拒绝 localhost、环回、
// 私有与保留地址主机；非法值返回空串，由调用方回退到环境变量默认值。
func normalizeBaseURL(v string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return ""
	}
	u, err := url.Parse(v)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return ""
	}
	host := strings.ToLower(strings.TrimSuffix(u.Hostname(), "."))
	if host == "localhost" || strings.HasSuffix(host, ".localhost") ||
		strings.HasSuffix(host, ".local") || strings.HasSuffix(host, ".internal") {
		return ""
	}
	if ip := net.ParseIP(host); ip != nil {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
			return ""
		}
	}
	return strings.TrimRight(v, "/")
}

// domainOverride 从数据库 domains 段读取字段，返回规范化后的值（未配置/非法返回空）
func (s *ConfigService) domainOverride(ctx context.Context, field string) string {
	raw := s.Get(ctx, "domains")
	if raw == "" {
		return ""
	}
	var d DomainConfig
	if err := json.Unmarshal([]byte(raw), &d); err != nil {
		return ""
	}
	switch field {
	case "download_base_url":
		return normalizeBaseURL(d.DownloadBaseURL)
	case "frontend_base_url":
		return normalizeBaseURL(d.FrontendBaseURL)
	}
	return ""
}

// ResolveDomainConfig 解析站点域名配置。
// 优先级：管理后台 domains 段 > 环境变量（DOWNLOAD_URL / FRONTEND_URL）> SERVER_URL 回退。
func (s *ConfigService) ResolveDomainConfig(ctx context.Context) DomainConfig {
	download := s.domainOverride(ctx, "download_base_url")
	if download == "" {
		download = normalizeBaseURL(s.baseCfg.Backends.DownloadURL)
	}
	if download == "" {
		download = normalizeBaseURL(s.baseCfg.Backends.ServerURL)
	}

	frontend := s.domainOverride(ctx, "frontend_base_url")
	if frontend == "" {
		frontend = normalizeBaseURL(s.baseCfg.Backends.FrontendURL)
	}
	if frontend == "" {
		frontend = normalizeBaseURL(s.baseCfg.Backends.ServerURL)
	}

	return DomainConfig{
		DownloadBaseURL: download,
		FrontendBaseURL: frontend,
	}
}
