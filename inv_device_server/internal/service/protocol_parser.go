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

	snModelCache  map[string]int32
	snCacheMu     sync.RWMutex
	parseEngine   *ParseRuleEngine
	stateManager  *DeviceStateManager // 集中式状态管理器

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
		stateManager: NewDeviceStateManager(rdb, apiServer, internalKey),
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
	case "info", "data/info":
		return p.handleInfo(ctx, raw)
	case "cmd", "cmd/response", "cmd_result":
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
	// 解析设备上报的状态
	online := true
	if p.rdb != nil {
		payloadMap, err := unwrapPayload(raw.Payload)
		if err == nil {
			if val, ok := payloadMap["online"]; ok {
				if b, ok := val.(bool); ok {
					online = b
				}
			}
		}
	}

	// 更新心跳（设备上报任何状态消息都刷新心跳）
	if err := p.stateManager.UpdateHeartbeat(ctx, raw.SN); err != nil {
		logger.Warn("Failed to update heartbeat", zap.String("sn", raw.SN), zap.Error(err))
	}

	// 确定状态转换事件
	var event StateTransition
	if online {
		event = EventOnlineReport
	} else {
		event = EventOfflineReport
	}

	// 通过状态管理器处理状态变更（内置防抖和状态转换检查）
	return p.stateManager.HandleStateChange(ctx, &StateChangeRequest{
		SN:        raw.SN,
		Event:     event,
		Timestamp: time.Now().UTC(),
	})
}

func (p *ProtocolParser) handleInfo(ctx context.Context, raw *RawMessage) error {
	// 解析 payload，支持嵌套格式 {"data": {...}, "timestamp": ...} 和扁平格式 {...}
	payloadBytes := raw.Payload
	var wrapper map[string]json.RawMessage
	if err := json.Unmarshal(raw.Payload, &wrapper); err == nil {
		if dataRaw, ok := wrapper["data"]; ok {
			payloadBytes = dataRaw
		}
	}

	var info model.DeviceInfo
	if err := json.Unmarshal(payloadBytes, &info); err != nil {
		// 尝试解包字符串形式的 payload
		var s string
		if err2 := json.Unmarshal(payloadBytes, &s); err2 == nil {
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

	// 同步更新 Redis 缓存中的 info 数据，保持与数据库一致
	if p.rdb != nil {
		infoPayload := map[string]interface{}{
			"data": map[string]interface{}{
				"model":           info.Model,
				"manufacturer":    info.Manufacturer,
				"firmware_arm":    info.FirmwareARM,
				"firmware_esp":    info.FirmwareESP,
				"firmware_dsp":    info.FirmwareDSP,
				"firmware_bms":    info.FirmwareBMS,
				"type":            info.Type,
				"rated_power":     info.RatedPower,
				"rated_voltage":   info.RatedVoltage,
				"rated_freq":      info.RatedFreq,
				"battery_voltage": info.BatteryVoltage,
				"battery_type":    info.BatteryType,
				"cell_count":      info.CellCount,
				"sn":              info.SN,
			},
			"timestamp": time.Now().UTC().Unix(),
		}
		cacheKey := "realtime:latest:" + raw.SN
		existing, err := p.rdb.Get(ctx, cacheKey).Bytes()
		var rt map[string]interface{}
		if err == nil {
			_ = json.Unmarshal(existing, &rt)
		}
		if rt == nil {
			rt = make(map[string]interface{})
		}
		rt["info"] = infoPayload
		rt["_sn"] = raw.SN
		rt["_updated_at"] = time.Now().UTC().Format(time.RFC3339)
		mergedBytes, _ := json.Marshal(rt)
		p.rdb.Set(ctx, cacheKey, mergedBytes, 120*time.Second)
	}

	logger.Info("Device info registered",
		zap.String("sn", raw.SN),
		zap.String("model", info.Model),
		zap.String("firmware_arm", info.FirmwareARM),
		zap.String("firmware_esp", info.FirmwareESP),
		zap.String("firmware_dsp", info.FirmwareDSP),
		zap.String("firmware_bms", info.FirmwareBMS))
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
	// 更新心跳
	if err := p.stateManager.UpdateHeartbeat(ctx, raw.SN); err != nil {
		logger.Warn("Failed to update heartbeat", zap.String("sn", raw.SN), zap.Error(err))
	}

	logger.Info("handleTelemetry called",
		zap.String("sn", raw.SN),
		zap.String("msg_type", raw.MsgType))

	// 通过状态管理器处理在线状态（内置防抖）
	if err := p.stateManager.HandleStateChange(ctx, &StateChangeRequest{
		SN:        raw.SN,
		Event:     EventOnlineReport,
		Timestamp: time.Now().UTC(),
	}); err != nil {
		logger.Warn("Failed to handle online state",
			zap.String("sn", raw.SN),
			zap.Error(err))
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

	// data/status 故障检测：通过状态管理器统一处理
	if raw.MsgType == "data/status" && parsedPayload != nil {
		logger.Info("data/status payload received",
			zap.String("sn", raw.SN),
			zap.Any("payload", parsedPayload))

		// 通过状态管理器检测并处理故障状态
		if err := p.stateManager.DetectAndHandleFault(ctx, raw.SN, parsedPayload); err != nil {
			logger.Warn("Failed to detect/handle fault",
				zap.String("sn", raw.SN),
				zap.Error(err))
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

	// 确定 result 字段值（兼容新旧格式）
	result := resp.Result
	if result == "" {
		if resp.Success {
			result = "success"
		} else {
			result = "failed"
		}
	}

	// 优先使用新的 cmd_result 接口，回退到旧的 device-cmd-status
	endpoint := "/api/v1/internal/device-cmd-result"
	payload := map[string]interface{}{
		"sn":        raw.SN,
		"task_id":   resp.TaskID,
		"cmd":       resp.Cmd,
		"result":    result,
		"success":   resp.Success,
		"message":   resp.Message,
		"timestamp": resp.Timestamp,
	}
	if resp.Data != nil {
		payload["data"] = json.RawMessage(resp.Data)
	}

	return p.postInternal(endpoint, payload)
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
	// 缓存时间改为600秒（10分钟），因为设备不同topic发送频率不同（1-6分钟）
	for k, v := range payload {
		fieldBytes, _ := json.Marshal(map[string]interface{}{"v": v, "ts": time.Now().UTC().Unix()})
		pipe.Set(ctx, fmt.Sprintf("realtime:latest:%s:%s", sn, k), fieldBytes, 600*time.Second)
	}
	rt["_sn"] = sn
	rt["_msg_type"] = msgType
	rt["_updated_at"] = time.Now().UTC().Format(time.RFC3339)

	mergedBytes, _ := json.Marshal(rt)
	pipe.Set(ctx, cacheKey, mergedBytes, 600*time.Second)

	// 有效数据缓存：检查合并后的完整数据是否包含有效值
	// 因为设备数据分散在多个topic中，需要检查整个rt而不是单个payload
	if isValidRealtimeData(rt, topicCategory) {
		validCacheKey := "realtime:last_valid:" + sn
		rt["_sn"] = sn
		rt["_msg_type"] = msgType
		rt["_updated_at"] = time.Now().Format(time.RFC3339)
		validMergedBytes, _ := json.Marshal(rt)
		// 有效数据缓存7天过期
		pipe.Set(ctx, validCacheKey, validMergedBytes, 7*24*time.Hour)
	}

	if _, err := pipe.Exec(ctx); err != nil {
		return err
	}

	pubChannel := "realtime:channel:" + sn
	_ = p.rdb.Publish(ctx, pubChannel, string(mergedBytes)).Err()

	return nil
}

// isValidRealtimeData 判断实时数据是否为有效数据（非全0）
// 用于决定是否更新有效数据缓存
// 注意：data参数可能是合并后的完整数据（包含ac/batt/pv等嵌套对象）
func isValidRealtimeData(data map[string]interface{}, topicCategory string) bool {
	// 如果是info类型，始终认为是有效数据
	if topicCategory == "info" {
		return true
	}

	// 检查顶层字段
	if hasValidFields(data) {
		return true
	}

	// 检查嵌套对象中的字段（ac、batt、pv、energy等）
	// 设备数据结构: {"ac": {"data": {...}, "timestamp": ...}, ...}
	nestedKeys := []string{"ac", "batt", "battery", "pv", "energy", "sys", "system"}
	for _, key := range nestedKeys {
		if nested, ok := data[key]; ok {
			if nestedMap, ok := nested.(map[string]interface{}); ok {
				// 处理嵌套格式 {"data": {...}, "timestamp": ...}
				if innerData, exists := nestedMap["data"].(map[string]interface{}); exists {
					if hasValidFields(innerData) {
						return true
					}
				} else {
					if hasValidFields(nestedMap) {
						return true
					}
				}
			}
		}
	}

	return false
}

// hasValidFields 检查数据中是否包含有效字段（功率/电压/能量>0）
func hasValidFields(data map[string]interface{}) bool {
	// 检查功率相关字段
	powerFields := []string{"power", "pv_power", "pv_power_total", "active_power", "total_active_power"}
	for _, field := range powerFields {
		if v, ok := data[field]; ok {
			if f, ok := v.(float64); ok && f > 0 {
				return true
			}
		}
	}

	// 检查电压相关字段（电压通常不为0表示设备在工作）
	voltageFields := []string{"voltage", "ac_voltage", "pv_voltage", "pv1_voltage", "pv2_voltage"}
	for _, field := range voltageFields {
		if v, ok := data[field]; ok {
			if f, ok := v.(float64); ok && f > 0 {
				return true
			}
		}
	}

	// 检查能量相关字段
	energyFields := []string{"daily_pv", "total_pv", "daily_charge", "total_charge"}
	for _, field := range energyFields {
		if v, ok := data[field]; ok {
			if f, ok := v.(float64); ok && f > 0 {
				return true
			}
		}
	}

	// 检查SOC字段
	if v, ok := data["soc"]; ok {
		if f, ok := v.(float64); ok && f > 0 {
			return true
		}
	}

	// 所有关键字段都为0或不存在，认为是无效数据
	return false
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
