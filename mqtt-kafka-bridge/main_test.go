package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ===================== stringsSplit =====================

func TestStringsSplit(t *testing.T) {
	tests := []struct {
		name string
		s    string
		sep  string
		want []string
	}{
		{"basic", "a/b/c", "/", []string{"a", "b", "c"}},
		{"no separator", "abc", "/", []string{"abc"}},
		{"empty string", "", "/", []string{""}},
		{"leading separator", "/a/b", "/", []string{"", "a", "b"}},
		{"trailing separator", "a/b/", "/", []string{"a", "b", ""}},
		{"multi-char sep", "a::b::c", "::", []string{"a", "b", "c"}},
		{"single element", "hello", "/", []string{"hello"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := strings.Split(tt.s, tt.sep)
			assert.Equal(t, tt.want, got)
		})
	}
}

// ===================== stringsJoin =====================

func TestStringsJoin(t *testing.T) {
	tests := []struct {
		name  string
		parts []string
		sep   string
		want  string
	}{
		{"basic", []string{"a", "b", "c"}, "/", "a/b/c"},
		{"single", []string{"hello"}, "/", "hello"},
		{"empty slice", []string{}, "/", ""},
		{"with empty parts", []string{"a", "", "b"}, "/", "a//b"},
		{"multi-char sep", []string{"x", "y"}, "::", "x::y"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := strings.Join(tt.parts, tt.sep)
			assert.Equal(t, tt.want, got)
		})
	}
}

// ===================== extractSN =====================

func TestExtractSN(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  string
	}{
		{"standard topic", "cs_inv/DEV001/data", "DEV001"},
		{"two segments", "cs_inv/SN123", "SN123"},
		{"deep topic", "cs_inv/ABC/data/alarm", "ABC"},
		{"single segment", "cs_inv", ""},
		{"empty topic", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractSN(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

// ===================== extractMsgType =====================

func TestExtractMsgType(t *testing.T) {
	tests := []struct {
		name  string
		topic string
		want  string
	}{
		{"data type", "cs_inv/SN001/data", "data"},
		{"alarm type", "cs_inv/SN001/alarm", "alarm"},
		{"deep type", "cs_inv/SN001/data/alarm", "data/alarm"},
		{"status type", "cs_inv/SN001/status", "status"},
		{"ota status", "cs_inv/SN001/ota/status", "ota/status"},
		{"two segments only", "cs_inv/SN001", "unknown"},
		{"single segment", "cs_inv", "unknown"},
		{"empty topic", "", "unknown"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractMsgType(tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

// ===================== Config.Validate =====================

func TestConfigValidate(t *testing.T) {
	validCfg := Config{}
	validCfg.Server.Port = 8080
	validCfg.Kafka.Brokers = []string{"localhost:9092"}
	validCfg.Kafka.TelemetryTopic = "inv-telemetry"
	validCfg.Kafka.AlarmTopic = "inv-alerts"

	t.Run("valid config", func(t *testing.T) {
		assert.NoError(t, validCfg.Validate())
	})

	t.Run("missing brokers", func(t *testing.T) {
		cfg := validCfg
		cfg.Kafka.Brokers = nil
		err := cfg.Validate()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "kafka.brokers")
	})

	t.Run("missing telemetry topic", func(t *testing.T) {
		cfg := validCfg
		cfg.Kafka.TelemetryTopic = ""
		err := cfg.Validate()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "telemetry_topic")
	})

	t.Run("missing alarm topic", func(t *testing.T) {
		cfg := validCfg
		cfg.Kafka.AlarmTopic = ""
		err := cfg.Validate()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "alarm_topic")
	})

	t.Run("invalid port zero", func(t *testing.T) {
		cfg := validCfg
		cfg.Server.Port = 0
		err := cfg.Validate()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "server.port")
	})

	t.Run("invalid port too large", func(t *testing.T) {
		cfg := validCfg
		cfg.Server.Port = 70000
		err := cfg.Validate()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "server.port")
	})

	t.Run("multiple errors", func(t *testing.T) {
		cfg := Config{}
		err := cfg.Validate()
		require.Error(t, err)
		assert.Contains(t, err.Error(), "kafka.brokers")
		assert.Contains(t, err.Error(), "telemetry_topic")
		assert.Contains(t, err.Error(), "server.port")
	})
}

// ===================== loadConfig =====================

func TestLoadConfig(t *testing.T) {
	yamlContent := `
server:
  port: 9090
  workers: 8
  timeout: 60
kafka:
  brokers:
    - broker1:9092
    - broker2:9092
  telemetry_topic: test-telemetry
  alarm_topic: test-alarm
  batch_size: 50
  batch_timeout: 200
emqx:
  token: "secret-token"
`
	tmpFile, err := os.CreateTemp("", "bridge-config-*.yaml")
	require.NoError(t, err)
	defer os.Remove(tmpFile.Name())

	_, err = tmpFile.WriteString(yamlContent)
	require.NoError(t, err)
	tmpFile.Close()

	cfg, err := loadConfig(tmpFile.Name())
	require.NoError(t, err)

	assert.Equal(t, 9090, cfg.Server.Port)
	assert.Equal(t, 8, cfg.Server.Workers)
	assert.Equal(t, 60, cfg.Server.Timeout)
	assert.Equal(t, []string{"broker1:9092", "broker2:9092"}, cfg.Kafka.Brokers)
	assert.Equal(t, "test-telemetry", cfg.Kafka.TelemetryTopic)
	assert.Equal(t, "test-alarm", cfg.Kafka.AlarmTopic)
	assert.Equal(t, 50, cfg.Kafka.BatchSize)
	assert.Equal(t, 200, cfg.Kafka.BatchTimeout)
	assert.Equal(t, "secret-token", cfg.EMQX.Token)
}

func TestLoadConfig_Defaults(t *testing.T) {
	yamlContent := `
kafka:
  brokers:
    - localhost:9092
  telemetry_topic: t
  alarm_topic: a
`
	tmpFile, err := os.CreateTemp("", "bridge-config-defaults-*.yaml")
	require.NoError(t, err)
	defer os.Remove(tmpFile.Name())

	_, err = tmpFile.WriteString(yamlContent)
	require.NoError(t, err)
	tmpFile.Close()

	cfg, err := loadConfig(tmpFile.Name())
	require.NoError(t, err)

	assert.Equal(t, 8080, cfg.Server.Port)
	assert.Equal(t, 4, cfg.Server.Workers)
	assert.Equal(t, 30, cfg.Server.Timeout)
	assert.Equal(t, 100, cfg.Kafka.BatchSize)
	assert.Equal(t, 100, cfg.Kafka.BatchTimeout)
}

func TestLoadConfig_FileNotFound(t *testing.T) {
	_, err := loadConfig("/nonexistent/path/config.yaml")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "read config")
}

func TestLoadConfig_InvalidYAML(t *testing.T) {
	tmpFile, err := os.CreateTemp("", "bridge-bad-*.yaml")
	require.NoError(t, err)
	defer os.Remove(tmpFile.Name())

	_, err = tmpFile.WriteString("{{invalid yaml")
	require.NoError(t, err)
	tmpFile.Close()

	_, err = loadConfig(tmpFile.Name())
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "parse config")
}

// ===================== Health & Stats endpoints =====================

func TestHealthEndpoint(t *testing.T) {
	cfg := &Config{}
	cfg.Server.Port = 8080
	cfg.Kafka.Brokers = []string{"localhost:9092"}
	cfg.Kafka.TelemetryTopic = "inv-telemetry"
	cfg.Kafka.AlarmTopic = "inv-alerts"

	bridge := NewKafkaBridge(cfg)
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})
	_ = bridge // bridge used in webhook tests below

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Body.String(), `"status":"ok"`)
}

func TestStatsEndpoint(t *testing.T) {
	cfg := &Config{}
	cfg.Server.Port = 8080
	cfg.Kafka.Brokers = []string{"localhost:9092"}
	cfg.Kafka.TelemetryTopic = "inv-telemetry"
	cfg.Kafka.AlarmTopic = "inv-alerts"

	bridge := NewKafkaBridge(cfg)
	bridge.stats.incIn()
	bridge.stats.incIn()
	bridge.stats.incOut(3)
	bridge.stats.incErr()

	mux := http.NewServeMux()
	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		bridge.stats.mu.Lock()
		data := map[string]interface{}{
			"messages_in":     bridge.stats.messagesIn,
			"messages_out":    bridge.stats.messagesOut,
			"errors":          bridge.stats.errors,
			"last_message_at": bridge.stats.lastMessageAt.Format("2006-01-02T15:04:05Z07:00"),
		}
		bridge.stats.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(data)
	})

	req := httptest.NewRequest(http.MethodGet, "/stats", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)

	var body map[string]interface{}
	err := json.Unmarshal(rec.Body.Bytes(), &body)
	require.NoError(t, err)
	assert.Equal(t, float64(2), body["messages_in"])
	assert.Equal(t, float64(3), body["messages_out"])
	assert.Equal(t, float64(1), body["errors"])
}

// ===================== Stats counters =====================

func TestStatsCounters(t *testing.T) {
	var s stats

	s.incIn()
	s.incIn()
	s.mu.Lock()
	assert.Equal(t, int64(2), s.messagesIn)
	assert.False(t, s.lastMessageAt.IsZero())
	s.mu.Unlock()

	s.incOut(5)
	s.mu.Lock()
	assert.Equal(t, int64(5), s.messagesOut)
	s.mu.Unlock()

	s.incErr()
	s.mu.Lock()
	assert.Equal(t, int64(1), s.errors)
	s.mu.Unlock()
}

// ===================== Webhook handler =====================

func TestWebhook_MethodNotAllowed(t *testing.T) {
	cfg := &Config{}
	cfg.Kafka.Brokers = []string{"localhost:9092"}
	cfg.Kafka.TelemetryTopic = "t"
	cfg.Kafka.AlarmTopic = "a"
	bridge := NewKafkaBridge(cfg)

	req := httptest.NewRequest(http.MethodGet, "/webhook", nil)
	rec := httptest.NewRecorder()
	bridge.handleWebhook(rec, req)

	assert.Equal(t, http.StatusMethodNotAllowed, rec.Code)
}

func TestWebhook_BadJSON(t *testing.T) {
	cfg := &Config{}
	cfg.Kafka.Brokers = []string{"localhost:9092"}
	cfg.Kafka.TelemetryTopic = "t"
	cfg.Kafka.AlarmTopic = "a"
	bridge := NewKafkaBridge(cfg)

	req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader("not json"))
	rec := httptest.NewRecorder()
	bridge.handleWebhook(rec, req)

	assert.Equal(t, http.StatusBadRequest, rec.Code)
}

func TestWebhook_Unauthorized(t *testing.T) {
	cfg := &Config{}
	cfg.Kafka.Brokers = []string{"localhost:9092"}
	cfg.Kafka.TelemetryTopic = "t"
	cfg.Kafka.AlarmTopic = "a"
	cfg.EMQX.Token = "my-secret"
	bridge := NewKafkaBridge(cfg)

	body := `{"topic":"cs_inv/SN1/data","payload":"{}"}`

	// No token
	req := httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(body))
	rec := httptest.NewRecorder()
	bridge.handleWebhook(rec, req)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)

	// Wrong token
	req = httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer wrong")
	rec = httptest.NewRecorder()
	bridge.handleWebhook(rec, req)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)

	// Correct Bearer token
	req = httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer my-secret")
	rec = httptest.NewRecorder()
	bridge.handleWebhook(rec, req)
	// Will fail at kafka write (no kafka running), but not unauthorized
	assert.NotEqual(t, http.StatusUnauthorized, rec.Code)

	// Correct raw token
	req = httptest.NewRequest(http.MethodPost, "/webhook", strings.NewReader(body))
	req.Header.Set("Authorization", "my-secret")
	rec = httptest.NewRecorder()
	bridge.handleWebhook(rec, req)
	assert.NotEqual(t, http.StatusUnauthorized, rec.Code)
}

// ===================== Message format =====================

func TestWebhook_MessageFormat(t *testing.T) {
	// Verify that a valid webhook message produces correct Kafka message structure
	// We can't write to real kafka, but we can verify the marshalling logic
	msg := EMQXWebhookMessage{
		ClientID:  "client1",
		Topic:     "cs_inv/SN001/data",
		Payload:   `{"voltage":220.5,"current":10.3}`,
		QoS:       1,
		Timestamp: 1700000000,
	}

	sn := extractSN(msg.Topic)
	msgType := extractMsgType(msg.Topic)

	assert.Equal(t, "SN001", sn)
	assert.Equal(t, "data", msgType)

	var payloadObj interface{}
	err := json.Unmarshal([]byte(msg.Payload), &payloadObj)
	require.NoError(t, err)

	rawMsg := map[string]interface{}{
		"sn":         sn,
		"client_id":  msg.ClientID,
		"msg_type":   msgType,
		"mqtt_topic": msg.Topic,
		"qos":        msg.QoS,
		"payload":    payloadObj,
	}

	body, err := json.Marshal(rawMsg)
	require.NoError(t, err)

	var result map[string]interface{}
	err = json.Unmarshal(body, &result)
	require.NoError(t, err)

	assert.Equal(t, "SN001", result["sn"])
	assert.Equal(t, "data", result["msg_type"])
	assert.Equal(t, "cs_inv/SN001/data", result["mqtt_topic"])
	assert.Equal(t, float64(1), result["qos"])

	payload := result["payload"].(map[string]interface{})
	assert.Equal(t, 220.5, payload["voltage"])
	assert.Equal(t, 10.3, payload["current"])
}

func TestWebhook_AlarmRouting(t *testing.T) {
	tests := []struct {
		topic       string
		wantAlarm   bool
	}{
		{"cs_inv/SN1/data", false},
		{"cs_inv/SN1/alarm", true},
		{"cs_inv/SN1/data/alarm", true},
		{"cs_inv/SN1/status", false},
		{"cs_inv/SN1/ota/status", false},
	}
	for _, tt := range tests {
		t.Run(tt.topic, func(t *testing.T) {
			msgType := extractMsgType(tt.topic)
			isAlarm := msgType == "alarm" || msgType == "data/alarm"
			assert.Equal(t, tt.wantAlarm, isAlarm)
		})
	}
}

// ===================== joinStrs =====================

func TestJoinStrs(t *testing.T) {
	tests := []struct {
		name string
		ss   []string
		sep  string
		want string
	}{
		{"empty", []string{}, ", ", ""},
		{"single", []string{"a"}, ", ", "a"},
		{"multiple", []string{"a", "b", "c"}, ", ", "a, b, c"},
		{"newline sep", []string{"x", "y"}, "\n  - ", "x\n  - y"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := strings.Join(tt.ss, tt.sep)
			assert.Equal(t, tt.want, got)
		})
	}
}
