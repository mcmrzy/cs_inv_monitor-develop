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
	telemetryv2 "inv-device-server/internal/telemetry"
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
	batcher     *TelemetryBatcher

	snModelCache map[string]int32
	snCacheMu    sync.RWMutex
	parseEngine  *ParseRuleEngine
	stateManager *DeviceStateManager // 集中式状态管理器

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
		batcher:      NewTelemetryBatcher(apiServer, internalKey),
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
	go p.batcher.Start(ctx)
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
	case "heartbeat":
		return p.handleHeartbeat(ctx, raw)
	case "config":
		return p.handleReportedConfig(ctx, raw)
	case "info", "data/info":
		return p.handleInfo(ctx, raw)
	case "cmd", "cmd/response", "cmd_result":
		return p.handleCommandResponse(ctx, raw)
	case "parallel":
		return p.handleParallel(ctx, raw)
	case "three_phase":
		return p.handleThreePhase(ctx, raw)
	default:
		return p.handleTelemetry(ctx, raw)
	}
}

func (p *ProtocolParser) handleReportedConfig(ctx context.Context, raw *RawMessage) error {
	cfg, err := telemetryv2.ParseReportedConfig(raw.Payload)
	if err != nil {
		return err
	}
	if err := p.repo.SaveReportedConfig(ctx, raw.SN, cfg); err != nil {
		return err
	}
	if p.rdb != nil {
		encoded, err := json.Marshal(cfg.Values)
		if err == nil {
			_ = p.rdb.Set(ctx, "device:config:"+raw.SN, encoded, 24*time.Hour).Err()
		}
	}
	return nil
}

func (p *ProtocolParser) handleHeartbeat(ctx context.Context, raw *RawMessage) error {
	receivedAt := time.Now().UTC()
	if raw.ReceivedAt != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, raw.ReceivedAt); err == nil {
			receivedAt = parsed.UTC()
		}
	}
	cellCount, tempSensorCount, err := p.repo.GetDeviceCellCounts(ctx, raw.SN)
	if err != nil || cellCount <= 0 {
		cellCount = 16
	}
	if tempSensorCount <= 0 {
		tempSensorCount = 4
	}
	sample, err := telemetryv2.ParseHeartbeat(raw.SN, raw.Payload, cellCount, tempSensorCount, receivedAt)
	if err != nil {
		if saveErr := p.repo.SaveIngestError(ctx, raw.SN, raw.MsgType, raw.Payload, "INVALID_HEARTBEAT", err.Error()); saveErr != nil {
			return fmt.Errorf("%v; save ingest error: %w", err, saveErr)
		}
		return nil
	}
	if err := p.repo.SaveTelemetryV2(ctx, sample); err != nil {
		return err
	}

	if sample.QualityFlags&telemetryv2.QualityBackfill == 0 {
		if err := p.stateManager.UpdateHeartbeat(ctx, raw.SN); err != nil {
			logger.Warn("Failed to update heartbeat", zap.String("sn", raw.SN), zap.Error(err))
		}
		if err := p.stateManager.HandleStateChange(ctx, &StateChangeRequest{SN: raw.SN, Event: EventOnlineReport, Timestamp: receivedAt}); err != nil {
			logger.Warn("Failed to handle heartbeat online state", zap.String("sn", raw.SN), zap.Error(err))
		}
	}

	status := map[string]interface{}{}
	if sample.System.FaultCode != nil {
		status["fault_code"] = int64(*sample.System.FaultCode)
	}
	if sample.System.AlarmCode != nil {
		status["alarm_code"] = int64(*sample.System.AlarmCode)
	}
	if sample.System.WorkState != nil {
		status["work_state"] = int64(*sample.System.WorkState)
	}
	if err := p.stateManager.DetectAndHandleFault(ctx, raw.SN, status); err != nil {
		logger.Warn("Failed to detect heartbeat fault", zap.String("sn", raw.SN), zap.Error(err))
	}

	if p.rdb != nil && sample.QualityFlags&telemetryv2.QualityBackfill == 0 {
		latest := map[string]interface{}{
			"device_sn": raw.SN, "event_time": sample.EventTime, "quality_flags": sample.QualityFlags,
			"ac_power": sample.AC.ActivePower, "pv_total_power": sample.PV.TotalPower,
			"battery_soc": sample.Battery.SOC, "battery_power": sample.Battery.Power,
			"work_state": sample.System.WorkState, "fault_code": sample.System.FaultCode,
			"daily_pv": sample.Energy.DailyPV, "total_pv": sample.Energy.TotalPV,
		}
		if encoded, marshalErr := json.Marshal(latest); marshalErr == nil {
			_ = p.rdb.Set(ctx, "device:latest:"+raw.SN, encoded, 10*time.Minute).Err()
		}
	}
	return nil
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
				"model":                   info.Model,
				"manufacturer":            info.Manufacturer,
				"firmware_arm":            info.FirmwareARM,
				"firmware_esp":            info.FirmwareESP,
				"firmware_dsp":            info.FirmwareDSP,
				"firmware_bms":            info.FirmwareBMS,
				"device_type":             info.Type,
				"rated_power":             info.RatedPower,
				"rated_voltage":           info.RatedVoltage,
				"rated_frequency":         info.RatedFreq,
				"battery_nominal_voltage": info.BatteryVoltage,
				"battery_type":            info.BatteryType,
				"cell_count":              info.CellCount,
				"temp_sensor_count":       info.TempSensorCount,
				"sn":                      info.SN,
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
		p.rdb.Set(ctx, cacheKey, mergedBytes, 10*time.Minute)
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

	// 直接使用解析后的 payload，不再添加带前缀的冗余字段（ac_data/pv_data/batt_data 等）
	topic := raw.MsgType
	if topic == "" {
		topic = "data/unknown"
	}

	item := &telemetryBatchItem{
		SN:   raw.SN,
		Topic: topic,
		Data: parsedPayload,
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
	item.Timestamp = timestamp

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
			item.DailyPV = energy.DailyPV
			item.TotalPV = energy.TotalPV
			item.DailyCharge = energy.DailyCharge
			item.TotalCharge = energy.TotalCharge
			item.DailyDischarge = energy.DailyDischarge
			item.TotalDischarge = energy.TotalDischarge
			item.DailyLoad = energy.DailyLoad
			item.TotalLoad = energy.TotalLoad
			item.RuntimeHours = energy.RuntimeHours
		}
		stationID, _ := p.repo.GetStationIDBySN(ctx, raw.SN)
		if stationID > 0 {
			item.StationID = stationID
		}
	}

	p.batcher.Add(item)

	if err := p.cacheRealtime(ctx, raw.SN, parsedPayload, raw.MsgType); err != nil {
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
	normalizedPayload, err := normalizeCommandResultPayload(raw.SN, raw.Payload)
	if err != nil {
		return err
	}
	var resp model.CommandResponse
	if err := json.Unmarshal(normalizedPayload, &resp); err != nil {
		return err
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
		"stage":     resp.Stage,
		"code":      resp.Code,
		"message":   resp.Message,
		"timestamp": resp.Timestamp,
	}
	if resp.Data != nil {
		payload["data"] = json.RawMessage(resp.Data)
	}

	return p.postInternal(endpoint, payload)
}

// handleParallel 处理并机状态消息（parallel topic）
// 解析并机拓扑数据，提取 master SN 和 station_id，
// 通过内部 API 转发给 api_server 进行 UPSERT 和拓扑变化检测，
// 并更新 Redis 实时缓存。
func (p *ProtocolParser) handleParallel(ctx context.Context, raw *RawMessage) error {
	// 更新心跳
	if err := p.stateManager.UpdateHeartbeat(ctx, raw.SN); err != nil {
		logger.Warn("Failed to update heartbeat", zap.String("sn", raw.SN), zap.Error(err))
	}
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

	// 解析 payload，支持嵌套格式 {"data": {...}, "t": ..., "v": ...}
	payloadBytes := raw.Payload
	var wrapper struct {
		T    int64           `json:"t"`
		V    int             `json:"v"`
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(raw.Payload, &wrapper); err != nil {
		return err
	}
	if len(wrapper.Data) > 0 {
		payloadBytes = wrapper.Data
	}

	var parallel struct {
		Enabled          bool `json:"enabled"`
		Mode             string  `json:"mode"`
		Count            int     `json:"count"`
		TotalRatedPower  int     `json:"total_rated_power"`
		TotalActivePower float64 `json:"total_active_power"`
		SyncState        string  `json:"sync_state"`
		Machines []struct {
			ID    int     `json:"id"`
			SN    string  `json:"sn"`
			Role  string  `json:"role"`
			Phase string  `json:"phase"`
			Power float64 `json:"power"`
			State int     `json:"state"`
		} `json:"machines"`
	}
	if err := json.Unmarshal(payloadBytes, &parallel); err != nil {
		return err
	}

	// 找到 master SN（从 machines 数组中 role="master" 的设备）
	masterSN := raw.SN
	for _, m := range parallel.Machines {
		if m.Role == "master" {
			masterSN = m.SN
			break
		}
	}

	// 查询设备的 station_id
	stationID, _ := p.repo.GetStationIDBySN(ctx, raw.SN)

	// 构建转发给 api_server 的请求 payload
	requestPayload := map[string]interface{}{
		"sn":                 raw.SN,
		"master_sn":          masterSN,
		"station_id":         stationID,
		"enabled":            parallel.Enabled,
		"mode":               parallel.Mode,
		"count":              parallel.Count,
		"total_rated_power":  parallel.TotalRatedPower,
		"total_active_power": parallel.TotalActivePower,
		"sync_state":         parallel.SyncState,
		"machines":           parallel.Machines,
		"timestamp":          wrapper.T,
	}

	// 通过内部 API 转发给 api_server（api_server 负责 UPSERT 和拓扑变化检测）
	if err := p.postInternal("/api/v1/internal/parallel-state", requestPayload); err != nil {
		return err
	}

	// 更新 Redis 实时缓存
	if p.rdb != nil {
		parallelPayload := map[string]interface{}{
			"data": map[string]interface{}{
				"enabled":            parallel.Enabled,
				"mode":               parallel.Mode,
				"count":              parallel.Count,
				"total_rated_power":  parallel.TotalRatedPower,
				"total_active_power": parallel.TotalActivePower,
				"sync_state":         parallel.SyncState,
				"machines":           parallel.Machines,
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
		rt["parallel"] = parallelPayload
		rt["_sn"] = raw.SN
		rt["_updated_at"] = time.Now().UTC().Format(time.RFC3339)
		mergedBytes, _ := json.Marshal(rt)
		p.rdb.Set(ctx, cacheKey, mergedBytes, 10*time.Minute)
	}

	logger.Info("Parallel state processed",
		zap.String("sn", raw.SN),
		zap.String("master_sn", masterSN),
		zap.String("mode", parallel.Mode),
		zap.Int("count", parallel.Count),
		zap.String("sync_state", parallel.SyncState))
	return nil
}

// handleThreePhase 处理三相数据消息（three_phase topic）
// 解析三相电压/电流/功率数据，校验数组长度，
// 通过内部 API 转发给 api_server，并写入 Redis 实时缓存。
func (p *ProtocolParser) handleThreePhase(ctx context.Context, raw *RawMessage) error {
	// 更新心跳
	if err := p.stateManager.UpdateHeartbeat(ctx, raw.SN); err != nil {
		logger.Warn("Failed to update heartbeat", zap.String("sn", raw.SN), zap.Error(err))
	}
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

	// 解析 payload，支持嵌套格式 {"data": {...}, "t": ..., "v": ...}
	payloadBytes := raw.Payload
	var wrapper struct {
		T    int64           `json:"t"`
		V    int             `json:"v"`
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(raw.Payload, &wrapper); err != nil {
		return err
	}
	if len(wrapper.Data) > 0 {
		payloadBytes = wrapper.Data
	}

	var threePhase struct {
		Voltage          []float64 `json:"voltage"`
		Current          []float64 `json:"current"`
		ActivePower      []float64 `json:"active_power"`
		TotalActivePower float64   `json:"total_active_power"`
		LineVoltage      []float64 `json:"line_voltage"`
		Frequency        float64   `json:"frequency"`
		VoltageUnbalance float64   `json:"voltage_unbalance"`
		CurrentUnbalance float64   `json:"current_unbalance"`
	}
	if err := json.Unmarshal(payloadBytes, &threePhase); err != nil {
		return err
	}

	// 校验三相数组长度（必须为3）
	if len(threePhase.Voltage) != 3 || len(threePhase.Current) != 3 ||
		len(threePhase.ActivePower) != 3 || len(threePhase.LineVoltage) != 3 {
		return fmt.Errorf("three_phase arrays must have exactly 3 elements: voltage=%d, current=%d, active_power=%d, line_voltage=%d",
			len(threePhase.Voltage), len(threePhase.Current),
			len(threePhase.ActivePower), len(threePhase.LineVoltage))
	}

	// 构建转发给 api_server 的请求 payload
	requestPayload := map[string]interface{}{
		"sn":                 raw.SN,
		"voltage":            threePhase.Voltage,
		"current":            threePhase.Current,
		"active_power":       threePhase.ActivePower,
		"total_active_power": threePhase.TotalActivePower,
		"line_voltage":       threePhase.LineVoltage,
		"frequency":          threePhase.Frequency,
		"voltage_unbalance":  threePhase.VoltageUnbalance,
		"current_unbalance":  threePhase.CurrentUnbalance,
		"timestamp":          wrapper.T,
	}

	// 通过内部 API 转发给 api_server
	if err := p.postInternal("/api/v1/internal/three-phase", requestPayload); err != nil {
		return err
	}

	// 写入 Redis 实时缓存
	if p.rdb != nil {
		threePhasePayload := map[string]interface{}{
			"data": map[string]interface{}{
				"voltage":             threePhase.Voltage,
				"current":             threePhase.Current,
				"active_power":        threePhase.ActivePower,
				"total_active_power":  threePhase.TotalActivePower,
				"line_voltage":        threePhase.LineVoltage,
				"frequency":           threePhase.Frequency,
				"voltage_unbalance":   threePhase.VoltageUnbalance,
				"current_unbalance":   threePhase.CurrentUnbalance,
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
		rt["three_phase"] = threePhasePayload
		rt["_sn"] = raw.SN
		rt["_updated_at"] = time.Now().UTC().Format(time.RFC3339)
		mergedBytes, _ := json.Marshal(rt)
		p.rdb.Set(ctx, cacheKey, mergedBytes, 10*time.Minute)
	}

	logger.Info("Three-phase data processed",
		zap.String("sn", raw.SN),
		zap.Float64("total_active_power", threePhase.TotalActivePower),
		zap.Float64("frequency", threePhase.Frequency))
	return nil
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

	// ── 时间戳保护：防止离线补发的旧数据覆盖 Redis 中的新数据 ──
	// 从 incoming payload 提取设备时间戳（Unix 秒）
	incomingTimestamp := extractUnixTimestamp(payload, "timestamp")
	// 从已缓存数据中提取上次写入的设备时间戳（_timestamp 由本方法写入顶层）
	cachedTimestamp := extractUnixTimestamp(rt, "_timestamp")
	// 仅当新数据不比缓存旧时才执行写入
	if incomingTimestamp < cachedTimestamp {
		return nil
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
	// 记录设备时间戳（Unix 秒），用于下次写入时做时间戳保护比较
	rt["_timestamp"] = incomingTimestamp

	mergedBytes, _ := json.Marshal(rt)
	pipe.Set(ctx, cacheKey, mergedBytes, 600*time.Second)

	// 有效数据缓存：检查合并后的完整数据是否包含有效值
	// 因为设备数据分散在多个topic中，需要检查整个rt而不是单个payload
	if isValidRealtimeData(rt, topicCategory) {
		validCacheKey := "realtime:last_valid:" + sn
		rt["_sn"] = sn
		rt["_msg_type"] = msgType
		rt["_updated_at"] = time.Now().UTC().Format(time.RFC3339)
		validMergedBytes, _ := json.Marshal(rt)
		// 有效数据缓存7天过期
		pipe.Set(ctx, validCacheKey, validMergedBytes, 7*24*time.Hour)
	}

	if _, err := pipe.Exec(ctx); err != nil {
		return err
	}

	pubChannel := "realtime:channel:" + sn
	_ = p.rdb.Publish(ctx, pubChannel, string(mergedBytes)).Err()

	// 缓存最近100条消息用于 WebSocket 重连回填
	historyKey := fmt.Sprintf("realtime:history:%s", sn)
	histPipe := p.rdb.Pipeline()
	histPipe.LPush(ctx, historyKey, string(mergedBytes))
	histPipe.LTrim(ctx, historyKey, 0, 99) // 只保留最近100条
	histPipe.Expire(ctx, historyKey, 10*time.Minute)
	_, _ = histPipe.Exec(ctx)

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

// extractUnixTimestamp 从 map 中提取指定 key 的 Unix 时间戳（int64 秒）。
// 兼容 JSON 反序列化后的 float64、原生 int64 以及 json.Number 类型。
func extractUnixTimestamp(m map[string]interface{}, key string) int64 {
	v, ok := m[key]
	if !ok {
		return 0
	}
	switch val := v.(type) {
	case float64:
		return int64(val)
	case int64:
		return val
	case int:
		return int64(val)
	case json.Number:
		n, _ := val.Int64()
		return n
	default:
		return 0
	}
}

// telemetryBatchItem 遥测批量写入数据项，与 api_server 的 internalDeviceDataRequest 结构对应
type telemetryBatchItem struct {
	SN             string                 `json:"sn"`
	Topic          string                 `json:"topic"`
	Data           map[string]interface{} `json:"data"`
	DailyPV        float64                `json:"daily_pv"`
	TotalPV        float64                `json:"total_pv"`
	DailyCharge    float64                `json:"daily_charge"`
	TotalCharge    float64                `json:"total_charge"`
	DailyDischarge float64                `json:"daily_discharge"`
	TotalDischarge float64                `json:"total_discharge"`
	DailyLoad      float64                `json:"daily_load"`
	TotalLoad      float64                `json:"total_load"`
	RuntimeHours   float64                `json:"runtime_hours"`
	StationID      int64                  `json:"station_id"`
	Timestamp      int64                  `json:"timestamp"`
}

const (
	batchSize     = 500              // 数量阈值
	batchInterval = 2 * time.Second  // 时间阈值
	maxBufferSize = 10000            // 背压阈值
)

// TelemetryBatcher 遥测数据批量缓冲组件
// 将逐条 HTTP POST 改为批量发送，减少 api_server 的写入压力
type TelemetryBatcher struct {
	mu          sync.Mutex
	buffer      []*telemetryBatchItem
	flushCh     chan struct{}
	client      *http.Client
	apiURL      string
	internalKey string
}

// NewTelemetryBatcher 创建批量缓冲器
func NewTelemetryBatcher(apiServer, internalKey string) *TelemetryBatcher {
	return &TelemetryBatcher{
		buffer:  make([]*telemetryBatchItem, 0, batchSize),
		flushCh: make(chan struct{}, 1),
		client: &http.Client{
			Timeout: 30 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 50,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		apiURL:      strings.TrimRight(apiServer, "/") + "/api/v1/internal/device-data-batch",
		internalKey: internalKey,
	}
}

// Start 启动定时 flush goroutine，每 batchInterval 触发一次
func (b *TelemetryBatcher) Start(ctx context.Context) {
	ticker := time.NewTicker(batchInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			b.flush() // 关闭前最后一次 flush
			return
		case <-ticker.C:
			b.flush()
		case <-b.flushCh:
			b.flush()
		}
	}
}

// Add 添加消息到缓冲，达到 batchSize 时触发 flush；超过 maxBufferSize 时阻塞（背压）
func (b *TelemetryBatcher) Add(item *telemetryBatchItem) {
	for {
		b.mu.Lock()
		if len(b.buffer) < maxBufferSize {
			b.buffer = append(b.buffer, item)
			shouldFlush := len(b.buffer) >= batchSize
			b.mu.Unlock()
			if shouldFlush {
				select {
				case b.flushCh <- struct{}{}:
				default:
				}
			}
			return
		}
		b.mu.Unlock()
		// 缓冲已满，等待 flush 释放空间后重试
		time.Sleep(10 * time.Millisecond)
	}
}

// flush 将缓冲区消息批量发送到 api_server
func (b *TelemetryBatcher) flush() {
	b.mu.Lock()
	if len(b.buffer) == 0 {
		b.mu.Unlock()
		return
	}
	batch := b.buffer
	b.buffer = make([]*telemetryBatchItem, 0, batchSize)
	b.mu.Unlock()

	body, err := json.Marshal(batch)
	if err != nil {
		logger.Error("TelemetryBatcher: failed to marshal batch",
			zap.Int("count", len(batch)), zap.Error(err))
		return
	}

	req, err := http.NewRequest(http.MethodPost, b.apiURL, bytes.NewReader(body))
	if err != nil {
		logger.Error("TelemetryBatcher: failed to create request", zap.Error(err))
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if b.internalKey != "" {
		req.Header.Set("X-Internal-Key", b.internalKey)
	}

	resp, err := b.client.Do(req)
	if err != nil {
		logger.Error("TelemetryBatcher: failed to send batch",
			zap.Int("count", len(batch)), zap.Error(err))
		return
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		logger.Error("TelemetryBatcher: API returned error",
			zap.Int("status", resp.StatusCode),
			zap.Int("count", len(batch)),
			zap.String("response", string(respBody)))
	} else {
		logger.Info("TelemetryBatcher: batch sent successfully",
			zap.Int("count", len(batch)))
	}
}
