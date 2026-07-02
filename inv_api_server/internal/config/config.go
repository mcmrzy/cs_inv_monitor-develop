package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/spf13/viper"
)

type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	Database DatabaseConfig `mapstructure:"database"`
	Redis    RedisConfig    `mapstructure:"redis"`
	JWT      JWTConfig      `mapstructure:"jwt"`
	SMS      SMSConfig      `mapstructure:"sms"`
	Email    EmailConfig    `mapstructure:"email"`
	CORS     CORSConfig     `mapstructure:"cors"`
	Log      LogConfig      `mapstructure:"log"`
	Timezone string         `mapstructure:"timezone"`
	Backends BackendsConfig `mapstructure:"backends"`
}

type CORSConfig struct {
	AllowedOrigins []string `mapstructure:"allowed_origins"`
}

type BackendsConfig struct {
	DeviceServer  string `mapstructure:"device_server"`
	InternalKey   string `mapstructure:"internal_key"`
	ServerURL     string `mapstructure:"server_url"`     // 外部访问地址，用于ESP32下载固件
	WeatherAPI    string `mapstructure:"weather_api"`    // 天气API地址
	AmapAPIKey    string `mapstructure:"amap_api_key"`   // 高德地图API Key
	WeatherSource string `mapstructure:"weather_source"` // 天气数据源: open-meteo 或 amap
}

type ServerConfig struct {
	Port         int           `mapstructure:"port"`
	ReadTimeout  time.Duration `mapstructure:"read_timeout"`
	WriteTimeout time.Duration `mapstructure:"write_timeout"`
	Mode         string        `mapstructure:"mode"`
}

type DatabaseConfig struct {
	Host            string        `mapstructure:"host"`
	Port            int           `mapstructure:"port"`
	User            string        `mapstructure:"user"`
	Password        string        `mapstructure:"password"`
	Database        string        `mapstructure:"database"`
	SSLMode         string        `mapstructure:"ssl_mode"`
	MaxOpenConns    int           `mapstructure:"max_open_conns"`
	MaxIdleConns    int           `mapstructure:"max_idle_conns"`
	ConnMaxLifetime time.Duration `mapstructure:"conn_max_lifetime"`
	ConnMaxIdleTime time.Duration `mapstructure:"conn_max_idle_time"`
}

type RedisConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Password string `mapstructure:"password"`
	DB       int    `mapstructure:"db"`
}

type JWTConfig struct {
	Secret            string        `mapstructure:"secret"`
	ExpireTime        time.Duration `mapstructure:"expire_time"`
	RefreshExpireTime time.Duration `mapstructure:"refresh_expire_time"`
	Issuer            string        `mapstructure:"issuer"`
}

type SMSConfig struct {
	Provider  string `mapstructure:"provider"`
	AccessKey string `mapstructure:"access_key"`
	SecretKey string `mapstructure:"secret_key"`
	SignName  string `mapstructure:"sign_name"`
	Template  string `mapstructure:"template"`
}

type EmailConfig struct {
	Host        string `mapstructure:"host"`
	Port        int    `mapstructure:"port"`
	Username    string `mapstructure:"username"`
	Password    string `mapstructure:"password"`
	From        string `mapstructure:"from"`
	UseSSL      bool   `mapstructure:"use_ssl"`
	TLSInsecure bool   `mapstructure:"tls_insecure"`
}

type LogConfig struct {
	Level      string `mapstructure:"level"`
	Filename   string `mapstructure:"filename"`
	MaxSize    int    `mapstructure:"max_size"`
	MaxBackups int    `mapstructure:"max_backups"`
	MaxAge     int    `mapstructure:"max_age"`
	Compress   bool   `mapstructure:"compress"`
}

func Load(configPath string) (*Config, error) {
	viper.SetConfigType("yaml")

	viper.SetDefault("timezone", "Asia/Shanghai")
	viper.SetDefault("backends.device_server", "http://inv-device-server:8081")
	viper.SetDefault("backends.weather_api", "http://api.open-meteo.com/v1/forecast")
	viper.SetDefault("backends.amap_api_key", "")
	viper.SetDefault("backends.weather_source", "open-meteo")
	
	viper.SetDefault("database.host", "postgres")
	viper.SetDefault("database.port", 5432)
	viper.SetDefault("database.user", "postgres")
	viper.SetDefault("database.password", "")
	viper.SetDefault("database.database", "inv_mqtt")
	viper.SetDefault("database.ssl_mode", "disable")
	viper.SetDefault("database.max_open_conns", 100)
	viper.SetDefault("database.max_idle_conns", 20)
	viper.SetDefault("database.conn_max_lifetime", 30*time.Minute)
	viper.SetDefault("database.conn_max_idle_time", 10*time.Minute)
	
	viper.SetDefault("redis.host", "redis")
	viper.SetDefault("redis.port", 6379)
	viper.SetDefault("redis.password", "")
	viper.SetDefault("redis.db", 0)
	
	viper.SetDefault("jwt.secret", "")
	viper.SetDefault("jwt.expire_time", 2*time.Hour)
	viper.SetDefault("jwt.refresh_expire_time", 7*24*time.Hour)
	viper.SetDefault("jwt.issuer", "inv-api-server")
	
	viper.SetDefault("sms.provider", "aliyun")
	viper.SetDefault("sms.access_key", "")
	viper.SetDefault("sms.secret_key", "")
	viper.SetDefault("sms.sign_name", "")
	viper.SetDefault("sms.template", "")
	
	viper.SetDefault("email.host", "smtp.qq.com")
	viper.SetDefault("email.port", 465)
	viper.SetDefault("email.username", "")
	viper.SetDefault("email.password", "")
	viper.SetDefault("email.from", "")
	viper.SetDefault("email.use_ssl", true)
	
	viper.SetDefault("log.level", "info")
	viper.SetDefault("log.filename", "logs/api-server.log")
	viper.SetDefault("log.max_size", 100)
	viper.SetDefault("log.max_backups", 10)
	viper.SetDefault("log.max_age", 30)
	viper.SetDefault("log.compress", true)
	
	viper.SetDefault("server.port", 8080)
	viper.SetDefault("server.read_timeout", 30*time.Second)
	viper.SetDefault("server.write_timeout", 0*time.Second) // SSE 长连接需要无写超时
	viper.SetDefault("server.mode", "release")

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("read config file: %w", err)
	}
	
	if err := viper.ReadConfig(strings.NewReader(string(data))); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	viper.BindEnv("database.host", "DB_HOST")
	viper.BindEnv("database.port", "DB_PORT")
	viper.BindEnv("database.user", "DB_USER")
	viper.BindEnv("database.password", "DB_PASSWORD")
	viper.BindEnv("database.database", "DB_NAME")
	
	viper.BindEnv("redis.host", "REDIS_HOST")
	viper.BindEnv("redis.port", "REDIS_PORT")
	viper.BindEnv("redis.password", "REDIS_PASSWORD")
	
	viper.BindEnv("jwt.secret", "JWT_SECRET")
	
	viper.BindEnv("sms.access_key", "SMS_ACCESS_KEY")
	viper.BindEnv("sms.secret_key", "SMS_SECRET_KEY")
	viper.BindEnv("sms.sign_name", "SMS_SIGN_NAME")
	viper.BindEnv("sms.template", "SMS_TEMPLATE")
	
	viper.BindEnv("email.host", "EMAIL_HOST")
	viper.BindEnv("email.port", "EMAIL_PORT")
	viper.BindEnv("email.username", "EMAIL_USER")
	viper.BindEnv("email.password", "EMAIL_PASS")
	viper.BindEnv("email.from", "EMAIL_FROM")
	
	viper.BindEnv("backends.device_server", "DEVICE_SERVER_URL")
	viper.BindEnv("backends.internal_key", "INTERNAL_KEY")
	viper.BindEnv("backends.server_url", "SERVER_URL")
	viper.BindEnv("backends.weather_api", "WEATHER_API_URL")
	viper.BindEnv("backends.amap_api_key", "AMAP_API_KEY")
	viper.BindEnv("backends.weather_source", "WEATHER_SOURCE")

	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, err
	}

	return &config, nil
}

// Validate 校验关键配置项，缺失时返回明确错误信息
func (c *Config) Validate() error {
	var missing []string
	if c.JWT.Secret == "" || c.JWT.Secret == "CHANGE_ME" {
		missing = append(missing, "jwt.secret (env: JWT_SECRET, must not be empty or 'CHANGE_ME')")
	}
	if c.Database.Password == "" {
		missing = append(missing, "database.password (env: DB_PASSWORD)")
	}
	if c.Database.Host == "" {
		missing = append(missing, "database.host (env: DB_HOST)")
	}
	if c.Server.Port <= 0 || c.Server.Port > 65535 {
		missing = append(missing, "server.port (must be 1-65535)")
	}
	if len(missing) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s\n\nHint: Set these via environment variables or config.yaml",
			strings.Join(missing, "\n  - "))
	}
	return nil
}
