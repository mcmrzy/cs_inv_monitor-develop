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
	SN         string                 `json:"sn"`
	Source     string                 `json:"source"`
	FaultCode  int                    `json:"fault_code"`
	FaultDesc  string                 `json:"fault_desc"`
	ReceivedAt string                 `json:"received_at"`
	Payload    map[string]interface{} `json:"payload"`
}

func NewAlertConsumer(brokers []string, topic string, groupID string, apiServer string, internalKey string) *AlertConsumer {
	return &AlertConsumer{
		consumer: kafka.NewReader(kafka.ReaderConfig{
			Brokers:   brokers,
			Topic:     topic,
			GroupID:   groupID,
			MinBytes:  10e3,
			MaxBytes:  10e6,
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
		logger.Error("Failed to unmarshal alert", zap.Error(err))
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

	alarm := &model.AlarmData{
		SN:         raw.SN,
		Source:     raw.Source,
		FaultCode:  raw.FaultCode,
		FaultDesc:  raw.FaultDesc,
		ReceivedAt: time.Now(),
		Trigger:    raw.Payload,
	}

	if err := a.postInternalAlarm(alarm); err != nil {
		logger.Error("Failed to insert alarm",
			zap.String("sn", raw.SN),
			zap.Error(err))
	} else {
		logger.Warn("Alarm recorded from Kafka",
			zap.String("sn", raw.SN),
			zap.String("source", raw.Source),
			zap.String("desc", raw.FaultDesc))
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
