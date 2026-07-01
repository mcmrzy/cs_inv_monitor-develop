// Package main is the entry point for mqtt-kafka-bridge, the EMQX-to-Kafka message forwarder.
//
// Responsibilities:
//   - Receive MQTT messages via EMQX webhook (POST /webhook)
//   - Extract device SN and message type from MQTT topic
//   - Forward messages to appropriate Kafka topics (telemetry or alarm)
//   - Expose stats endpoint for monitoring
//
// Dependencies: Kafka
// Listens on: :8080 (configurable)
// Endpoints: POST /webhook, GET /health, GET /stats
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/segmentio/kafka-go"
	"gopkg.in/yaml.v3"
)

type Config struct {
	Server struct {
		Port    int    `yaml:"port"`
		Workers int    `yaml:"workers"`
		Timeout int    `yaml:"timeout"`
	} `yaml:"server"`
	Kafka struct {
		Brokers        []string `yaml:"brokers"`
		TelemetryTopic string   `yaml:"telemetry_topic"`
		AlarmTopic     string   `yaml:"alarm_topic"`
		BatchSize      int      `yaml:"batch_size"`
		BatchTimeout   int      `yaml:"batch_timeout"`
	} `yaml:"kafka"`
	EMQX struct {
		Token string `yaml:"token"`
	} `yaml:"emqx"`
}

// Validate 校验关键配置项
func (c *Config) Validate() error {
	var missing []string
	if len(c.Kafka.Brokers) == 0 {
		missing = append(missing, "kafka.brokers (at least one broker required)")
	}
	if c.Kafka.TelemetryTopic == "" {
		missing = append(missing, "kafka.telemetry_topic")
	}
	if c.Kafka.AlarmTopic == "" {
		missing = append(missing, "kafka.alarm_topic")
	}
	if c.Server.Port <= 0 || c.Server.Port > 65535 {
		missing = append(missing, "server.port (must be 1-65535)")
	}
	if len(missing) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s", joinStrs(missing, "\n  - "))
	}
	return nil
}

func joinStrs(ss []string, sep string) string {
	r := ""
	for i, s := range ss {
		if i > 0 {
			r += sep
		}
		r += s
	}
	return r
}

type stats struct {
	mu            sync.Mutex
	messagesIn    int64
	messagesOut   int64
	errors        int64
	lastMessageAt time.Time
}

func (s *stats) incIn() {
	s.mu.Lock()
	s.messagesIn++
	s.lastMessageAt = time.Now()
	s.mu.Unlock()
}

func (s *stats) incOut(n int) {
	s.mu.Lock()
	s.messagesOut += int64(n)
	s.mu.Unlock()
}

func (s *stats) incErr() {
	s.mu.Lock()
	s.errors++
	s.mu.Unlock()
}

type KafkaBridge struct {
	telemetryWriter *kafka.Writer
	alarmWriter     *kafka.Writer
	stats           stats
	cfg             *Config
}

func NewKafkaBridge(cfg *Config) *KafkaBridge {
	return &KafkaBridge{
		cfg: cfg,
		telemetryWriter: &kafka.Writer{
			Addr:         kafka.TCP(cfg.Kafka.Brokers...),
			Topic:        cfg.Kafka.TelemetryTopic,
			BatchSize:    cfg.Kafka.BatchSize,
			BatchTimeout: time.Duration(cfg.Kafka.BatchTimeout) * time.Millisecond,
			Async:        true,
		},
		alarmWriter: &kafka.Writer{
			Addr:         kafka.TCP(cfg.Kafka.Brokers...),
			Topic:        cfg.Kafka.AlarmTopic,
			BatchSize:    cfg.Kafka.BatchSize,
			BatchTimeout: time.Duration(cfg.Kafka.BatchTimeout) * time.Millisecond,
			Async:        true,
		},
	}
}

type EMQXWebhookMessage struct {
	ClientID  string `json:"clientid"`
	Username  string `json:"username"`
	Topic     string `json:"topic"`
	Payload   string `json:"payload"`
	QoS       int    `json:"qos"`
	Timestamp int64  `json:"ts"`
}

func (b *KafkaBridge) handleWebhook(w http.ResponseWriter, r *http.Request) {
	if b.cfg.EMQX.Token != "" {
		token := r.Header.Get("Authorization")
		if token != "Bearer "+b.cfg.EMQX.Token && token != b.cfg.EMQX.Token {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
	}

	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var msg EMQXWebhookMessage
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		b.stats.incErr()
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	sn := extractSN(msg.Topic)
	msgType := extractMsgType(msg.Topic)

	var payloadObj interface{}
	if msg.Payload != "" {
		if err := json.Unmarshal([]byte(msg.Payload), &payloadObj); err != nil {
			payloadObj = msg.Payload
		}
	}

	rawMsg := map[string]interface{}{
		"sn":          sn,
		"client_id":   msg.ClientID,
		"msg_type":    msgType,
		"mqtt_topic":  msg.Topic,
		"qos":         msg.QoS,
		"payload":     payloadObj,
		"received_at": time.Now().UTC().Format(time.RFC3339),
	}

	body, err := json.Marshal(rawMsg)
	if err != nil {
		b.stats.incErr()
		log.Printf("Marshal error: %v", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	kafkaTopic := b.cfg.Kafka.TelemetryTopic
	if msgType == "alarm" || msgType == "data/alarm" {
		kafkaTopic = b.cfg.Kafka.AlarmTopic
	}

	writer := b.telemetryWriter
	if kafkaTopic == b.cfg.Kafka.AlarmTopic {
		writer = b.alarmWriter
	}

	kafkaMsg := kafka.Message{
		Key:   []byte(sn),
		Value: body,
	}

	if err := writer.WriteMessages(context.Background(), kafkaMsg); err != nil {
		b.stats.incErr()
		log.Printf("Kafka write error: %v", err)
		http.Error(w, "kafka error", http.StatusBadGateway)
		return
	}

	b.stats.incIn()
	w.WriteHeader(http.StatusNoContent)
}

func extractSN(topic string) string {
	parts := stringsSplit(topic, "/")
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}

func extractMsgType(topic string) string {
	parts := stringsSplit(topic, "/")
	if len(parts) >= 3 {
		return stringsJoin(parts[2:], "/")
	}
	return "unknown"
}

func stringsSplit(s, sep string) []string {
	result := []string{}
	start := 0
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			result = append(result, s[start:i])
			start = i + len(sep)
			i += len(sep) - 1
		}
	}
	result = append(result, s[start:])
	return result
}

func stringsJoin(parts []string, sep string) string {
	if len(parts) == 0 {
		return ""
	}
	result := parts[0]
	for i := 1; i < len(parts); i++ {
		result += sep + parts[i]
	}
	return result
}

func main() {
	configFile := "config.yaml"
	if len(os.Args) > 1 {
		configFile = os.Args[1]
	}

	cfg, err := loadConfig(configFile)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
	if err := cfg.Validate(); err != nil {
		log.Fatalf("Config validation failed: %v", err)
	}

	log.Printf("Starting MQTT-Kafka Bridge (Webhook mode)")
	log.Printf("  Listen: :%d", cfg.Server.Port)
	log.Printf("  Kafka: %v", cfg.Kafka.Brokers)
	log.Printf("  Topics: %s, %s", cfg.Kafka.TelemetryTopic, cfg.Kafka.AlarmTopic)

	bridge := NewKafkaBridge(cfg)

	mux := http.NewServeMux()
	mux.HandleFunc("/webhook", bridge.handleWebhook)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		bridge.stats.mu.Lock()
		data := map[string]interface{}{
			"messages_in":    bridge.stats.messagesIn,
			"messages_out":   bridge.stats.messagesOut,
			"errors":         bridge.stats.errors,
			"last_message_at": bridge.stats.lastMessageAt.Format(time.RFC3339),
		}
		bridge.stats.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(data)
	})

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      mux,
		ReadTimeout:  time.Duration(cfg.Server.Timeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.Timeout) * time.Second,
	}

	go func() {
		log.Printf("HTTP server listening on :%d", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	go printStats(&bridge.stats)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
	bridge.telemetryWriter.Close()
	bridge.alarmWriter.Close()
	log.Println("Bridge stopped")
}

func printStats(st *stats) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		st.mu.Lock()
		log.Printf("Stats: in=%d, out=%d, errors=%d, last_msg=%s",
			st.messagesIn, st.messagesOut, st.errors,
			st.lastMessageAt.Format("15:04:05"))
		st.mu.Unlock()
	}
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
	}
	if cfg.Server.Workers == 0 {
		cfg.Server.Workers = 4
	}
	if cfg.Server.Timeout == 0 {
		cfg.Server.Timeout = 30
	}
	if cfg.Kafka.BatchSize == 0 {
		cfg.Kafka.BatchSize = 100
	}
	if cfg.Kafka.BatchTimeout == 0 {
		cfg.Kafka.BatchTimeout = 100
	}

	return &cfg, nil
}
