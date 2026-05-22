package mqtt

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const (
	streamKey       = "device:stream"
	deadStreamKey   = "device:stream:dead"
	consumerGroup   = "inv-group"
	consumerName    = "inv-consumer"
	maxRetries      = 3
	blockTimeout    = 5 * time.Second
	maxStreamLen    = 100000
)

type StreamConsumer struct {
	rdb       *redis.Client
	hub       *Hub
	ctx       context.Context
	cancel    context.CancelFunc
}

func NewStreamConsumer(rdb *redis.Client, hub *Hub) *StreamConsumer {
	ctx, cancel := context.WithCancel(context.Background())
	return &StreamConsumer{
		rdb:    rdb,
		hub:    hub,
		ctx:    ctx,
		cancel: cancel,
	}
}

func (sc *StreamConsumer) Start() error {
	if err := sc.initGroup(); err != nil {
		return fmt.Errorf("init consumer group: %w", err)
	}

	go sc.consume()
	logger.Info("Redis Streams consumer started",
		zap.String("stream", streamKey),
		zap.String("group", consumerGroup))
	return nil
}

func (sc *StreamConsumer) Stop() {
	sc.cancel()
	logger.Info("Redis Streams consumer stopped")
}

func (sc *StreamConsumer) initGroup() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err := sc.rdb.XGroupCreateMkStream(ctx, streamKey, consumerGroup, "0").Err()
	if err != nil && err.Error() != "BUSYGROUP Consumer Group name already exists" {
		return err
	}

	err = sc.rdb.XGroupCreateMkStream(ctx, deadStreamKey, consumerGroup, "0").Err()
	if err != nil && err.Error() != "BUSYGROUP Consumer Group name already exists" {
		logger.Warn("Dead stream group init warning", zap.Error(err))
	}

	return nil
}

func (sc *StreamConsumer) consume() {
	for {
		select {
		case <-sc.ctx.Done():
			return
		default:
		}

		ctx, cancel := context.WithTimeout(sc.ctx, blockTimeout+2*time.Second)
		streams, err := sc.rdb.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    consumerGroup,
			Consumer: consumerName,
			Streams:  []string{streamKey, ">"},
			Count:    10,
			Block:    blockTimeout,
		}).Result()
		cancel()

		if err != nil {
			if err != redis.Nil && sc.ctx.Err() == nil {
				logger.Error("Stream read error", zap.Error(err))
				time.Sleep(1 * time.Second)
			}
			continue
		}

		for _, stream := range streams {
			for _, msg := range stream.Messages {
				sc.processMessage(msg)
			}
		}
	}
}

func (sc *StreamConsumer) processMessage(msg redis.XMessage) {
	var rt model.DeviceRealtime
	if err := json.Unmarshal([]byte(msg.Values["data"].(string)), &rt); err != nil {
		logger.Warn("Failed to unmarshal stream message", zap.Error(err))
		sc.ack(msg.ID)
		return
	}

	sn := rt.DeviceSN
	if sn == "" {
		sc.ack(msg.ID)
		return
	}

	sc.hub.MarkSeen(sn)

	sc.hub.realtimeMux.Lock()
	existing := sc.hub.getOrCreateRealtimeLocked(sn)
	sc.mergeRealtime(existing, &rt)
	existing.UpdatedAt = time.Now()
	sc.hub.realtimeMux.Unlock()

	sendToDataChan(sc.hub, existing, sn)
	sc.ack(msg.ID)
}

func (sc *StreamConsumer) mergeRealtime(existing, incoming *model.DeviceRealtime) {
	if incoming.OnlineStatus != nil {
		existing.OnlineStatus = incoming.OnlineStatus
	}
	if incoming.AC != nil {
		existing.AC = incoming.AC
	}
	if incoming.Battery != nil {
		existing.Battery = incoming.Battery
	}
	if incoming.PV != nil {
		existing.PV = incoming.PV
	}
	if incoming.SysStatus != nil {
		existing.SysStatus = incoming.SysStatus
	}
	if incoming.Energy != nil {
		existing.Energy = incoming.Energy
	}
	if incoming.Cells != nil {
		existing.Cells = incoming.Cells
	}
}

func (sc *StreamConsumer) ack(msgID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := sc.rdb.XAck(ctx, streamKey, consumerGroup, msgID).Err(); err != nil {
		logger.Warn("Stream ack failed", zap.String("msg_id", msgID), zap.Error(err))
	}
}

func (sc *StreamConsumer) moveToDead(msg redis.XMessage) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	pipe := sc.rdb.Pipeline()
	pipe.XAdd(ctx, &redis.XAddArgs{
		Stream: deadStreamKey,
		Values: msg.Values,
	})
	pipe.XAck(ctx, streamKey, consumerGroup, msg.ID)
	pipe.XDel(ctx, streamKey, msg.ID)
	_, err := pipe.Exec(ctx)
	if err != nil {
		logger.Error("Move to dead stream failed", zap.String("msg_id", msg.ID), zap.Error(err))
	} else {
		logger.Warn("Message moved to dead stream", zap.String("msg_id", msg.ID))
	}
}

func (sc *StreamConsumer) PendingCount() (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	result, err := sc.rdb.XPending(ctx, streamKey, consumerGroup).Result()
	if err != nil {
		return 0, err
	}
	return result.Count, nil
}

func PublishToStream(rdb *redis.Client, data []byte, sn string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	return rdb.XAdd(ctx, &redis.XAddArgs{
		Stream: streamKey,
		MaxLen: maxStreamLen,
		Approx: true,
		Values: map[string]interface{}{
			"sn":   sn,
			"data": string(data),
		},
	}).Err()
}
