// Package main is the entry point for mqtt-kafka-bridge, the EMQX-to-Kafka message forwarder.
//
// Responsibilities:
//   - Receive MQTT messages via EMQX webhook (POST /webhook)
//   - Extract device SN and message type from MQTT topic
//   - Forward messages to appropriate Kafka topics (telemetry or alarm)
//   - Expose stats, health, and metrics endpoints for monitoring
//   - Probe Kafka connectivity and report health to Redis
//
// Dependencies: Kafka, Redis (optional)
// Listens on: :8080 (configurable)
// Endpoints: POST /webhook, GET /health, GET /stats, GET /metrics
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
	"gopkg.in/yaml.v3"
)

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

type Config struct {
	Server struct {
		Port    int `yaml:"port"`
		Workers int `yaml:"workers"`
		Timeout int `yaml:"timeout"`
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
	Redis struct {
		Addr     string `yaml:"addr"`
		Password string `yaml:"password"`
		DB       int    `yaml:"db"`
	} `yaml:"redis"`
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
	if c.EMQX.Token == "" {
		log.Printf("[WARN] EMQX token not configured, webhook authentication disabled")
	}

	if len(missing) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s", strings.Join(missing, "\n  - "))
	}
	return nil
}

// ---------------------------------------------------------------------------
// Stats (atomic counters)
// ---------------------------------------------------------------------------

type stats struct {
	messagesIn    atomic.Int64
	messagesOut   atomic.Int64
	errors        atomic.Int64
	lastMessageAt atomic.Value // stores time.Time
}

func (s *stats) incIn() {
	s.messagesIn.Add(1)
	s.lastMessageAt.Store(time.Now())
}

func (s *stats) incOut(n int) {
	s.messagesOut.Add(int64(n))
}

func (s *stats) incErr() {
	s.errors.Add(1)
}

// ---------------------------------------------------------------------------
// KafkaHealthProbe
// ---------------------------------------------------------------------------

// KafkaHealthProbe monitors Kafka connectivity with a consecutive-failure
// threshold. It is safe for concurrent use.
type KafkaHealthProbe struct {
	connected      atomic.Bool
	failCount      atomic.Int32
	threshold      int32 // consecutive failures before marking disconnected
	disconnectedAt atomic.Value // stores time.Time
}

func newKafkaHealthProbe(threshold int32) *KafkaHealthProbe {
	p := &KafkaHealthProbe{threshold: threshold}
	p.connected.Store(true)
	return p
}

// check executes fn and updates the probe state. If fn returns an error the
// failure counter is incremented; once it reaches the threshold the probe is
// marked disconnected. A single success resets the counter and marks connected.
func (p *KafkaHealthProbe) check(fn func() error) {
	if p.threshold == 0 {
		p.threshold = 3
	}
	if err := fn(); err != nil {
		n := p.failCount.Add(1)
		if n >= p.threshold {
			if p.connected.Swap(false) {
				// Was connected → just transitioned
				p.disconnectedAt.Store(time.Now())
			}
		}
	} else {
		p.failCount.Store(0)
		p.connected.Store(true)
	}
}

// IsConnected returns the current connectivity state.
func (p *KafkaHealthProbe) IsConnected() bool {
	return p.connected.Load()
}

// ---------------------------------------------------------------------------
// KafkaBridge
// ---------------------------------------------------------------------------

type KafkaBridge struct {
	telemetryWriter messageWriter
	alarmWriter     messageWriter
	stats           stats
	cfg             *Config
	probe           *KafkaHealthProbe
	probeCheckFunc  func() error
	startTime       time.Time
	redisClient     *redis.Client
}

type messageWriter interface {
	WriteMessages(context.Context, ...kafka.Message) error
	Close() error
}

func newKafkaWriter(cfg *Config, topic string) *kafka.Writer {
	return &kafka.Writer{
		Addr:            kafka.TCP(cfg.Kafka.Brokers...),
		Topic:           topic,
		Balancer:        &kafka.Hash{},
		BatchSize:       cfg.Kafka.BatchSize,
		BatchTimeout:    time.Duration(cfg.Kafka.BatchTimeout) * time.Millisecond,
		RequiredAcks:    kafka.RequireAll,
		MaxAttempts:     5,
		WriteBackoffMin: 100 * time.Millisecond,
		WriteBackoffMax: 2 * time.Second,
		Async:           false,
	}
}

func NewKafkaBridge(cfg *Config) *KafkaBridge {
	tw := newKafkaWriter(cfg, cfg.Kafka.TelemetryTopic)
	aw := newKafkaWriter(cfg, cfg.Kafka.AlarmTopic)

	bridge := &KafkaBridge{
		cfg:             cfg,
		telemetryWriter: tw,
		alarmWriter:     aw,
		probe:           newKafkaHealthProbe(3),
		startTime:       time.Now(),
	}

	// Build a check function that probes Kafka connectivity via real TCP dial.
	bridge.probeCheckFunc = func() error {
		dialer := &kafka.Dialer{Timeout: 5 * time.Second}
		for _, broker := range cfg.Kafka.Brokers {
			conn, err := dialer.DialContext(context.Background(), "tcp", broker)
			if err != nil {
				return err
			}
			conn.Close()
		}
		return nil
	}

	return bridge
}

// ---------------------------------------------------------------------------
// EMQX Webhook handler
// ---------------------------------------------------------------------------

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
	if sn == "" || msgType == "unknown" {
		b.stats.incErr()
		http.Error(w, "invalid mqtt topic", http.StatusBadRequest)
		return
	}
	b.stats.incIn()

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

	writeTimeout := time.Duration(b.cfg.Server.Timeout) * time.Second
	if writeTimeout <= 0 {
		writeTimeout = 30 * time.Second
	}
	ctx, cancel := context.WithTimeout(r.Context(), writeTimeout)
	defer cancel()
	if err := writer.WriteMessages(ctx, kafkaMsg); err != nil {
		b.stats.incErr()
		log.Printf("Kafka write error: %v", err)
		http.Error(w, "kafka error", http.StatusBadGateway)
		return
	}

	b.stats.incOut(1)
	w.WriteHeader(http.StatusNoContent)
}

// ---------------------------------------------------------------------------
// Topic helpers
// ---------------------------------------------------------------------------

func extractSN(topic string) string {
	parts := strings.Split(topic, "/")
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}

func extractMsgType(topic string) string {
	parts := strings.Split(topic, "/")
	if len(parts) >= 3 {
		return strings.Join(parts[2:], "/")
	}
	return "unknown"
}

// ---------------------------------------------------------------------------
// HTTP handlers: /health, /metrics, /stats
// ---------------------------------------------------------------------------

// healthStatus returns "ok", "degraded", or "down".
func (b *KafkaBridge) healthStatus() string {
	if b.probe.IsConnected() {
		return "ok"
	}
	if v := b.probe.disconnectedAt.Load(); v != nil {
		if ts, ok := v.(time.Time); ok {
			if time.Since(ts) > 90*time.Second {
				return "down"
			}
		}
	}
	return "degraded"
}

func (b *KafkaBridge) handleHealth(w http.ResponseWriter, r *http.Request) {
	status := b.healthStatus()

	kafkaStatus := "connected"
	if !b.probe.IsConnected() {
		kafkaStatus = "disconnected"
	}

	data := map[string]interface{}{
		"status":         status,
		"kafka":          kafkaStatus,
		"messages_in":    b.stats.messagesIn.Load(),
		"messages_out":   b.stats.messagesOut.Load(),
		"errors":         b.stats.errors.Load(),
		"uptime_seconds": int(time.Since(b.startTime).Seconds()),
	}

	w.Header().Set("Content-Type", "application/json")
	if status == "down" {
		w.WriteHeader(http.StatusServiceUnavailable)
	} else {
		w.WriteHeader(http.StatusOK)
	}
	json.NewEncoder(w).Encode(data)
}

func (b *KafkaBridge) handleMetrics(w http.ResponseWriter, r *http.Request) {
	messagesIn := b.stats.messagesIn.Load()
	messagesOut := b.stats.messagesOut.Load()
	errs := b.stats.errors.Load()
	kafkaConnected := 0
	if b.probe.IsConnected() {
		kafkaConnected = 1
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	fmt.Fprintf(w, "# HELP bridge_messages_received_total Total MQTT messages received from EMQX\n")
	fmt.Fprintf(w, "# TYPE bridge_messages_received_total counter\n")
	fmt.Fprintf(w, "bridge_messages_received_total %d\n", messagesIn)
	fmt.Fprintf(w, "# HELP bridge_messages_forwarded_total Total messages forwarded to Kafka\n")
	fmt.Fprintf(w, "# TYPE bridge_messages_forwarded_total counter\n")
	fmt.Fprintf(w, "bridge_messages_forwarded_total %d\n", messagesOut)
	fmt.Fprintf(w, "# HELP bridge_errors_total Total processing errors\n")
	fmt.Fprintf(w, "# TYPE bridge_errors_total counter\n")
	fmt.Fprintf(w, "bridge_errors_total %d\n", errs)
	fmt.Fprintf(w, "# HELP bridge_kafka_connected Whether Kafka is connected (1=yes, 0=no)\n")
	fmt.Fprintf(w, "# TYPE bridge_kafka_connected gauge\n")
	fmt.Fprintf(w, "bridge_kafka_connected %d\n", kafkaConnected)
}

func (b *KafkaBridge) handleStats(w http.ResponseWriter, r *http.Request) {
	var lastMsgAt string
	if v := b.stats.lastMessageAt.Load(); v != nil {
		lastMsgAt = v.(time.Time).Format(time.RFC3339)
	}
	data := map[string]interface{}{
		"messages_in":     b.stats.messagesIn.Load(),
		"messages_out":    b.stats.messagesOut.Load(),
		"errors":          b.stats.errors.Load(),
		"last_message_at": lastMsgAt,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

// recoveryMiddleware 捕获 handler 中的 panic，防止进程崩溃。
func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				log.Printf("[PANIC] %v", err)
				http.Error(w, "internal error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------------------
// Environment variable overrides
// ---------------------------------------------------------------------------

// applyEnvOverrides 使用环境变量覆盖配置文件中的值。
func applyEnvOverrides(cfg *Config) {
	if v := os.Getenv("KAFKA_BROKERS"); v != "" {
		cfg.Kafka.Brokers = strings.Split(v, ",")
	}
	if v := os.Getenv("KAFKA_TELEMETRY_TOPIC"); v != "" {
		cfg.Kafka.TelemetryTopic = v
	}
	if v := os.Getenv("KAFKA_ALARM_TOPIC"); v != "" {
		cfg.Kafka.AlarmTopic = v
	}
	if v := os.Getenv("EMQX_TOKEN"); v != "" {
		cfg.EMQX.Token = v
	}
	if v := os.Getenv("EMQX_WEBHOOK_PORT"); v != "" {
		if port, err := strconv.Atoi(v); err == nil {
			cfg.Server.Port = port
		}
	}
	if v := os.Getenv("REDIS_ADDR"); v != "" {
		cfg.Redis.Addr = v
	}
}

// ---------------------------------------------------------------------------
// Background goroutines
// ---------------------------------------------------------------------------

func (b *KafkaBridge) runHealthProbe(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			b.probe.check(b.probeCheckFunc)
		}
	}
}

func (b *KafkaBridge) runRedisHealthReport(ctx context.Context) {
	if b.redisClient == nil {
		return
	}
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			b.reportHealthToRedis(ctx)
		}
	}
}

func (b *KafkaBridge) reportHealthToRedis(ctx context.Context) {
	if b.redisClient == nil {
		return
	}
	status := b.healthStatus()
	kafkaStatus := "connected"
	if !b.probe.IsConnected() {
		kafkaStatus = "disconnected"
	}
	payload := map[string]interface{}{
		"status":         status,
		"kafka":          kafkaStatus,
		"uptime_seconds": int(time.Since(b.startTime).Seconds()),
	}
	data, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[WARN] Failed to marshal health payload: %v", err)
		return
	}
	rctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := b.redisClient.Set(rctx, "pipeline:health:bridge", string(data), 90*time.Second).Err(); err != nil {
		log.Printf("[WARN] Failed to report health to Redis: %v", err)
	}
}

func printStats(ctx context.Context, st *stats) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			var lastMsgAt string
			if v := st.lastMessageAt.Load(); v != nil {
				lastMsgAt = v.(time.Time).Format("15:04:05")
			}
			log.Printf("Stats: in=%d, out=%d, errors=%d, last_msg=%s",
				st.messagesIn.Load(), st.messagesOut.Load(), st.errors.Load(),
				lastMsgAt)
		}
	}
}

// ---------------------------------------------------------------------------
// Config loader
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	configFile := "config.yaml"
	if len(os.Args) > 1 {
		configFile = os.Args[1]
	}

	cfg, err := loadConfig(configFile)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// 环境变量覆盖配置
	applyEnvOverrides(cfg)

	if err := cfg.Validate(); err != nil {
		log.Fatalf("Config validation failed: %v", err)
	}

	log.Printf("Starting MQTT-Kafka Bridge (Webhook mode)")
	log.Printf("  Listen: :%d", cfg.Server.Port)
	log.Printf("  Kafka: %v", cfg.Kafka.Brokers)
	log.Printf("  Topics: %s, %s", cfg.Kafka.TelemetryTopic, cfg.Kafka.AlarmTopic)

	bridge := NewKafkaBridge(cfg)

	// Optional Redis client
	if cfg.Redis.Addr != "" {
		bridge.redisClient = redis.NewClient(&redis.Options{
			Addr:     cfg.Redis.Addr,
			Password: cfg.Redis.Password,
			DB:       cfg.Redis.DB,
		})
		log.Printf("  Redis: %s (db=%d)", cfg.Redis.Addr, cfg.Redis.DB)
	} else {
		log.Printf("  Redis: not configured, health reporting disabled")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	mux := http.NewServeMux()
	mux.HandleFunc("/webhook", bridge.handleWebhook)
	mux.HandleFunc("/health", bridge.handleHealth)
	mux.HandleFunc("/stats", bridge.handleStats)
	mux.HandleFunc("/metrics", bridge.handleMetrics)

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      recoveryMiddleware(mux),
		ReadTimeout:  time.Duration(cfg.Server.Timeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.Timeout) * time.Second,
	}

	go func() {
		log.Printf("HTTP server listening on :%d", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	go printStats(ctx, &bridge.stats)
	go bridge.runHealthProbe(ctx)
	go bridge.runRedisHealthReport(ctx)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down...")
	cancel()
	srvCtx, srvCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer srvCancel()
	srv.Shutdown(srvCtx)
	bridge.telemetryWriter.Close()
	bridge.alarmWriter.Close()
	if bridge.redisClient != nil {
		bridge.redisClient.Close()
	}
	log.Println("Bridge stopped")
}
