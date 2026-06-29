package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
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

type parsedMessage struct {
	msg kafka.Message
	raw RawMessage
}

type ProtocolParser struct {
	consumer    *kafka.Reader
	repo        *repository.DeviceRepository
	metaRepo    *repository.MetadataRepository
	rdb         *redis.Client
	hub         *mqtt.Hub
	apiServer   string
	internalKey string
	httpClient  *http.Client

	snModelCache map[string]int32
	snCacheMu    sync.RWMutex
	parseEngine  *ParseRuleEngine

	workerCount int
	msgChan     chan *parsedMessage
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
	apiServer string,
	internalKey string,
) *ProtocolParser {
	return &ProtocolParser{
		consumer: kafka.NewReader(kafka.ReaderConfig{
			Brokers:  brokers,
			Topic:    topic,
			GroupID:  groupID,
			MinBytes: 10e3,
			MaxBytes: 10e6,
		}),
		repo:        repo,
		metaRepo:    metaRepo,
		rdb:         rdb,
		hub:         hub,
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
		snModelCache: make(map[string]int32),
		parseEngine:  NewParseRuleEngine(),
		workerCount:  10,
		msgChan:      make(chan *parsedMessage, 5000),
	}
}

func (p *ProtocolParser) Start(ctx context.Context) {
	for i := 0; i < p.workerCount; i++ {
		go p.worker(ctx, i)
	}
	go p.consume(ctx)
	go p.refreshModelCache(ctx)
}

func (p *ProtocolParser) worker(ctx context.Context, id int) {
	logger.Info("Protocol parser worker started", zap.Int("worker_id", id))
	retryCounts := make(map[string]int)
	const maxRetries = 3
	for {
		select {
		case <-ctx.Done():
			logger.Info("Protocol parser worker stopped", zap.Int("worker_id", id))
			return
		case pm := <-p.msgChan:
			msgKey := fmt.Sprintf("%s:%d:%d", pm.msg.Topic, pm.msg.Partition, pm.msg.Offset)
			if err := p.processMessage(ctx, &pm.raw); err != nil {
				retryCounts[msgKey]++
				if retryCounts[msgKey] >= maxRetries {
					logger.Error("Message processing failed after max retries, skipping",
						zap.String("sn", pm.raw.SN),
						zap.String("msg_type", pm.raw.MsgType),
						zap.Int("retries", retryCounts[msgKey]),
						zap.Error(err))
					_ = p.consumer.CommitMessages(ctx, pm.msg)
					delete(retryCounts, msgKey)
				} else {
					logger.Warn("Message processing failed, will retry on redelivery",
						zap.String("sn", pm.raw.SN),
						zap.String("msg_type", pm.raw.MsgType),
						zap.Int("retry", retryCounts[msgKey]),
						zap.Error(err))
				}
				continue
			}
			delete(retryCounts, msgKey)
			_ = p.consumer.CommitMessages(ctx, pm.msg)
		}
	}
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
	logger.Info("Protocol parser consumer started", zap.Int("workers", p.workerCount))

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

			select {
			case p.msgChan <- &parsedMessage{msg: m, raw: raw}:
			case <-ctx.Done():
				p.consumer.Close()
				logger.Info("Protocol parser consumer stopped")
				return
			}
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
		return p.handleCommandResponse(ctx, raw)
	default:
		return p.handleTelemetry(ctx, raw)
	}
}

// unwrapPayload 处理 payload 可能是 JSON 字符串的情况
// 设备端可能发送 "{\"ac_power\":100}" 而不是 {"ac_power":100}
func unwrapPayload(payload json.RawMessage) (map[string]interface{}, error) {
	var m map[string]interface{}
	if err := json.Unmarshal(payload, &m); err == nil {
		return m, nil
	}

	// 尝试解析为字符串（payload 被多包了一层引号）
	var s string
	if err := json.Unmarshal(payload, &s); err == nil {
		var m2 map[string]interface{}
		if err := json.Unmarshal([]byte(s), &m2); err == nil {
			return m2, nil
		}
	}

	return nil, fmt.Errorf("payload is neither JSON object nor JSON string: %s", string(payload))
}

func (p *ProtocolParser) handleOnline(ctx context.Context, raw *RawMessage) error {
	p.hub.MarkDeviceOnline(raw.SN)
	statusValue := 1

	if p.rdb != nil {
		payloadMap, err := unwrapPayload(raw.Payload)
		if err == nil {
			online, _ := payloadMap["online"].(bool)
			if online {
				p.rdb.HSet(ctx, "device:online", raw.SN, time.Now().Unix())
				statusValue = 1
			} else {
				statusValue = 0
			}
		}
	}

	// 防抖：10 秒内同一设备相同状态不上报，避免状态抖动产生大量通知
	statusKey := "status_report:" + raw.SN
	if p.rdb != nil {
		lastVal, err := p.rdb.Get(ctx, statusKey).Result()
		if err == nil && lastVal == fmt.Sprintf("%d", statusValue) {
			return nil // 状态未变化，跳过上报
		}
		// 如果设备处于故障状态，不发送 status=1 覆盖故障
		if statusValue == 1 {
			faultKey := "fault_report:" + raw.SN
			if faultVal, err := p.rdb.Get(ctx, faultKey).Result(); err == nil && faultVal == "2" {
				return nil
			}
		}
	}

	err := p.postInternal("/api/v1/internal/device-status", map[string]interface{}{
		"sn":     raw.SN,
		"status": statusValue,
	})
	if err == nil && p.rdb != nil {
		p.rdb.Set(ctx, statusKey, fmt.Sprintf("%d", statusValue), 10*time.Second)
	}
	// 如果失败，不设防抖 key，下次会重试
	return nil
}

func (p *ProtocolParser) handleInfo(ctx context.Context, raw *RawMessage) error {
	var info model.DeviceInfo
	if err := json.Unmarshal(raw.Payload, &info); err != nil {
		// 尝试解包字符串形式的 payload
		var s string
		if err2 := json.Unmarshal(raw.Payload, &s); err2 == nil {
			if err3 := json.Unmarshal([]byte(s), &info); err3 != nil {
				return err
			}
		} else {
			return err
		}
	}
	info.SN = raw.SN

	if err := p.postInternal("/api/v1/internal/device-info", info); err != nil {
		return err
	}

	logger.Info("Device info registered",
		zap.String("sn", raw.SN),
		zap.String("model", info.Model))
	return nil
}

func (p *ProtocolParser) postInternal(path string, payload interface{}) error {
	if p.apiServer == "" {
		logger.Warn("API server URL is empty, skipping internal API call",
			zap.String("path", path))
		return nil
	}
	if p.internalKey == "" {
		logger.Warn("Internal API key is empty, API server will likely reject this call",
			zap.String("path", path))
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(1<<uint(attempt-1)*100) * time.Millisecond
			time.Sleep(backoff)
		}

		req, err := http.NewRequest(http.MethodPost, p.apiServer+path, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "application/json")
		if p.internalKey != "" {
			req.Header.Set("X-Internal-Key", p.internalKey)
		}

		resp, err := p.httpClient.Do(req)
		if err != nil {
			lastErr = err
			logger.Warn("internal API call failed, retrying",
				zap.String("path", path),
				zap.Int("attempt", attempt+1),
				zap.Error(err))
			continue
		}
		bodyBytes, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		if resp.StatusCode >= http.StatusInternalServerError {
			lastErr = fmt.Errorf("internal api status %d", resp.StatusCode)
			logger.Warn("internal API returned 5xx, retrying",
				zap.String("path", path),
				zap.Int("attempt", attempt+1),
				zap.Int("status", resp.StatusCode),
				zap.String("response", string(bodyBytes)))
			continue
		}
		if resp.StatusCode >= http.StatusBadRequest {
			logger.Error("internal API returned 4xx error",
				zap.String("path", path),
				zap.Int("status", resp.StatusCode),
				zap.String("response", string(bodyBytes)))
			return fmt.Errorf("internal api status %d: %s", resp.StatusCode, string(bodyBytes))
		}
		return nil
	}
	return fmt.Errorf("internal API call failed after 3 attempts: %w", lastErr)
}

func (p *ProtocolParser) handleTelemetry(ctx context.Context, raw *RawMessage) error {
	p.hub.MarkDeviceOnline(raw.SN)

	if p.rdb != nil {
		p.rdb.HSet(ctx, "device:online", raw.SN, time.Now().Unix())
	}

	// 诊断日志：记录所有进入 handleTelemetry 的消息类型
	logger.Info("handleTelemetry called",
		zap.String("sn", raw.SN),
		zap.String("msg_type", raw.MsgType))

	// 防抖：遥测数据频繁上报，仅在设备从离线恢复为在线时才通知 API Server
	statusKey := "status_report:" + raw.SN
	shouldReport := true
	if p.rdb != nil {
		lastVal, err := p.rdb.Get(ctx, statusKey).Result()
		if err == nil && lastVal == "1" {
			shouldReport = false // 已经上报过在线状态，跳过
		}
		// 如果设备处于故障状态，不发送 status=1 覆盖故障
		faultKey := "fault_report:" + raw.SN
		if faultVal, err := p.rdb.Get(ctx, faultKey).Result(); err == nil && faultVal == "2" {
			shouldReport = false
			logger.Info("Skipping status=1 report due to active fault",
				zap.String("sn", raw.SN),
				zap.String("msg_type", raw.MsgType))
		}
	}
	if shouldReport {
		logger.Info("Reporting status=1 to API server",
			zap.String("sn", raw.SN),
			zap.String("msg_type", raw.MsgType))
		err := p.postInternal("/api/v1/internal/device-status", map[string]interface{}{
			"sn":     raw.SN,
			"status": 1,
		})
		if err == nil && p.rdb != nil {
			p.rdb.Set(ctx, statusKey, "1", 10*time.Second)
		}
		// 如果失败，不设防抖 key，下次会重试
	}

	modelID := p.getModelID(ctx, raw.SN)

	var payloadMap map[string]interface{}
	if modelID > 0 && p.metaRepo != nil {
		meta, ok := p.metaRepo.GetMetadata(modelID)
		if ok && len(meta.Protocols) > 0 {
			adapter := GetAdapterForTopic(meta, raw.MsgType)
			payloadMap = adapter.ParseTopic(raw.MsgType, raw.Payload)
		} else {
			var err error
			payloadMap, err = unwrapPayload(raw.Payload)
			if err != nil {
				return err
			}
		}
	} else {
		var err error
		payloadMap, err = unwrapPayload(raw.Payload)
		if err != nil {
			return err
		}
	}

	if payloadMap == nil {
		logger.Warn("Telemetry payload parsed to nil, data will not be stored",
			zap.String("sn", raw.SN),
			zap.String("msg_type", raw.MsgType),
			zap.Int("payload_len", len(raw.Payload)))
		return nil
	}

	var parsedPayload map[string]interface{}
	if modelID > 0 && p.metaRepo != nil {
		parsedPayload = p.applyFieldMapping(modelID, payloadMap)
	} else {
		parsedPayload = payloadMap
	}

	// data/status 故障检测：检查 state 和 fault_code，主动上报设备故障状态
	if raw.MsgType == "data/status" && parsedPayload != nil {
		// 添加诊断日志（Info 级别确保可见）
		logger.Info("data/status payload received",
			zap.String("sn", raw.SN),
			zap.Any("payload", parsedPayload))

		// 处理可能的嵌套格式：{"data": {"state": "fault", ...}, "timestamp": ...}
		statusData := parsedPayload
		if data, ok := parsedPayload["data"].(map[string]interface{}); ok {
			statusData = data
			logger.Info("Using nested data field for status",
				zap.String("sn", raw.SN),
				zap.Any("data", data))
		}

		isFault := false
		if state, ok := statusData["state"].(string); ok && state == "fault" {
			isFault = true
			logger.Info("Fault detected via state field",
				zap.String("sn", raw.SN),
				zap.String("state", state))
		}
		if !isFault {
			if fc, ok := statusData["fault_code"]; ok {
				logger.Info("fault_code found in payload",
					zap.String("sn", raw.SN),
					zap.Any("fault_code", fc),
					zap.String("type", fmt.Sprintf("%T", fc)))
				switch v := fc.(type) {
				case float64:
					isFault = v != 0
				case int:
					isFault = v != 0
				case int64:
					isFault = v != 0
				}
				if isFault {
					logger.Info("Fault detected via fault_code field",
						zap.String("sn", raw.SN),
						zap.Any("fault_code", fc))
				}
			} else {
				logger.Info("fault_code not found in payload",
					zap.String("sn", raw.SN),
					zap.Any("available_keys", getKeys(statusData)))
			}
		}

		faultKey := "fault_report:" + raw.SN
		if isFault {
			shouldReportFault := true
			if p.rdb != nil {
				// 防抖检查：10 秒内不重复上报故障状态
				lastVal, err := p.rdb.Get(ctx, faultKey).Result()
				if err == nil && lastVal == "2" {
					shouldReportFault = false
				}
				// 始终刷新故障标记 TTL，防止其他遥测数据的 status=1 覆盖故障状态
				p.rdb.Set(ctx, faultKey, "2", 15*time.Second)
			}
			if shouldReportFault {
				logger.Info("Reporting fault status to API server",
					zap.String("sn", raw.SN),
					zap.Int("status", 2))
				p.postInternal("/api/v1/internal/device-status", map[string]interface{}{
					"sn":     raw.SN,
					"status": 2,
				})
			}
		} else {
			// 设备恢复正常，清除故障防抖 key，确保下次故障能及时上报
			logger.Info("Device status normal, clearing fault key",
				zap.String("sn", raw.SN))
			if p.rdb != nil {
				p.rdb.Del(ctx, faultKey)
			}
		}
	}

	// 构建数据库存储数据（保留带前缀字段用于查询兼容）
	topicCategory := p.getTopicCategory(raw.MsgType)
	dataToStore := make(map[string]interface{})
	for k, v := range parsedPayload {
		dataToStore[k] = v
	}
	if topicCategory != "" {
		prefix := topicCategory + "_"
		for k, v := range payloadMap {
			if !strings.HasPrefix(k, prefix) && !strings.HasPrefix(k, "pv_") && !strings.HasPrefix(k, "mppt_") {
				dataToStore[prefix+k] = v
			}
		}
	}

	// 构建 Redis 缓存数据（只保留原始字段，不添加带前缀的重复字段）
	cachePayload := make(map[string]interface{})
	for k, v := range parsedPayload {
		cachePayload[k] = v
	}

	topic := raw.MsgType
	if topic == "" {
		topic = "data/unknown"
	}

	req := map[string]interface{}{
		"sn":    raw.SN,
		"topic": topic,
		"data":  dataToStore,
	}

	var timestamp int64
	if ts, ok := payloadMap["timestamp"]; ok {
		switch v := ts.(type) {
		case int64:
			timestamp = v
		case int:
			timestamp = int64(v)
		case float64:
			timestamp = int64(v)
		}
	}
	if timestamp <= 0 {
		timestamp = time.Now().Unix()
	}
	req["timestamp"] = timestamp

	if topic == "data/energy" {
		var energy model.EnergyData
		// 处理嵌套格式 {"energy": {"data": {...}, "timestamp": ...}}
		var dataToUnmarshal map[string]interface{}
		if nestedData, ok := payloadMap["data"].(map[string]interface{}); ok {
			dataToUnmarshal = nestedData
		} else {
			dataToUnmarshal = payloadMap
		}
		rawBytes, _ := json.Marshal(dataToUnmarshal)
		if err := json.Unmarshal(rawBytes, &energy); err == nil {
			req["daily_pv"] = energy.DailyPV
			req["total_pv"] = energy.TotalPV
			req["daily_charge"] = energy.DailyCharge
			req["total_charge"] = energy.TotalCharge
			req["daily_discharge"] = energy.DailyDischarge
			req["total_discharge"] = energy.TotalDischarge
			req["daily_load"] = energy.DailyLoad
			req["total_load"] = energy.TotalLoad
			req["runtime_hours"] = energy.RuntimeHours
		}
		stationID, _ := p.repo.GetStationIDBySN(ctx, raw.SN)
		if stationID > 0 {
			req["station_id"] = stationID
		}
	}

	if err := p.postInternal("/api/v1/internal/device-data", req); err != nil {
		logger.Error("Failed to post telemetry data to API server",
			zap.String("sn", raw.SN),
			zap.String("topic", topic),
			zap.Error(err))
		return err
	}

	if err := p.cacheRealtime(ctx, raw.SN, cachePayload, raw.MsgType); err != nil {
		logger.Debug("Redis cache failed", zap.String("sn", raw.SN), zap.Error(err))
	}

	return nil
}

func (p *ProtocolParser) applyFieldMapping(modelID int32, payload map[string]interface{}) map[string]interface{} {
	fields := p.metaRepo.GetFieldsByModelID(modelID)
	if len(fields) == 0 {
		return payload
	}

	result := make(map[string]interface{}, len(payload))
	for k, v := range payload {
		result[k] = v
	}

	for _, field := range fields {
		val, exists := payload[field.FieldKey]

		// 如果直接查找失败，尝试去掉前缀后查找
		if !exists {
			// 去掉常见的前缀：ac_, batt_, pv_, sys_, energy_, load_, meter_
			prefixes := []string{"ac_", "batt_", "pv_", "sys_", "energy_", "load_", "meter_"}
			for _, prefix := range prefixes {
				if strings.HasPrefix(field.FieldKey, prefix) {
					simpleKey := strings.TrimPrefix(field.FieldKey, prefix)
					if v, ok := payload[simpleKey]; ok {
						val = v
						exists = true
						break
					}
				}
			}
		}

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

func (p *ProtocolParser) handleCommandResponse(ctx context.Context, raw *RawMessage) error {
	var resp model.CommandResponse
	if err := json.Unmarshal(raw.Payload, &resp); err != nil {
		return nil
	}

	return p.postInternal("/api/v1/internal/device-cmd-status", map[string]interface{}{
		"sn":        raw.SN,
		"result":    resp.Result,
		"cmd":       resp.Cmd,
		"message":   resp.Message,
		"timestamp": resp.Timestamp,
	})
}

func (p *ProtocolParser) cacheRealtime(ctx context.Context, sn string, payload map[string]interface{}, msgType string) error {
	if p.rdb == nil {
		return nil
	}

	topicCategory := p.getTopicCategory(msgType)

	cacheKey := "realtime:latest:" + sn
	existing, err := p.rdb.Get(ctx, cacheKey).Bytes()
	var rt map[string]interface{}
	if err == nil {
		_ = json.Unmarshal(existing, &rt)
	}
	if rt == nil {
		rt = make(map[string]interface{})
	}

	// 将 payload 存入嵌套对象（只存原始字段，不添加带前缀的重复字段）
	if topicCategory != "" {
		existingNested := make(map[string]interface{})
		if v, ok := rt[topicCategory]; ok {
			if nestedMap, ok := v.(map[string]interface{}); ok {
				existingNested = nestedMap
			}
		}
		for k, v := range payload {
			existingNested[k] = v
		}
		rt[topicCategory] = existingNested
	} else {
		for k, v := range payload {
			rt[k] = v
		}
	}

	pipe := p.rdb.Pipeline()
	// 存储单个字段到 Redis（用于按字段查询和订阅）
	for k, v := range payload {
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

func (p *ProtocolParser) getTopicCategory(msgType string) string {
	switch {
	case msgType == "data/ac":
		return "ac"
	case msgType == "data/battery":
		return "batt"
	case msgType == "data/pv":
		return "pv"
	case msgType == "data/status":
		return "sys"
	case msgType == "data/energy":
		return "energy"
	case msgType == "data/cells":
		return "cells"
	case msgType == "info" || msgType == "data/info":
		return "info"
	case msgType == "data/dc" || msgType == "data/ldc":
		return "dc"
	case msgType == "data/grid":
		return "grid"
	case msgType == "data/load":
		return "load"
	case msgType == "data/eps":
		return "eps"
	case msgType == "data/meter":
		return "meter"
	default:
		return ""
	}
}
