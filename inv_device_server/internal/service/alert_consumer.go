package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/pkg/logger"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type AlertConsumer struct {
	consumer    *kafka.Reader
	apiServer   string
	internalKey string
	httpClient  *http.Client
	workerCount int
	msgChan     chan kafka.Message
}

type RawAlertMessage struct {
	SN        string      `json:"sn"`
	Source    string      `json:"source"`
	MsgType   string      `json:"msg_type"`
	Payload   interface{} `json:"payload"`
	ReceivedAt string     `json:"received_at"`
}

// 新告警格式 (MQTT payload)
type RawAlarmPayload struct {
	Code      int                    `json:"code"`
	Level     string                 `json:"level"`
	Message   string                 `json:"message"`
	Count     int                    `json:"count"`
	Alarms    []map[string]interface{} `json:"alarms"`
	Timestamp int64                  `json:"timestamp"`
}

func NewAlertConsumer(brokers []string, topic string, groupID string, apiServer string, internalKey string) *AlertConsumer {
	return &AlertConsumer{
		consumer: kafka.NewReader(kafka.ReaderConfig{
			Brokers:  brokers,
			Topic:    topic,
			GroupID:  groupID,
			MinBytes: 10e3,
			MaxBytes: 10e6,
		}),
		apiServer:   strings.TrimRight(apiServer, "/"),
		internalKey: internalKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 50,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		workerCount: 5,
		msgChan:     make(chan kafka.Message, 2000),
	}
}

func (a *AlertConsumer) Start(ctx context.Context) {
	for i := 0; i < a.workerCount; i++ {
		go a.worker(ctx, i)
	}
	go a.consume(ctx)
}

func (a *AlertConsumer) worker(ctx context.Context, id int) {
	logger.Info("Alert consumer worker started", zap.Int("worker_id", id))
	for {
		select {
		case <-ctx.Done():
			logger.Info("Alert consumer worker stopped", zap.Int("worker_id", id))
			return
		case m := <-a.msgChan:
			a.processAlert(ctx, m)
		}
	}
}

func (a *AlertConsumer) consume(ctx context.Context) {
	logger.Info("Alert consumer started", zap.Int("workers", a.workerCount))

	for {
		select {
		case <-ctx.Done():
			a.consumer.Close()
			logger.Info("Alert consumer stopped")
			return
		default:
			m, err := a.consumer.FetchMessage(ctx)
			if err != nil {
				logger.Error("Kafka fetch alert error", zap.Error(err))
				time.Sleep(100 * time.Millisecond)
				continue
			}

			select {
			case a.msgChan <- m:
			case <-ctx.Done():
				a.consumer.Close()
				logger.Info("Alert consumer stopped")
				return
			}
		}
	}
}

func (a *AlertConsumer) processAlert(ctx context.Context, m kafka.Message) {
	var raw RawAlertMessage
	if err := json.Unmarshal(m.Value, &raw); err != nil {
		logger.Error("Failed to unmarshal alert", zap.Error(err), zap.String("raw", string(m.Value)))
		if err := a.consumer.CommitMessages(ctx, m); err != nil {
			logger.Warn("Failed to commit alert message", zap.Error(err))
		}
		return
	}

	if raw.SN == "" {
		if err := a.consumer.CommitMessages(ctx, m); err != nil {
			logger.Warn("Failed to commit alert message", zap.Error(err))
		}
		return
	}

	// 将 payload 统一转为 map
	var payloadMap map[string]interface{}
	switch v := raw.Payload.(type) {
	case map[string]interface{}:
		payloadMap = v
	case string:
		json.Unmarshal([]byte(v), &payloadMap)
	}

	// 空 payload 或空对象 → 告警清除
	if len(payloadMap) == 0 {
		logger.Info("Device alarm cleared (empty payload)", zap.String("sn", raw.SN))
		alarm := &model.AlarmData{
			SN:         raw.SN,
			Code:       0,
			Level:      "normal",
			Message:    "故障恢复，系统正常",
			Count:      0,
			Alarms:     nil,
			ReceivedAt: time.Now(),
		}
		if err := a.postInternalAlarm(alarm); err != nil {
			logger.Error("Failed to post alarm clear", zap.String("sn", raw.SN), zap.Error(err))
		}
		if err := a.consumer.CommitMessages(ctx, m); err != nil {
			logger.Warn("Failed to commit alert message", zap.Error(err))
		}
		return
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
	dataJSON, _ := json.Marshal(dataMap)
	json.Unmarshal(dataJSON, &alarmPayload)

	// code=0 且 level="normal" → 告警清除
	if alarmPayload.Code == 0 && alarmPayload.Level == "normal" {
		logger.Info("Device alarm cleared (code=0)", zap.String("sn", raw.SN))
		alarm := &model.AlarmData{
			SN:         raw.SN,
			Code:       0,
			Level:      "normal",
			Message:    "故障恢复，系统正常",
			Count:      0,
			Alarms:     nil,
			Timestamp:  alarmPayload.Timestamp,
			ReceivedAt: time.Now(),
		}
		if err := a.postInternalAlarm(alarm); err != nil {
			logger.Error("Failed to post alarm clear", zap.String("sn", raw.SN), zap.Error(err))
		}
		if err := a.consumer.CommitMessages(ctx, m); err != nil {
			logger.Warn("Failed to commit alert message", zap.Error(err))
		}
		return
	}

	// 有 alarms 数组时，逐个上报
	if len(alarmPayload.Alarms) > 0 {
		for _, item := range alarmPayload.Alarms {
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
				ReceivedAt: time.Now(),
			}
			if err := a.postInternalAlarm(alarm); err != nil {
				logger.Error("Failed to post alarm item",
					zap.String("sn", raw.SN),
					zap.Int("code", code),
					zap.Error(err))
			} else {
				logger.Info("Alarm item recorded",
					zap.String("sn", raw.SN),
					zap.Int("code", code),
					zap.String("level", level),
					zap.String("message", message))
			}
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
			ReceivedAt: time.Now(),
		}
		if err := a.postInternalAlarm(alarm); err != nil {
			logger.Error("Failed to post alarm",
				zap.String("sn", raw.SN),
				zap.Int("code", alarmPayload.Code),
				zap.Error(err))
		} else {
			logger.Info("Alarm recorded",
				zap.String("sn", raw.SN),
				zap.Int("code", alarmPayload.Code),
				zap.String("level", alarmPayload.Level),
				zap.String("message", alarmPayload.Message))
		}
	}

	if err := a.consumer.CommitMessages(ctx, m); err != nil {
		logger.Warn("Failed to commit alert message", zap.Error(err))
	}
}

func (a *AlertConsumer) postInternalAlarm(alarm *model.AlarmData) error {
	if a.apiServer == "" {
		return nil
	}

	body, err := json.Marshal(alarm)
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
		return fmt.Errorf("internal api status %d", resp.StatusCode)
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
