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
	SN         string      `json:"sn"`
	Source     string      `json:"source"`
	FaultCode  int         `json:"fault_code"`
	FaultDesc  string      `json:"fault_desc"`
	ReceivedAt string      `json:"received_at"`
	Payload    interface{} `json:"payload"`
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

	// 从 payload 中提取设备实际报告的故障码和描述
	// bridge 包装格式: {"sn":"...", "payload":{"data":{"code":1001,"message":"...",...},"timestamp":...}}
	// 实际告警字段嵌套在 payload.data 内
	faultCode := raw.FaultCode
	faultDesc := raw.FaultDesc

	// 将 payload 统一转为 map（可能是 map 或 JSON 字符串）
	var payloadMap map[string]interface{}
	switch v := raw.Payload.(type) {
	case map[string]interface{}:
		payloadMap = v
	case string:
		json.Unmarshal([]byte(v), &payloadMap)
	}

	if payloadMap != nil {
		// 先从 payload.data 中提取（bridge 的包装格式）
		var alarmPayload map[string]interface{}
		if data, ok := payloadMap["data"]; ok {
			if dataMap, ok := data.(map[string]interface{}); ok {
				alarmPayload = dataMap
			}
		}
		// 如果 payload.data 不存在，则直接用 payload 本身
		if alarmPayload == nil {
			alarmPayload = payloadMap
		}
		if code, ok := alarmPayload["code"]; ok {
			if codeNum, ok := toInt(code); ok {
				faultCode = codeNum
			}
		}
		if msg, ok := alarmPayload["message"]; ok {
			if msgStr, ok := msg.(string); ok && msgStr != "" {
				faultDesc = msgStr
			}
		}
	}

	alarm := &model.AlarmData{
		SN:         raw.SN,
		Source:     raw.Source,
		FaultCode:  faultCode,
		FaultDesc:  faultDesc,
		ReceivedAt: time.Now(),
		Trigger:    payloadMap,
	}

	if err := a.postInternalAlarm(alarm); err != nil {
		logger.Error("Failed to insert alarm",
			zap.String("sn", raw.SN),
			zap.Int("fault_code", faultCode),
			zap.String("fault_desc", faultDesc),
			zap.Error(err))
	} else {
		logger.Warn("Alarm recorded from Kafka",
			zap.String("sn", raw.SN),
			zap.Int("fault_code", faultCode),
			zap.String("fault_desc", faultDesc))
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
