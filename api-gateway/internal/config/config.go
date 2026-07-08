package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server          ServerConfig     `yaml:"server"`
	JWT             JWTConfig        `yaml:"jwt"`
	RateLimit       RateLimitConfig  `yaml:"rate_limit"`
	RouteRateLimits []RouteRateLimit `yaml:"route_rate_limits"`
	Backends        BackendsConfig   `yaml:"backends"`
	Redis           RedisConfig      `yaml:"redis"`
	RBAC            RBACConfig       `yaml:"rbac"`
	Database        DatabaseConfig   `yaml:"database"`
	CORS            CORSConfig       `yaml:"cors"`
}

type DatabaseConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	User     string `yaml:"user"`
	Password string `yaml:"password"`
	Name     string `yaml:"name"`
}

type ServerConfig struct {
	Port int    `yaml:"port"`
	Mode string `yaml:"mode"`
}

type JWTConfig struct {
	Secret string `yaml:"secret"`
}

type RateLimitConfig struct {
	Rate  float64 `yaml:"rate"`
	Burst int     `yaml:"burst"`
}

type RouteRateLimit struct {
	PathPrefix string  `yaml:"path_prefix"`
	Rate       float64 `yaml:"rate"`
	Burst      int     `yaml:"burst"`
}

type BackendsConfig struct {
	APIServer    string `yaml:"api_server"`
	DeviceServer string `yaml:"device_server"`
}

type RedisConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Password string `yaml:"password"`
	DB       int    `yaml:"db"`
}

type RBACConfig struct {
	Enabled     bool `yaml:"enabled"`
	CacheTTLSec int  `yaml:"cache_ttl_sec"`
}

type CORSConfig struct {
	AllowedOrigins []string `yaml:"allowed_origins"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取配置文件失败: %w", err)
	}

	expanded := expandEnv(string(data))

	cfg := &Config{}
	cfg.Server.Port = 8080
	cfg.Server.Mode = "release"
	cfg.RateLimit.Rate = 100
	cfg.RateLimit.Burst = 200
	cfg.Backends.APIServer = "http://inv-api-server:8080"
	cfg.Backends.DeviceServer = "http://inv-device-server:8081"
	cfg.Redis.Host = "localhost"
	cfg.Redis.Port = 6379
	cfg.Redis.DB = 0
	cfg.RBAC.Enabled = true
	cfg.RBAC.CacheTTLSec = 300
	cfg.Database.Host = "localhost"
	cfg.Database.Port = 5432
	cfg.Database.User = "postgres"
	cfg.Database.Name = "inv_mqtt"
	cfg.CORS.AllowedOrigins = []string{"http://localhost:3000", "http://localhost:5173"}

	if err := yaml.Unmarshal([]byte(expanded), cfg); err != nil {
		return nil, fmt.Errorf("解析配置文件失败: %w", err)
	}
	return cfg, nil
}

// expandEnv 展开环境变量，支持 ${VAR:-default} 默认值语法。
// 标准库 os.ExpandEnv 不识别 :- 语法，因此使用 os.Expand + 自定义映射。
func expandEnv(s string) string {
	return os.Expand(s, func(key string) string {
		if i := strings.Index(key, ":-"); i >= 0 {
			if v, ok := os.LookupEnv(key[:i]); ok {
				return v
			}
			return key[i+2:]
		}
		return os.Getenv(key)
	})
}

func (c *Config) RedisAddr() string {
	return fmt.Sprintf("%s:%d", c.Redis.Host, c.Redis.Port)
}

func (c *Config) DatabaseDSN() string {
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=disable&timezone=UTC",
		c.Database.User, c.Database.Password, c.Database.Host, c.Database.Port, c.Database.Name)
}

// Validate 校验关键配置项
func (c *Config) Validate() error {
	var missing []string
	if c.JWT.Secret == "" || c.JWT.Secret == "CHANGE_ME" {
		missing = append(missing, "jwt.secret (env: JWT_SECRET)")
	}
	if c.Backends.APIServer == "" {
		missing = append(missing, "backends.api_server (env: API_SERVER_URL)")
	}
	if c.Backends.DeviceServer == "" {
		missing = append(missing, "backends.device_server (env: DEVICE_SERVER_URL)")
	}
	if len(missing) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s",
			strings.Join(missing, "\n  - "))
	}
	return nil
}
