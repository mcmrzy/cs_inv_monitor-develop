package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/segmentio/kafka-go"
)

// ---------------------------------------------------------------------------
// Config.Validate tests
// ---------------------------------------------------------------------------

func validConfig() *Config {
	cfg := &Config{}
	cfg.Server.Port = 8080
	cfg.Kafka.Brokers = []string{"localhost:9092"}
	cfg.Kafka.TelemetryTopic = "inv.telemetry"
	cfg.Kafka.AlarmTopic = "inv.alarm"
	return cfg
}

func TestConfigValidate_Valid(t *testing.T) {
	if err := validConfig().Validate(); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
}

func TestConfigValidate_MissingBrokers(t *testing.T) {
	cfg := validConfig()
	cfg.Kafka.Brokers = nil
	err := cfg.Validate()
	if err == nil || !strings.Contains(err.Error(), "kafka.brokers") {
		t.Fatalf("expected kafka.brokers error, got %v", err)
	}
}

func TestConfigValidate_MissingTopics(t *testing.T) {
	cfg := validConfig()
	cfg.Kafka.TelemetryTopic = ""
	err := cfg.Validate()
	if err == nil || !strings.Contains(err.Error(), "telemetry_topic") {
		t.Fatalf("expected telemetry_topic error, got %v", err)
	}

	cfg = validConfig()
	cfg.Kafka.AlarmTopic = ""
	err = cfg.Validate()
	if err == nil || !strings.Contains(err.Error(), "alarm_topic") {
		t.Fatalf("expected alarm_topic error, got %v", err)
	}
}

func TestConfigValidate_InvalidPort(t *testing.T) {
	cfg := validConfig()
	cfg.Server.Port = 0
	if err := cfg.Validate(); err == nil || !strings.Contains(err.Error(), "server.port") {
		t.Fatalf("expected server.port error for 0, got %v", err)
	}

	cfg = validConfig()
	cfg.Server.Port = 70000
	if err := cfg.Validate(); err == nil || !strings.Contains(err.Error(), "server.port") {
		t.Fatalf("expected server.port error for 70000, got %v", err)
	}
}

// ---------------------------------------------------------------------------
// loadConfig tests
// ---------------------------------------------------------------------------

func TestLoadConfig_MissingFile(t *testing.T) {
	if _, err := loadConfig(filepath.Join(t.TempDir(), "nope.yaml")); err == nil {
		t.Fatal("expected error for missing config file")
	}
}

func TestLoadConfig_ValidYAMLWithDefaults(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	content := `
server:
  port: 9090
kafka:
  brokers: ["k1:9092", "k2:9092"]
  telemetry_topic: "inv.telemetry"
  alarm_topic: "inv.alarm"
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := loadConfig(path)
	if err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if cfg.Server.Port != 9090 {
		t.Errorf("port = %d, want 9090", cfg.Server.Port)
	}
	if len(cfg.Kafka.Brokers) != 2 {
		t.Errorf("brokers = %v", cfg.Kafka.Brokers)
	}
	// Defaults applied for zero values
	if cfg.Server.Workers != 4 {
		t.Errorf("workers default = %d, want 4", cfg.Server.Workers)
	}
	if cfg.Server.Timeout != 30 {
		t.Errorf("timeout default = %d, want 30", cfg.Server.Timeout)
	}
	if cfg.Kafka.BatchSize != 100 {
		t.Errorf("batch_size default = %d, want 100", cfg.Kafka.BatchSize)
	}
	if cfg.Kafka.BatchTimeout != 100 {
		t.Errorf("batch_timeout default = %d, want 100", cfg.Kafka.BatchTimeout)
	}
}

func TestLoadConfig_DefaultPort(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	content := "kafka:\n  brokers: [\"k1:9092\"]\n  telemetry_topic: \"t\"\n  alarm_topic: \"a\"\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg, err := loadConfig(path)
	if err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if cfg.Server.Port != 8080 {
		t.Errorf("default port = %d, want 8080", cfg.Server.Port)
	}
}

func TestLoadConfig_InvalidYAML(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte("kafka: [unclosed"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadConfig(path); err == nil {
		t.Fatal("expected parse error for invalid yaml")
	}
}

// ---------------------------------------------------------------------------
// applyEnvOverrides tests
// ---------------------------------------------------------------------------

func TestApplyEnvOverrides(t *testing.T) {
	cfg := validConfig()
	cfg.EMQX.Token = "old-token"
	cfg.Server.Port = 8080
	cfg.Redis.Addr = "old-redis:6379"
	cfg.Redis.Password = "old-pass"

	t.Setenv("KAFKA_BROKERS", "new1:9092,new2:9092")
	t.Setenv("KAFKA_TELEMETRY_TOPIC", "new-telemetry")
	t.Setenv("KAFKA_ALARM_TOPIC", "new-alarm")
	t.Setenv("EMQX_TOKEN", "new-token")
	t.Setenv("EMQX_WEBHOOK_PORT", "9999")
	t.Setenv("REDIS_ADDR", "new-redis:6379")
	t.Setenv("REDIS_PASSWORD", "new-pass")

	applyEnvOverrides(cfg)

	if len(cfg.Kafka.Brokers) != 2 || cfg.Kafka.Brokers[0] != "new1:9092" {
		t.Errorf("brokers = %v", cfg.Kafka.Brokers)
	}
	if cfg.Kafka.TelemetryTopic != "new-telemetry" || cfg.Kafka.AlarmTopic != "new-alarm" {
		t.Errorf("topics = %s / %s", cfg.Kafka.TelemetryTopic, cfg.Kafka.AlarmTopic)
	}
	if cfg.EMQX.Token != "new-token" {
		t.Errorf("token = %s", cfg.EMQX.Token)
	}
	if cfg.Server.Port != 9999 {
		t.Errorf("port = %d, want 9999", cfg.Server.Port)
	}
	if cfg.Redis.Addr != "new-redis:6379" || cfg.Redis.Password != "new-pass" {
		t.Errorf("redis = %s / %s", cfg.Redis.Addr, cfg.Redis.Password)
	}
}

func TestApplyEnvOverrides_InvalidPortIgnored(t *testing.T) {
	cfg := validConfig()
	cfg.Server.Port = 8080
	t.Setenv("EMQX_WEBHOOK_PORT", "not-a-number")
	applyEnvOverrides(cfg)
	if cfg.Server.Port != 8080 {
		t.Errorf("invalid port env should be ignored, got %d", cfg.Server.Port)
	}
}

// ---------------------------------------------------------------------------
// Writer construction tests
// ---------------------------------------------------------------------------

func TestNewKafkaWriter_ConfigFields(t *testing.T) {
	cfg := validConfig()
	cfg.Kafka.BatchSize = 50
	cfg.Kafka.BatchTimeout = 200

	w := newKafkaWriter(cfg, cfg.Kafka.TelemetryTopic)
	defer w.Close()
	if w.Topic != "inv.telemetry" {
		t.Errorf("topic = %s", w.Topic)
	}
	if w.BatchSize != 50 {
		t.Errorf("batch size = %d, want 50", w.BatchSize)
	}
	if w.RequiredAcks != kafka.RequireAll {
		t.Error("expected RequireAll acks")
	}
}

func TestNewKafkaBridge_InitialState(t *testing.T) {
	bridge := NewKafkaBridge(validConfig())
	defer bridge.telemetryWriter.Close()
	defer bridge.alarmWriter.Close()

	if !bridge.probe.IsConnected() {
		t.Error("probe should start connected")
	}
	if bridge.probeCheckFunc == nil {
		t.Error("probeCheckFunc should be set")
	}
	if bridge.cfg.Kafka.TelemetryTopic != "inv.telemetry" {
		t.Errorf("telemetry topic = %s", bridge.cfg.Kafka.TelemetryTopic)
	}

	// Cancelled context must stop the probe loop promptly.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	bridge.runHealthProbe(ctx)
}
