package service

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/pkg/logger"
	"inv-device-server/pkg/timezone"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type AlertConsumer struct {
	consumer     kafkaMessageReader
	rdb          *redis.Client
	ingestErrors ingestErrorStore
	apiServer    string
	internalKey  string
	httpClient   *http.Client
	dlq          DeadLetterQueue
	metrics      *IngestMetrics
	maxRetries   int
	baseBackoff  time.Duration
}

type RawAlertMessage struct {
	SN         string          `json:"sn"`
	Source     string          `json:"source"`
	MsgType    string          `json:"msg_type"`
	MQTTTopic  string          `json:"mqtt_topic"`
	Payload    json.RawMessage `json:"payload"`
	ReceivedAt string          `json:"received_at"`
}

// 新告警格式 (MQTT payload)
type RawAlarmPayload struct {
	Code      int                      `json:"code"`
	Level     string                   `json:"level"`
	Message   string                   `json:"message"`
	Count     int                      `json:"count"`
	Alarms    []map[string]interface{} `json:"alarms"`
	Timestamp int64                    `json:"timestamp"`
}

func NewAlertConsumer(brokers []string, topic string, groupID string, rdb *redis.Client, ingestErrors ingestErrorStore, apiServer string, internalKey string) *AlertConsumer {
	return &AlertConsumer{
		consumer: kafka.NewReader(kafka.ReaderConfig{
			Brokers:  brokers,
			Topic:    topic,
			GroupID:  groupID,
			MinBytes: 1,                // 降低阈值，避免低频小消息延迟
			MaxBytes: 10e6,
			MaxWait:  1 * time.Second, // 最多等待1秒即返回可用消息
		}),
		rdb:          rdb,
		ingestErrors: ingestErrors,
		apiServer:    strings.TrimRight(apiServer, "/"),
		internalKey:  internalKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 50,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		maxRetries:  DefaultMaxRetries,
		baseBackoff: DefaultBaseBackoff,
	}
}

// WithDLQ sets the dead-letter queue for messages that exhaust retries.
func (a *AlertConsumer) WithDLQ(dlq DeadLetterQueue) *AlertConsumer {
	a.dlq = dlq
	return a
}

// WithMetrics sets the monitoring metrics tracker.
func (a *AlertConsumer) WithMetrics(metrics *IngestMetrics) *AlertConsumer {
	a.metrics = metrics
	return a
}

// WithMaxRetries overrides the default maximum retry count.
func (a *AlertConsumer) WithMaxRetries(n int) *AlertConsumer {
	a.maxRetries = n
	return a
}

// WithBaseBackoff overrides the default exponential backoff base duration.
func (a *AlertConsumer) WithBaseBackoff(d time.Duration) *AlertConsumer {
	a.baseBackoff = d
	return a
}

func (a *AlertConsumer) Start(ctx context.Context) {
	go runOrderedKafkaConsumer(ctx, "alert-consumer", a.consumer, a.processAlert, 250*time.Millisecond)
}

func (a *AlertConsumer) processAlert(ctx context.Context, m kafka.Message) error {
	err := a.deliverAlert(ctx, m)
	if err == nil {
		return nil
	}
	code := ""
	cause := err
	if permanent, ok := asPermanentMessage(err); ok {
		code, cause = permanent.code, permanent.err
	} else {
		var httpErr *downstreamHTTPError
		if errors.As(err, &httpErr) && httpErr.permanent() {
			code, cause = "DOWNSTREAM_HTTP_4XX", httpErr
		}
	}
	if code == "" {
		return err
	}
	var metadata struct {
		SN string `json:"sn"`
	}
	_ = json.Unmarshal(m.Value, &metadata)
	if a.ingestErrors == nil {
		return fmt.Errorf("permanent alert error cannot be audited (%s): %w", code, cause)
	}
	if saveErr := a.ingestErrors.SaveIngestError(ctx, metadata.SN, m.Topic, m.Value, code, cause.Error()); saveErr != nil {
		return fmt.Errorf("save permanent alert ingest error %s: %w", code, saveErr)
	}
	logger.Warn("Permanent alert message isolated in device_ingest_errors",
		zap.String("sn", metadata.SN), zap.String("topic", m.Topic), zap.String("error_code", code), zap.Error(cause))
	return nil
}

func (a *AlertConsumer) deliverAlert(ctx context.Context, m kafka.Message) error {
	hash := md5.Sum(m.Value)
	msgKey := fmt.Sprintf("alert:dedup:%x", hash)
	if a.rdb != nil {
		exists, err := a.rdb.Exists(ctx, msgKey).Result()
		if err != nil {
			logger.Warn("Alert dedup lookup failed; proceeding with idempotent delivery", zap.Error(err))
		} else if exists > 0 {
			logger.Info("Alert message already delivered, skipping duplicate",
				zap.String("topic", m.Topic),
				zap.Int("partition", m.Partition),
				zap.Int64("offset", m.Offset))
			return nil
		}
	}

	var raw RawAlertMessage
	if err := json.Unmarshal(m.Value, &raw); err != nil {
		return permanentMessage("INVALID_ALERT_BRIDGE_JSON", fmt.Errorf("decode alert bridge message: %w", err))
	}

	if strings.TrimSpace(raw.SN) == "" {
		return permanentMessage("MISSING_DEVICE_SN", fmt.Errorf("alert bridge message is missing device sn"))
	}
	receivedAt := timezone.NowUTC()
	if parsed, err := time.Parse(time.RFC3339Nano, raw.ReceivedAt); err == nil {
		receivedAt = parsed.UTC()
	} else if !m.Time.IsZero() {
		receivedAt = m.Time.UTC()
	}
	legacyTimestamp := receivedAt.Unix()

	// 将 payload 统一转为 map，并保留 V1 原始信封供 API 审计存储。
	payloadBytes := bytes.TrimSpace(raw.Payload)
	if len(payloadBytes) > 0 && payloadBytes[0] == '"' {
		var encoded string
		if err := json.Unmarshal(payloadBytes, &encoded); err != nil {
			return permanentMessage("INVALID_ALARM_PAYLOAD", fmt.Errorf("decode string alarm payload: %w", err))
		}
		payloadBytes = []byte(encoded)
	}
	var payloadMap map[string]interface{}
	if len(payloadBytes) == 0 || bytes.Equal(payloadBytes, []byte("null")) {
		// Legacy devices use an empty payload to report recovery.
	} else if err := json.Unmarshal(payloadBytes, &payloadMap); err != nil {
		return permanentMessage("INVALID_ALARM_PAYLOAD", fmt.Errorf("decode alarm payload object: %w", err))
	} else if payloadMap == nil {
		return permanentMessage("INVALID_ALARM_PAYLOAD", fmt.Errorf("alarm payload must be a JSON object"))
	}

	// Final V1 alarm envelope: {t,v,data:{source,code,level,state}}.
	if _, matched, err := parseAlarmV1(raw.SN, payloadMap); matched {
		if err != nil {
			return permanentMessage("INVALID_ALARM_V1", fmt.Errorf("invalid V1 alarm payload: %w", err))
		}
		if err := a.postInternalAlarmEnvelope(raw, payloadBytes); err != nil {
			return fmt.Errorf("post V1 alarm: %w", err)
		}
		a.markAlertProcessed(ctx, msgKey)
		return nil
	}

	// 空 payload 或空对象 → 告警清除
	if len(payloadMap) == 0 {
		clearKey := fmt.Sprintf("alarm:clear:%s", raw.SN)
		if a.rdb != nil {
			exists, err := a.rdb.Exists(ctx, clearKey).Result()
			if err == nil && exists > 0 {
				logger.Info("Alarm clear already sent recently, skipping", zap.String("sn", raw.SN))
				a.markAlertProcessed(ctx, msgKey)
				return nil
			}
		}
		alarm := &model.AlarmData{
			SN:         raw.SN,
			Code:       0,
			Level:      "normal",
			Message:    "设备故障恢复",
			Count:      0,
			Alarms:     nil,
			Timestamp:  legacyTimestamp,
			ReceivedAt: receivedAt,
		}
		if err := a.postInternalAlarm(alarm); err != nil {
			return fmt.Errorf("post empty-payload alarm clear: %w", err)
		}
		if a.rdb != nil {
			if err := a.rdb.Set(ctx, clearKey, "1", 10*time.Second).Err(); err != nil {
				logger.Warn("Failed to mark alarm clear dedup after delivery", zap.Error(err))
			}
		}
		a.markAlertProcessed(ctx, msgKey)
		return nil
	}

	// 解析新告警格式
	var alarmPayload RawAlarmPayload
	// 支持嵌套 data 格式: {"data": {"code":..., ...}, "timestamp":...}
	dataMap := payloadMap
	if data, ok := payloadMap["data"].(map[string]interface{}); ok {
		dataMap = data
		// 保留外层 timestamp
		if ts, ok := payloadMap["timestamp"]; ok {
			dataMap["timestamp"] = ts
		}
	}
	dataJSON, err := json.Marshal(dataMap)
	if err != nil {
		return permanentMessage("INVALID_LEGACY_ALARM", fmt.Errorf("encode legacy alarm payload: %w", err))
	}
	if err := json.Unmarshal(dataJSON, &alarmPayload); err != nil {
		return permanentMessage("INVALID_LEGACY_ALARM", fmt.Errorf("decode legacy alarm payload: %w", err))
	}
	if alarmPayload.Timestamp <= 0 {
		alarmPayload.Timestamp = legacyTimestamp
	}

	// code=0 且 level="normal" → 告警清除
	if alarmPayload.Code == 0 && alarmPayload.Level == "normal" {
		clearKey := fmt.Sprintf("alarm:clear:%s", raw.SN)
		if a.rdb != nil {
			exists, lookupErr := a.rdb.Exists(ctx, clearKey).Result()
			if lookupErr == nil && exists > 0 {
				logger.Info("Alarm clear already sent recently, skipping", zap.String("sn", raw.SN))
				a.markAlertProcessed(ctx, msgKey)
				return nil
			}
		}
		alarm := &model.AlarmData{
			SN:         raw.SN,
			Code:       0,
			Level:      "normal",
			Message:    "设备故障恢复",
			Count:      0,
			Alarms:     nil,
			Timestamp:  alarmPayload.Timestamp,
			ReceivedAt: receivedAt,
		}
		if err := a.postInternalAlarm(alarm); err != nil {
			return fmt.Errorf("post code-zero alarm clear: %w", err)
		}
		if a.rdb != nil {
			if err := a.rdb.Set(ctx, clearKey, "1", 10*time.Second).Err(); err != nil {
				logger.Warn("Failed to mark alarm clear dedup after delivery", zap.Error(err))
			}
		}
		a.markAlertProcessed(ctx, msgKey)
		return nil
	}

	// 有 alarms 数组时，逐个上报（过滤掉 code=0 的清除条目，避免与故障告警在同一消息中同时发送导致乱序）
	if len(alarmPayload.Alarms) > 0 {
		hasActiveFault := false
		for _, item := range alarmPayload.Alarms {
			if c, ok := toInt(item["code"]); ok && c != 0 {
				hasActiveFault = true
				break
			}
		}
		for _, item := range alarmPayload.Alarms {
			// 如果消息中同时包含故障和清除条目，过滤掉清除条目
			// 清除通知应由设备单独发送空 payload 或 code=0 消息触发
			if c, ok := toInt(item["code"]); ok && c == 0 && hasActiveFault {
				logger.Info("Skipping alarm clear in mixed message", zap.String("sn", raw.SN))
				continue
			}
			code := 0
			level := ""
			message := ""
			if c, ok := toInt(item["code"]); ok {
				code = c
			}
			if l, ok := item["level"].(string); ok {
				level = l
			}
			if m, ok := item["message"].(string); ok {
				message = m
			}
			alarm := &model.AlarmData{
				SN:         raw.SN,
				Code:       code,
				Level:      level,
				Message:    message,
				Count:      alarmPayload.Count,
				Alarms:     nil,
				Timestamp:  alarmPayload.Timestamp,
				ReceivedAt: receivedAt,
			}
			if err := a.postInternalAlarm(alarm); err != nil {
				return fmt.Errorf("post alarm item code %d: %w", code, err)
			}
			logger.Info("Alarm item recorded",
				zap.String("sn", raw.SN),
				zap.Int("code", code),
				zap.String("level", level),
				zap.String("message", message))
		}
	} else {
		// 没有 alarms 数组，使用顶层字段
		alarm := &model.AlarmData{
			SN:         raw.SN,
			Code:       alarmPayload.Code,
			Level:      alarmPayload.Level,
			Message:    alarmPayload.Message,
			Count:      alarmPayload.Count,
			Alarms:     nil,
			Timestamp:  alarmPayload.Timestamp,
			ReceivedAt: receivedAt,
		}
		if err := a.postInternalAlarm(alarm); err != nil {
			return fmt.Errorf("post alarm code %d: %w", alarmPayload.Code, err)
		}
		logger.Info("Alarm recorded",
			zap.String("sn", raw.SN),
			zap.Int("code", alarmPayload.Code),
			zap.String("level", alarmPayload.Level),
			zap.String("message", alarmPayload.Message))
	}

	a.markAlertProcessed(ctx, msgKey)
	return nil
}

func (a *AlertConsumer) markAlertProcessed(ctx context.Context, key string) {
	if a.rdb == nil {
		return
	}
	if err := a.rdb.Set(ctx, key, "1", 60*time.Second).Err(); err != nil {
		logger.Warn("Failed to mark alert dedup after successful delivery", zap.Error(err))
	}
}

func parseAlarmV1(sn string, payload map[string]interface{}) (*model.AlarmData, bool, error) {
	version, hasVersion := toInt(payload["v"])
	data, hasData := payload["data"].(map[string]interface{})
	if !hasVersion || !hasData {
		return nil, false, nil
	}
	if version != 1 {
		return nil, true, fmt.Errorf("unsupported alarm version %d", version)
	}
	source, sourceOK := toInt(data["source"])
	code, codeOK := toInt(data["code"])
	level, levelOK := toInt(data["level"])
	state, stateOK := toInt(data["state"])
	if !sourceOK || !codeOK || !levelOK || !stateOK {
		return nil, true, fmt.Errorf("source, code, level and state must be integers")
	}
	if source < 0 || source > 3 || code < 0 || level < 1 || level > 2 || state < 0 || state > 1 {
		return nil, true, fmt.Errorf("alarm fields are outside the V1 enum range")
	}
	levelName := "warning"
	if level == 2 {
		levelName = "fault"
	}
	timestamp, _ := toInt(payload["t"])
	return &model.AlarmData{
		SN: sn, Source: source, Code: code, Level: levelName, State: &state,
		Timestamp: int64(timestamp), ReceivedAt: timezone.NowUTC(),
	}, true, nil
}

type internalAlarmEnvelopeRequest struct {
	SN         string          `json:"sn"`
	Topic      string          `json:"topic"`
	ReceivedAt time.Time       `json:"received_at"`
	Envelope   json.RawMessage `json:"envelope"`
}

func (a *AlertConsumer) postInternalAlarmEnvelope(raw RawAlertMessage, envelope json.RawMessage) error {
	receivedAt := timezone.NowUTC()
	if parsed, err := time.Parse(time.RFC3339Nano, raw.ReceivedAt); err == nil {
		receivedAt = parsed.UTC()
	}
	return a.postInternalAlarmRequest(internalAlarmEnvelopeRequest{
		SN: raw.SN, Topic: "alarm", ReceivedAt: receivedAt, Envelope: envelope,
	})
}

func (a *AlertConsumer) postInternalAlarm(alarm *model.AlarmData) error {
	timestamp := alarm.Timestamp
	if timestamp <= 0 {
		timestamp = timezone.NowUTC().Unix()
	}
	state := 1
	if alarm.State != nil {
		state = *alarm.State
	} else if alarm.Level == "normal" || alarm.Code == 0 {
		state = 0
	}
	level := 1
	if alarm.Level == "fault" || alarm.Level == "critical" {
		level = 2
	}
	envelope, err := json.Marshal(map[string]interface{}{
		"t": timestamp,
		"v": 1,
		"data": map[string]interface{}{
			"source": alarm.Source,
			"code":   alarm.Code,
			"level":  level,
			"state":  state,
		},
	})
	if err != nil {
		return fmt.Errorf("marshal legacy alarm envelope: %w", err)
	}
	receivedAt := alarm.ReceivedAt
	if receivedAt.IsZero() {
		receivedAt = timezone.NowUTC()
	}
	return a.postInternalAlarmRequest(internalAlarmEnvelopeRequest{
		SN: alarm.SN, Topic: "alarm", ReceivedAt: receivedAt.UTC(), Envelope: envelope,
	})
}

func (a *AlertConsumer) postInternalAlarmRequest(payload internalAlarmEnvelopeRequest) error {
	if a.apiServer == "" {
		return fmt.Errorf("API server URL is empty")
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequest(http.MethodPost, a.apiServer+"/api/v1/internal/device-alarm", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if a.internalKey != "" {
		req.Header.Set("X-Internal-Key", a.internalKey)
	}

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		return &downstreamHTTPError{status: resp.StatusCode}
	}

	return nil
}

// toInt 将 interface{} 转为 int，支持 float64（JSON 数字默认类型）和 int 类型
func toInt(v interface{}) (int, bool) {
	switch n := v.(type) {
	case float64:
		return int(n), true
	case int:
		return n, true
	case int64:
		return int(n), true
	case json.Number:
		i, err := n.Int64()
		if err != nil {
			return 0, false
		}
		return int(i), true
	default:
		return 0, false
	}
}

func getKeys(m map[string]interface{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// HandleMQTTAlarm 处理从 MQTT 直连收到的告警消息（不经过 Kafka）
func (a *AlertConsumer) HandleMQTTAlarm(sn string, payload []byte) {
	ctx := context.Background()

	// 告警去重（MQTT QoS1 可能重复投递）
	hash := md5.Sum(payload)
	msgKey := fmt.Sprintf("mqtt:alarm:dedup:%x", hash)
	if a.rdb != nil {
		exists, err := a.rdb.Exists(ctx, msgKey).Result()
		if err != nil {
			logger.Warn("MQTT alarm dedup lookup failed; proceeding with delivery", zap.Error(err))
		} else if exists > 0 {
			logger.Debug("MQTT alarm already delivered, skipping duplicate", zap.String("sn", sn))
			return
		}
	}

	// 解析 payload
	var payloadMap map[string]interface{}
	if err := json.Unmarshal(payload, &payloadMap); err != nil {
		logger.Warn("Failed to parse MQTT alarm payload", zap.String("sn", sn), zap.Error(err))
		return
	}

	receivedAt := timezone.NowUTC()

	// 尝试 V1 格式: {v:1, t:..., data:{source,code,level,state}}
	if alarmData, matched, err := parseAlarmV1(sn, payloadMap); matched {
		if err != nil {
			logger.Warn("Invalid V1 alarm from MQTT", zap.String("sn", sn), zap.Error(err))
			return
		}
		// 直接使用原始信封 POST 到 api-server
		if postErr := a.postInternalAlarmRequest(internalAlarmEnvelopeRequest{
			SN:         sn,
			Topic:      "alarm",
			ReceivedAt: receivedAt,
			Envelope:   json.RawMessage(payload),
		}); postErr != nil {
			logger.Error("Failed to post V1 MQTT alarm", zap.String("sn", sn), zap.Error(postErr))
			return
		}
		a.markAlertProcessed(ctx, msgKey)
		logger.Info("MQTT V1 alarm delivered", zap.String("sn", sn), zap.Int("code", alarmData.Code))
		return
	}

	// 旧格式：复用 postInternalAlarm
	alarm := &model.AlarmData{
		SN:         sn,
		ReceivedAt: receivedAt,
	}

	var alarmPayload RawAlarmPayload
	dataMap := payloadMap
	if data, ok := payloadMap["data"].(map[string]interface{}); ok {
		dataMap = data
		if ts, ok := payloadMap["timestamp"]; ok {
			dataMap["timestamp"] = ts
		}
	}
	dataJSON, err := json.Marshal(dataMap)
	if err != nil {
		logger.Warn("Failed to marshal MQTT alarm data", zap.String("sn", sn), zap.Error(err))
		return
	}
	if err := json.Unmarshal(dataJSON, &alarmPayload); err != nil {
		logger.Warn("Failed to parse MQTT alarm fields", zap.String("sn", sn), zap.Error(err))
		return
	}
	if alarmPayload.Timestamp <= 0 {
		alarmPayload.Timestamp = receivedAt.Unix()
	}

	alarm.Code = alarmPayload.Code
	alarm.Level = alarmPayload.Level
	alarm.Message = alarmPayload.Message
	alarm.Count = alarmPayload.Count
	alarm.Timestamp = alarmPayload.Timestamp

	if postErr := a.postInternalAlarm(alarm); postErr != nil {
		logger.Error("Failed to post MQTT alarm", zap.String("sn", sn), zap.Error(postErr))
		return
	}
	a.markAlertProcessed(ctx, msgKey)
	logger.Info("MQTT alarm delivered",
		zap.String("sn", sn),
		zap.Int("code", alarmPayload.Code),
		zap.String("level", alarmPayload.Level))
}
