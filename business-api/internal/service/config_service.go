package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
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
