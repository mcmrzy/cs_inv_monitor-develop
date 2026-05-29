package service

import (
	"context"
	"encoding/json"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/internal/repository"
	"inv-device-server/pkg/logger"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type AlertConsumer struct {
	consumer *kafka.Reader
	repo     *repository.DeviceRepository
}

type RawAlertMessage struct {
	SN         string                 `json:"sn"`
	Source     string                 `json:"source"`
	FaultCode  int                    `json:"fault_code"`
	FaultDesc  string                 `json:"fault_desc"`
	ReceivedAt string                 `json:"received_at"`
	Payload    map[string]interface{} `json:"payload"`
}

func NewAlertConsumer(brokers []string, topic string, groupID string, repo *repository.DeviceRepository) *AlertConsumer {
	return &AlertConsumer{
		consumer: kafka.NewReader(kafka.ReaderConfig{
			Brokers:   brokers,
			Topic:     topic,
			GroupID:   groupID,
			MinBytes:  10e3,
			MaxBytes:  10e6,
		}),
		repo: repo,
	}
}

func (a *AlertConsumer) Start(ctx context.Context) {
	go a.consume(ctx)
}

func (a *AlertConsumer) consume(ctx context.Context) {
	logger.Info("Alert consumer started")

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

			var raw RawAlertMessage
			if err := json.Unmarshal(m.Value, &raw); err != nil {
				logger.Error("Failed to unmarshal alert", zap.Error(err))
				if err := a.consumer.CommitMessages(ctx, m); err != nil {
					logger.Warn("Failed to commit alert message", zap.Error(err))
				}
				continue
			}

			if raw.SN == "" {
				if err := a.consumer.CommitMessages(ctx, m); err != nil {
					logger.Warn("Failed to commit alert message", zap.Error(err))
				}
				continue
			}

			alarm := &model.AlarmData{
				SN:         raw.SN,
				Source:     raw.Source,
				FaultCode:  raw.FaultCode,
				FaultDesc:  raw.FaultDesc,
				ReceivedAt: time.Now(),
				Trigger:    raw.Payload,
			}

			if err := a.repo.InsertAlarm(ctx, alarm); err != nil {
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
	}
}
