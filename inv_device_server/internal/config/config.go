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
	MQTT     MQTTConfig     `mapstructure:"mqtt"`
	Kafka    KafkaConfig    `mapstructure:"kafka"`
	Backends BackendsConfig `mapstructure:"backends"`
	Log      LogConfig      `mapstructure:"log"`
	Timezone string         `mapstructure:"timezone"`
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

type MQTTConfig struct {
	Broker      string `mapstructure:"broker"`
	Port        int    `mapstructure:"port"`
	ClientID    string `mapstructure:"client_id"`
	Username    string `mapstructure:"username"`
	Password    string `mapstructure:"password"`
	QoS         byte   `mapstructure:"qos"`
	TLSInsecure bool   `mapstructure:"tls_insecure"`
}

type KafkaConfig struct {
	Brokers   []string `mapstructure:"brokers"`
	Enabled   bool     `mapstructure:"enabled"`
	TelemetryTopic string `mapstructure:"telemetry_topic"`
	AlarmTopic  string `mapstructure:"alarm_topic"`
	CommandTopic string `mapstructure:"command_topic"`
}

type BackendsConfig struct {
	APIServer   string `mapstructure:"api_server"`
	InternalKey string `mapstructure:"internal_key"`
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
	viper.SetDefault("backends.api_server", "http://inv-api-server:8080")
	
	viper.SetDefault("database.host", "postgres")
	viper.SetDefault("database.port", 5432)
	viper.SetDefault("database.user", "postgres")
	viper.SetDefault("database.password", "")
	viper.SetDefault("database.database", "inv_mqtt")
	viper.SetDefault("database.ssl_mode", "disable")
	viper.SetDefault("database.max_open_conns", 150)
	viper.SetDefault("database.max_idle_conns", 30)
	viper.SetDefault("database.conn_max_lifetime", 30*time.Minute)
	viper.SetDefault("database.conn_max_idle_time", 10*time.Minute)
	
	viper.SetDefault("redis.host", "redis")
	viper.SetDefault("redis.port", 6379)
	viper.SetDefault("redis.password", "")
	viper.SetDefault("redis.db", 0)
	
	viper.SetDefault("mqtt.broker", "")
	viper.SetDefault("mqtt.port", 1883)
	viper.SetDefault("mqtt.client_id", "CSKJ-INV-SERVER-DEVICE")
	viper.SetDefault("mqtt.username", "")
	viper.SetDefault("mqtt.password", "")
	viper.SetDefault("mqtt.qos", 1)
	viper.SetDefault("mqtt.tls_insecure", false)
	
	viper.SetDefault("kafka.enabled", true)
	viper.SetDefault("kafka.brokers", []string{"kafka:29092"})
	viper.SetDefault("kafka.telemetry_topic", "inv-telemetry")
	viper.SetDefault("kafka.alarm_topic", "inv-alerts")
	viper.SetDefault("kafka.command_topic", "inv-commands")

	viper.BindEnv("database.host", "DB_HOST")
	viper.BindEnv("database.port", "DB_PORT")
	viper.BindEnv("database.user", "DB_USER")
	viper.BindEnv("database.password", "DB_PASSWORD")
	viper.BindEnv("database.database", "DB_NAME")
	
	viper.BindEnv("redis.host", "REDIS_HOST")
	viper.BindEnv("redis.port", "REDIS_PORT")
	viper.BindEnv("redis.password", "REDIS_PASSWORD")
	
	viper.BindEnv("mqtt.broker", "MQTT_BROKER")
	viper.BindEnv("mqtt.port", "MQTT_PORT")
	viper.BindEnv("mqtt.client_id", "MQTT_CLIENT_ID")
	viper.BindEnv("mqtt.username", "MQTT_USERNAME")
	viper.BindEnv("mqtt.password", "MQTT_PASSWORD")
	viper.BindEnv("mqtt.tls_insecure", "MQTT_TLS_INSECURE")
	
	viper.BindEnv("kafka.brokers", "KAFKA_BROKER")
	viper.BindEnv("kafka.enabled", "KAFKA_ENABLED")
	viper.BindEnv("kafka.telemetry_topic", "KAFKA_TELEMETRY_TOPIC")
	viper.BindEnv("kafka.alarm_topic", "KAFKA_ALARM_TOPIC")
	viper.BindEnv("kafka.command_topic", "KAFKA_COMMAND_TOPIC")
	
	// 将单个 broker 字符串转换为数组
	if broker := viper.GetString("kafka.brokers"); broker != "" {
		viper.Set("kafka.brokers", []string{broker})
	}
	
	viper.BindEnv("backends.api_server", "API_SERVER_URL")
	viper.BindEnv("backends.internal_key", "INTERNAL_KEY")

	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("read config file: %w", err)
	}
	
	if err := viper.ReadConfig(strings.NewReader(string(data))); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, err
	}

	return &config, nil
}

// Validate 校验关键配置项
func (c *Config) Validate() error {
	var missing []string
	if isPlaceholder(c.Database.Password) {
		missing = append(missing, "database.password (env: DB_PASSWORD, must not be empty or start with 'CHANGE_ME')")
	}
	if c.Database.Host == "" {
		missing = append(missing, "database.host (env: DB_HOST)")
	}
	if c.Server.Port <= 0 || c.Server.Port > 65535 {
		missing = append(missing, "server.port (must be 1-65535)")
	}
	if !c.Kafka.Enabled && c.MQTT.Broker == "" {
		missing = append(missing, "mqtt.broker (env: MQTT_BROKER, required when kafka.enabled=false)")
	}
	if c.Kafka.Enabled && len(c.Kafka.Brokers) == 0 {
		missing = append(missing, "kafka.brokers (env: KAFKA_BROKER, required when kafka.enabled=true)")
	}
	if c.Backends.APIServer == "" {
		missing = append(missing, "backends.api_server (env: API_SERVER_URL)")
	}
	if isPlaceholder(c.Backends.InternalKey) {
		missing = append(missing, "backends.internal_key (env: INTERNAL_KEY, must not be empty or start with 'CHANGE_ME')")
	}
	if len(missing) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s\n\nHint: Set these via environment variables or config.yaml",
			strings.Join(missing, "\n  - "))
	}
	return nil
}

func isPlaceholder(value string) bool {
	value = strings.ToUpper(strings.TrimSpace(value))
	return value == "" || strings.HasPrefix(value, "CHANGE_ME")
}
