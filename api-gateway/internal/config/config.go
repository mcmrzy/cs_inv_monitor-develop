package config

import (
	"fmt"
	"net"
	"net/url"
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
	SSLMode  string `yaml:"ssl_mode"`
}

type ServerConfig struct {
	Port           int      `yaml:"port"`
	Mode           string   `yaml:"mode"`
	TrustedProxies []string `yaml:"trusted_proxies"`
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

	expanded := os.ExpandEnv(string(data))

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
	cfg.Database.SSLMode = "disable"
	cfg.CORS.AllowedOrigins = []string{"http://localhost:3000", "http://localhost:5173"}

	if err := yaml.Unmarshal([]byte(expanded), cfg); err != nil {
		return nil, fmt.Errorf("解析配置文件失败: %w", err)
	}
	return cfg, nil
}

func (c *Config) RedisAddr() string {
	return fmt.Sprintf("%s:%d", c.Redis.Host, c.Redis.Port)
}

func (c *Config) DatabaseDSN() string {
	sslMode := c.Database.SSLMode
	if sslMode == "" {
		sslMode = "disable"
	}
	u := &url.URL{Scheme: "postgres", User: url.UserPassword(c.Database.User, c.Database.Password), Host: net.JoinHostPort(c.Database.Host, fmt.Sprintf("%d", c.Database.Port)), Path: c.Database.Name}
	query := u.Query()
	query.Set("sslmode", sslMode)
	query.Set("timezone", "UTC")
	u.RawQuery = query.Encode()
	return u.String()
}

// Validate 校验关键配置项
func (c *Config) Validate() error {
	var missing []string
	if invalidRequiredSecret(c.JWT.Secret) {
		missing = append(missing, "jwt.secret (env: JWT_SECRET, must not be empty or a CHANGE_ME* placeholder)")
	} else if strings.EqualFold(c.Server.Mode, "release") && len(c.JWT.Secret) < 32 {
		missing = append(missing, "jwt.secret must be at least 32 characters in release mode")
	}
	if !validBackendURL(c.Backends.APIServer) {
		missing = append(missing, "backends.api_server (env: API_SERVER_URL)")
	}
	if !validBackendURL(c.Backends.DeviceServer) {
		missing = append(missing, "backends.device_server (env: DEVICE_SERVER_URL)")
	}
	if invalidRequiredSecret(c.Database.Password) {
		missing = append(missing, "database.password must not use a CHANGE_ME* placeholder")
	}
	if invalidRequiredSecret(c.Redis.Password) {
		missing = append(missing, "redis.password must not use a CHANGE_ME* placeholder")
	}
	if c.Server.Port < 1 || c.Server.Port > 65535 {
		missing = append(missing, "server.port must be between 1 and 65535")
	}
	if c.RateLimit.Rate <= 0 || c.RateLimit.Burst <= 0 {
		missing = append(missing, "rate_limit.rate and rate_limit.burst must be positive")
	}
	for _, trustedProxy := range c.Server.TrustedProxies {
		if !validIPOrCIDR(trustedProxy) {
			missing = append(missing, fmt.Sprintf("server.trusted_proxies contains invalid IP/CIDR %q", trustedProxy))
		}
	}
	if strings.EqualFold(c.Server.Mode, "release") {
		for _, origin := range c.CORS.AllowedOrigins {
			if strings.TrimSpace(origin) == "*" {
				missing = append(missing, "cors.allowed_origins must not contain '*' in release mode")
				break
			}
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s",
			strings.Join(missing, "\n  - "))
	}
	return nil
}

func validBackendURL(value string) bool {
	u, err := url.Parse(strings.TrimSpace(value))
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != "" && u.User == nil
}

func validIPOrCIDR(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" {
		return false
	}
	if net.ParseIP(value) != nil {
		return true
	}
	_, _, err := net.ParseCIDR(value)
	return err == nil
}

func invalidRequiredSecret(value string) bool {
	return strings.TrimSpace(value) == "" || isPlaceholder(value)
}

func isPlaceholder(value string) bool {
	return strings.HasPrefix(strings.ToUpper(strings.TrimSpace(value)), "CHANGE_ME")
}
