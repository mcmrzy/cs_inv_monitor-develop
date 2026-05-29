package service

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/internal/mqtt"
	"inv-device-server/internal/repository"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type ProtocolParser struct {
	consumer  *kafka.Reader
	repo      *repository.DeviceRepository
	metaRepo  *repository.MetadataRepository
	rdb       *redis.Client
	hub       *mqtt.Hub

	snModelCache map[string]int32
	snCacheMu    sync.RWMutex
	parseEngine  *ParseRuleEngine
}

type RawMessage struct {
	SN         string          `json:"sn"`
	ClientID   string          `json:"client_id"`
	MsgType    string          `json:"msg_type"`
	Payload    json.RawMessage `json:"payload"`
	ReceivedAt string          `json:"received_at"`
}

func NewProtocolParser(
	brokers []string, topic string, groupID string,
	repo *repository.DeviceRepository,
	metaRepo *repository.MetadataRepository,
	rdb *redis.Client,
	hub *mqtt.Hub,
) *ProtocolParser {
	return &ProtocolParser{
		consumer: kafka.NewReader(kafka.ReaderConfig{
			Brokers:  brokers,
			Topic:    topic,
			GroupID:  groupID,
			MinBytes: 10e3,
			MaxBytes: 10e6,
		}),
		repo:         repo,
		metaRepo:     metaRepo,
		rdb:          rdb,
		hub:          hub,
		snModelCache: make(map[string]int32),
		parseEngine:  NewParseRuleEngine(),
	}
}

func (p *ProtocolParser) Start(ctx context.Context) {
	go p.consume(ctx)
	go p.refreshModelCache(ctx)
}

func (p *ProtocolParser) refreshModelCache(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			p.loadAllDeviceModels(ctx)
		}
	}
}

func (p *ProtocolParser) loadAllDeviceModels(ctx context.Context) {
	devices, err := p.repo.GetAllDevices(ctx)
	if err != nil {
		logger.Error("Failed to load device models for cache", zap.Error(err))
		return
	}

	p.snCacheMu.Lock()
	defer p.snCacheMu.Unlock()

	for _, d := range devices {
		if d.SN != "" && d.ModelID > 0 {
			p.snModelCache[d.SN] = d.ModelID
		}
	}

	logger.Info("Device model cache loaded", zap.Int("count", len(p.snModelCache)))
}

func (p *ProtocolParser) getModelID(ctx context.Context, sn string) int32 {
	p.snCacheMu.RLock()
	if modelID, ok := p.snModelCache[sn]; ok {
		p.snCacheMu.RUnlock()
		return modelID
	}
	p.snCacheMu.RUnlock()

	modelID, _ := p.repo.GetDeviceModelID(ctx, sn)
	if modelID > 0 {
		p.snCacheMu.Lock()
		p.snModelCache[sn] = modelID
		p.snCacheMu.Unlock()
	}
	return modelID
}

func (p *ProtocolParser) consume(ctx context.Context) {
	logger.Info("Protocol parser consumer started")

	for {
		select {
		case <-ctx.Done():
			p.consumer.Close()
			logger.Info("Protocol parser consumer stopped")
			return
		default:
			m, err := p.consumer.FetchMessage(ctx)
			if err != nil {
				logger.Error("Kafka fetch message error", zap.Error(err))
				time.Sleep(100 * time.Millisecond)
				continue
			}

			var raw RawMessage
			if err := json.Unmarshal(m.Value, &raw); err != nil {
				logger.Error("Failed to unmarshal raw message",
					zap.Error(err),
					zap.String("topic", m.Topic),
					zap.Int64("offset", m.Offset))
				_ = p.consumer.CommitMessages(ctx, m)
				continue
			}

			if raw.SN == "" {
				_ = p.consumer.CommitMessages(ctx, m)
				continue
			}

			if err := p.processMessage(ctx, &raw); err != nil {
				logger.Error("Failed to process raw message",
					zap.String("sn", raw.SN),
					zap.String("msg_type", raw.MsgType),
					zap.Error(err))
			}

			_ = p.consumer.CommitMessages(ctx, m)
		}
	}
}

func (p *ProtocolParser) processMessage(ctx context.Context, raw *RawMessage) error {
	if len(raw.Payload) == 0 || string(raw.Payload) == "null" {
		return nil
	}

	switch raw.MsgType {
	case "status", "online":
		return p.handleOnline(ctx, raw)
	case "info":
		return p.handleInfo(ctx, raw)
	case "cmd", "cmd/response":
		return nil
	default:
		return p.handleTelemetry(ctx, raw)
	}
}

func (p *ProtocolParser) handleOnline(ctx context.Context, raw *RawMessage) error {
	p.hub.MarkDeviceOnline(raw.SN)

	if p.rdb != nil {
		var status struct {
			Online bool `json:"online"`
		}
		if err := json.Unmarshal(raw.Payload, &status); err == nil && status.Online {
			p.rdb.HSet(ctx, "device:online", raw.SN, time.Now().Unix())
		}
	}
	return nil
}

func (p *ProtocolParser) handleInfo(ctx context.Context, raw *RawMessage) error {
	var info model.DeviceInfo
	if err := json.Unmarshal(raw.Payload, &info); err != nil {
		return err
	}
	info.SN = raw.SN

	if err := p.repo.UpsertDeviceInfo(ctx, &info); err != nil {
		return err
	}

	logger.Info("Device info registered",
		zap.String("sn", raw.SN),
		zap.String("model", info.Model))
	return nil
}

func (p *ProtocolParser) handleTelemetry(ctx context.Context, raw *RawMessage) error {
	p.hub.MarkDeviceOnline(raw.SN)

	modelID := p.getModelID(ctx, raw.SN)

	var payloadMap map[string]interface{}
	if modelID > 0 && p.metaRepo != nil {
		meta, ok := p.metaRepo.GetMetadata(modelID)
		if ok && len(meta.Protocols) > 0 {
			adapter := GetAdapterForTopic(meta, raw.MsgType)
			payloadMap = adapter.ParseTopic(raw.MsgType, raw.Payload)
		} else {
			if err := json.Unmarshal(raw.Payload, &payloadMap); err != nil {
				return err
			}
		}
	} else {
		if err := json.Unmarshal(raw.Payload, &payloadMap); err != nil {
			return err
		}
	}

	if payloadMap == nil {
		return nil
	}

	var parsedPayload map[string]interface{}
	if modelID > 0 && p.metaRepo != nil {
		parsedPayload = p.applyFieldMapping(modelID, payloadMap)
	} else {
		parsedPayload = payloadMap
	}

	metricsJSON, err := json.Marshal(parsedPayload)
	if err != nil {
		return err
	}

	topic := raw.MsgType
	if topic == "" {
		topic = "data/unknown"
	}

	if err := p.repo.InsertTelemetry(ctx, raw.SN, topic, metricsJSON); err != nil {
		return err
	}

	if err := p.cacheRealtime(ctx, raw.SN, parsedPayload, raw.MsgType); err != nil {
		logger.Debug("Redis cache failed", zap.String("sn", raw.SN), zap.Error(err))
	}

	if raw.MsgType == "data/energy" {
		p.handleEnergyAggregation(ctx, raw.SN, payloadMap)
	}

	return nil
}

func (p *ProtocolParser) applyFieldMapping(modelID int32, payload map[string]interface{}) map[string]interface{} {
	fields := p.metaRepo.GetFieldsByModelID(modelID)
	if len(fields) == 0 {
		return payload
	}

	result := make(map[string]interface{}, len(fields))
	for _, field := range fields {
		val, exists := payload[field.FieldKey]
		if !exists {
			continue
		}

		if field.ParseRule != "" {
			val = p.parseEngine.Apply(field.ParseRule, val)
		}

		val = CastByFieldType(field.FieldType, val)
		result[field.FieldKey] = val
	}

	return result
}

func (p *ProtocolParser) handleEnergyAggregation(ctx context.Context, sn string, payload map[string]interface{}) {
	dailyPV, _ := payload["daily_pv"].(float64)

	var data model.EnergyData
	rawBytes, _ := json.Marshal(payload)
	if err := json.Unmarshal(rawBytes, &data); err == nil {
		_ = p.repo.UpsertDayData(ctx, sn, &data)
	}

	stationID, _ := p.repo.GetStationIDBySN(ctx, sn)
	if stationID > 0 && dailyPV > 0 {
		_ = p.repo.UpsertStationDayData(ctx, stationID, dailyPV, 0)
	}
}

func (p *ProtocolParser) cacheRealtime(ctx context.Context, sn string, payload map[string]interface{}, msgType string) error {
	if p.rdb == nil {
		return nil
	}

	cacheKey := "realtime:latest:" + sn
	existing, err := p.rdb.Get(ctx, cacheKey).Bytes()
	var rt map[string]interface{}
	if err == nil {
		_ = json.Unmarshal(existing, &rt)
	}
	if rt == nil {
		rt = make(map[string]interface{})
	}

	pipe := p.rdb.Pipeline()
	for k, v := range payload {
		rt[k] = v
		fieldBytes, _ := json.Marshal(map[string]interface{}{"v": v, "ts": time.Now().Unix()})
		pipe.Set(ctx, fmt.Sprintf("realtime:latest:%s:%s", sn, k), fieldBytes, 120*time.Second)
	}
	rt["_sn"] = sn
	rt["_msg_type"] = msgType
	rt["_updated_at"] = time.Now().Format(time.RFC3339)

	mergedBytes, _ := json.Marshal(rt)
	pipe.Set(ctx, cacheKey, mergedBytes, 120*time.Second)

	if _, err := pipe.Exec(ctx); err != nil {
		return err
	}

	pubChannel := "realtime:channel:" + sn
	_ = p.rdb.Publish(ctx, pubChannel, string(mergedBytes)).Err()

	return nil
}
