package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"regexp"
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

type ProtocolParser struct {
	consumer     kafkaMessageReader
	repo         *repository.DeviceRepository
	ingestErrors ingestErrorStore
	metaRepo     *repository.MetadataRepository
	rdb          *redis.Client
	hub          *mqtt.Hub
	apiServer    string
	internalKey  string
	httpClient   *http.Client
	batcher      *TelemetryBatcher

	snModelCache map[string]int32
	snCacheMu    sync.RWMutex
	parseEngine  *ParseRuleEngine
	stateManager *DeviceStateManager // 集中式状态管理器

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
	parser := &ProtocolParser{
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
	}
	if repo != nil {
		parser.ingestErrors = repo
	}
	return parser
}

func (p *ProtocolParser) Start(ctx context.Context) {
	go runOrderedKafkaConsumer(ctx, "protocol-parser", p.consumer, p.processKafkaMessage, 250*time.Millisecond)
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

func (p *ProtocolParser) processKafkaMessage(ctx context.Context, message kafka.Message) error {
	var raw RawMessage
	if err := json.Unmarshal(message.Value, &raw); err != nil {
		return p.isolatePermanentMessage(ctx, "", message.Topic, message.Value,
			"INVALID_BRIDGE_JSON", fmt.Errorf("decode bridge message: %w", err))
	}
	if strings.TrimSpace(raw.SN) == "" {
		return p.isolatePermanentMessage(ctx, "", message.Topic, message.Value,
			"MISSING_DEVICE_SN", fmt.Errorf("bridge message is missing device sn"))
	}
	err := p.processMessage(ctx, &raw)
	if permanent, ok := asPermanentMessage(err); ok {
		return p.isolatePermanentMessage(ctx, raw.SN, raw.MsgType, raw.Payload, permanent.code, permanent.err)
	}
	var httpErr *downstreamHTTPError
	if errors.As(err, &httpErr) && httpErr.permanent() {
		return p.isolatePermanentMessage(ctx, raw.SN, raw.MsgType, raw.Payload, "DOWNSTREAM_HTTP_4XX", httpErr)
	}
	return err
}

func (p *ProtocolParser) isolatePermanentMessage(
	ctx context.Context, sn, topic string, payload []byte, code string, cause error,
) error {
	if p.ingestErrors == nil {
		return fmt.Errorf("permanent ingest error cannot be audited (%s): %w", code, cause)
	}
	if err := p.ingestErrors.SaveIngestError(ctx, sn, topic, payload, code, cause.Error()); err != nil {
		return fmt.Errorf("save permanent ingest error %s: %w", code, err)
	}
	logger.Warn("Permanent Kafka message isolated in device_ingest_errors",
		zap.String("sn", sn), zap.String("topic", topic), zap.String("error_code", code), zap.Error(cause))
	return nil
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
		return permanentMessage("INVALID_REPORTED_CONFIG", err)
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
			"device_sn": raw.SN, "protocol_version": sample.ProtocolVersion,
			"event_time": sample.EventTime, "quality_flags": sample.QualityFlags,
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
		return fmt.Errorf("API server URL is empty for internal call %s", path)
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
			return &downstreamHTTPError{status: resp.StatusCode, body: string(bodyBytes)}
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
		SN:    raw.SN,
		Topic: topic,
		Data:  parsedPayload,
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

	// Kafka offset acknowledgement must reflect durable downstream acceptance.
	// The previous fire-and-forget batch buffer could drop a batch after the
	// offset had already been committed, so the ordered consumer uses a
	// synchronous, acknowledged send here.
	if err := p.batcher.Send(ctx, item); err != nil {
		return err
	}

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

const maxV1PayloadBytes = 16 * 1024

var v1DeviceSNPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,50}$`)

type v1UpstreamEnvelope struct {
	T    int64           `json:"t"`
	V    int             `json:"v"`
	Data json.RawMessage `json:"data"`
}

type internalEnvelopeRequest struct {
	SN         string          `json:"sn"`
	Topic      string          `json:"topic"`
	ReceivedAt time.Time       `json:"received_at"`
	Envelope   json.RawMessage `json:"envelope"`
}

type parallelMachineV1 struct {
	ID    int     `json:"id"`
	SN    string  `json:"sn"`
	Role  string  `json:"role"`
	Phase *string `json:"phase"`
	Power float64 `json:"power"`
	State int     `json:"state"`
}

type parallelDataV1 struct {
	Enabled          bool                `json:"enabled"`
	Mode             string              `json:"mode"`
	Count            int                 `json:"count"`
	TotalRatedPower  uint64              `json:"total_rated_power"`
	TotalActivePower float64             `json:"total_active_power"`
	SyncState        string              `json:"sync_state"`
	Machines         []parallelMachineV1 `json:"machines"`
}

type threePhaseDataV1 struct {
	Voltage          []float64 `json:"voltage"`
	Current          []float64 `json:"current"`
	ActivePower      []float64 `json:"active_power"`
	TotalActivePower float64   `json:"total_active_power"`
	LineVoltage      []float64 `json:"line_voltage"`
	Frequency        float64   `json:"frequency"`
	VoltageUnbalance float64   `json:"voltage_unbalance"`
	CurrentUnbalance float64   `json:"current_unbalance"`
}

func parseV1UpstreamEnvelope(payload json.RawMessage) (*v1UpstreamEnvelope, error) {
	if len(payload) == 0 {
		return nil, fmt.Errorf("empty V1 envelope")
	}
	if len(payload) > maxV1PayloadBytes {
		return nil, fmt.Errorf("V1 envelope exceeds %d bytes", maxV1PayloadBytes)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(payload, &fields); err != nil {
		return nil, fmt.Errorf("invalid V1 envelope: %w", err)
	}
	if fields == nil {
		return nil, fmt.Errorf("V1 envelope must be an object")
	}
	for _, name := range []string{"t", "v", "data"} {
		value, ok := fields[name]
		if !ok || string(bytes.TrimSpace(value)) == "null" {
			return nil, fmt.Errorf("V1 envelope field %q is required", name)
		}
	}
	var envelope v1UpstreamEnvelope
	if err := json.Unmarshal(payload, &envelope); err != nil {
		return nil, fmt.Errorf("invalid V1 envelope fields: %w", err)
	}
	if envelope.T <= 0 {
		return nil, fmt.Errorf("V1 envelope t must be greater than zero")
	}
	if envelope.V != 1 {
		return nil, fmt.Errorf("unsupported V1 envelope version %d", envelope.V)
	}
	data := bytes.TrimSpace(envelope.Data)
	if len(data) < 2 || data[0] != '{' || data[len(data)-1] != '}' {
		return nil, fmt.Errorf("V1 envelope data must be an object")
	}
	return &envelope, nil
}

func decodeStrictV1Data(raw json.RawMessage, dst interface{}, requiredFields ...string) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil || fields == nil {
		return fmt.Errorf("data must be a JSON object")
	}
	for _, name := range requiredFields {
		value, ok := fields[name]
		if !ok || string(bytes.TrimSpace(value)) == "null" {
			return fmt.Errorf("data field %q is required", name)
		}
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		return fmt.Errorf("invalid data object: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("invalid trailing JSON data")
	}
	return nil
}

func rawMessageReceivedAt(raw *RawMessage) (time.Time, error) {
	if raw.ReceivedAt == "" {
		return time.Now().UTC(), nil
	}
	receivedAt, err := time.Parse(time.RFC3339Nano, raw.ReceivedAt)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid received_at: %w", err)
	}
	return receivedAt.UTC(), nil
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func powerTotalsMatch(parts []float64, total float64) bool {
	var sum float64
	for _, part := range parts {
		sum += part
	}
	tolerance := math.Max(1, math.Abs(sum)*0.005)
	return math.Abs(sum-total) <= tolerance
}

func validateParallelV1(sn string, data *parallelDataV1) error {
	if !v1DeviceSNPattern.MatchString(sn) {
		return fmt.Errorf("invalid topic device SN")
	}
	if data.Count < 0 || data.Count > 8 || len(data.Machines) != data.Count {
		return fmt.Errorf("parallel count must match a machines array of 0 to 8 entries")
	}
	if data.TotalRatedPower > math.MaxUint32 || !finite(data.TotalActivePower) || data.TotalActivePower < 0 {
		return fmt.Errorf("parallel total power is invalid")
	}
	if data.Mode != "standalone" && data.Mode != "single_phase" && data.Mode != "three_phase" {
		return fmt.Errorf("invalid parallel mode %q", data.Mode)
	}
	if data.SyncState != "idle" && data.SyncState != "synced" && data.SyncState != "syncing" && data.SyncState != "fault" {
		return fmt.Errorf("invalid parallel sync_state %q", data.SyncState)
	}
	if !data.Enabled {
		if data.Mode != "standalone" || data.Count != 0 || data.TotalRatedPower != 0 ||
			data.TotalActivePower != 0 || data.SyncState != "idle" || len(data.Machines) != 0 {
			return fmt.Errorf("disabled parallel topology must use the standalone zero-value form")
		}
		return nil
	}
	if data.Mode == "standalone" || data.Count == 0 || data.TotalRatedPower == 0 {
		return fmt.Errorf("enabled parallel topology requires members, rated power and a parallel mode")
	}

	seenIDs := make(map[int]struct{}, data.Count)
	seenSNs := make(map[string]struct{}, data.Count)
	phaseSeen := map[string]bool{"L1": false, "L2": false, "L3": false}
	masterCount := 0
	powers := make([]float64, 0, data.Count)
	previousID := -1
	for index, machine := range data.Machines {
		if machine.ID < 0 || machine.ID > 7 || machine.ID <= previousID {
			return fmt.Errorf("parallel machines must have unique IDs 0..7 in ascending order")
		}
		previousID = machine.ID
		if _, exists := seenIDs[machine.ID]; exists {
			return fmt.Errorf("duplicate parallel machine ID %d", machine.ID)
		}
		seenIDs[machine.ID] = struct{}{}
		if !v1DeviceSNPattern.MatchString(machine.SN) {
			return fmt.Errorf("invalid parallel machine SN at index %d", index)
		}
		if _, exists := seenSNs[machine.SN]; exists {
			return fmt.Errorf("duplicate parallel machine SN %q", machine.SN)
		}
		seenSNs[machine.SN] = struct{}{}
		if machine.Role != "master" && machine.Role != "slave" {
			return fmt.Errorf("invalid parallel machine role %q", machine.Role)
		}
		if machine.Role == "master" {
			masterCount++
			if machine.ID != 0 || machine.SN != sn {
				return fmt.Errorf("parallel master must be machine 0 and match the topic SN")
			}
		} else if machine.ID == 0 {
			return fmt.Errorf("parallel machine 0 must be the master")
		}
		if machine.State != 0 && machine.State != 2 && machine.State != 3 {
			return fmt.Errorf("invalid parallel machine state %d", machine.State)
		}
		if !finite(machine.Power) || machine.Power < 0 {
			return fmt.Errorf("parallel machine power must be finite and non-negative")
		}
		powers = append(powers, machine.Power)
		switch data.Mode {
		case "single_phase":
			if machine.Phase != nil {
				return fmt.Errorf("single-phase parallel machines must use null phase")
			}
		case "three_phase":
			if machine.Phase == nil || (*machine.Phase != "L1" && *machine.Phase != "L2" && *machine.Phase != "L3") {
				return fmt.Errorf("three-phase parallel machines require phase L1, L2 or L3")
			}
			phaseSeen[*machine.Phase] = true
		}
	}
	if masterCount != 1 {
		return fmt.Errorf("parallel topology must contain exactly one master")
	}
	if data.Mode == "three_phase" && (!phaseSeen["L1"] || !phaseSeen["L2"] || !phaseSeen["L3"]) {
		return fmt.Errorf("three-phase parallel topology must include L1, L2 and L3")
	}
	if !powerTotalsMatch(powers, data.TotalActivePower) {
		return fmt.Errorf("parallel total_active_power does not match member power")
	}
	return nil
}

func validateThreePhaseV1(data *threePhaseDataV1) error {
	if len(data.Voltage) != 3 || len(data.Current) != 3 || len(data.ActivePower) != 3 || len(data.LineVoltage) != 3 {
		return fmt.Errorf("three_phase arrays must have exactly 3 elements")
	}
	for _, values := range [][]float64{data.Voltage, data.Current, data.ActivePower, data.LineVoltage} {
		for _, value := range values {
			if !finite(value) {
				return fmt.Errorf("three_phase values must be finite numbers")
			}
		}
	}
	for _, values := range [][]float64{data.Voltage, data.Current, data.LineVoltage} {
		for _, value := range values {
			if value < 0 {
				return fmt.Errorf("three_phase voltage and current values must not be negative")
			}
		}
	}
	for _, value := range data.ActivePower {
		if value < 0 {
			return fmt.Errorf("three_phase active power values must not be negative")
		}
	}
	if !finite(data.TotalActivePower) || !finite(data.Frequency) || !finite(data.VoltageUnbalance) || !finite(data.CurrentUnbalance) {
		return fmt.Errorf("three_phase scalar values must be finite numbers")
	}
	if data.TotalActivePower < 0 || data.Frequency < 0 || data.VoltageUnbalance < 0 || data.VoltageUnbalance > 100 ||
		data.CurrentUnbalance < 0 || data.CurrentUnbalance > 100 {
		return fmt.Errorf("three_phase scalar values are outside the V1 range")
	}
	if !powerTotalsMatch(data.ActivePower, data.TotalActivePower) {
		return fmt.Errorf("three_phase total_active_power does not match phase power")
	}
	return nil
}

func (p *ProtocolParser) markValidUplink(ctx context.Context, sn string) {
	if p.stateManager == nil {
		return
	}
	if err := p.stateManager.UpdateHeartbeat(ctx, sn); err != nil {
		logger.Warn("Failed to update heartbeat", zap.String("sn", sn), zap.Error(err))
	}
	if err := p.stateManager.HandleStateChange(ctx, &StateChangeRequest{
		SN: sn, Event: EventOnlineReport, Timestamp: time.Now().UTC(),
	}); err != nil {
		logger.Warn("Failed to handle online state", zap.String("sn", sn), zap.Error(err))
	}
}

func (p *ProtocolParser) cacheProtocolSnapshot(ctx context.Context, sn, topic string, eventTime int64, data interface{}) {
	if p.rdb == nil {
		return
	}
	cacheKey := "realtime:latest:" + sn
	existing, err := p.rdb.Get(ctx, cacheKey).Bytes()
	var realtime map[string]interface{}
	if err == nil {
		_ = json.Unmarshal(existing, &realtime)
	}
	if realtime == nil {
		realtime = make(map[string]interface{})
	}
	// An offline device can replay old messages after reconnecting. Keep Redis
	// aligned with the database's latest-event semantics and never let an older
	// protocol snapshot replace a newer one.
	if current, ok := realtime[topic].(map[string]interface{}); ok {
		if timestamp, ok := current["timestamp"].(float64); ok && int64(timestamp) > eventTime {
			return
		}
	}
	realtime[topic] = map[string]interface{}{"data": data, "timestamp": eventTime}
	realtime["_sn"] = sn
	realtime["_updated_at"] = time.Now().UTC().Format(time.RFC3339)
	encoded, err := json.Marshal(realtime)
	if err == nil {
		_ = p.rdb.Set(ctx, cacheKey, encoded, 10*time.Minute).Err()
	}
}

// handleParallel 处理并机状态消息（parallel topic）
// 解析并机拓扑数据，提取 master SN 和 station_id，
// 通过内部 API 转发给 api_server 进行 UPSERT 和拓扑变化检测，
// 并更新 Redis 实时缓存。
func (p *ProtocolParser) handleParallel(ctx context.Context, raw *RawMessage) error {
	envelope, err := parseV1UpstreamEnvelope(raw.Payload)
	if err != nil {
		return permanentMessage("INVALID_PARALLEL", fmt.Errorf("parallel: %w", err))
	}
	var data parallelDataV1
	if err := decodeStrictV1Data(envelope.Data, &data,
		"enabled", "mode", "count", "total_rated_power", "total_active_power", "sync_state", "machines"); err != nil {
		return permanentMessage("INVALID_PARALLEL", fmt.Errorf("parallel: %w", err))
	}
	if err := validateParallelV1(raw.SN, &data); err != nil {
		return permanentMessage("INVALID_PARALLEL", fmt.Errorf("parallel: %w", err))
	}
	receivedAt, err := rawMessageReceivedAt(raw)
	if err != nil {
		return permanentMessage("INVALID_PARALLEL", fmt.Errorf("parallel: %w", err))
	}
	request := internalEnvelopeRequest{
		SN: raw.SN, Topic: "parallel", ReceivedAt: receivedAt,
		Envelope: append(json.RawMessage(nil), raw.Payload...),
	}
	if err := p.postInternal("/api/v1/internal/parallel-state", request); err != nil {
		return err
	}
	p.markValidUplink(ctx, raw.SN)
	p.cacheProtocolSnapshot(ctx, raw.SN, "parallel", envelope.T, data)
	logger.Info("Parallel state processed", zap.String("sn", raw.SN), zap.String("mode", data.Mode),
		zap.Int("count", data.Count), zap.String("sync_state", data.SyncState))
	return nil
}

// handleThreePhase 处理三相数据消息（three_phase topic）
// 解析三相电压/电流/功率数据，校验数组长度，
// 通过内部 API 转发给 api_server，并写入 Redis 实时缓存。
func (p *ProtocolParser) handleThreePhase(ctx context.Context, raw *RawMessage) error {
	envelope, err := parseV1UpstreamEnvelope(raw.Payload)
	if err != nil {
		return permanentMessage("INVALID_THREE_PHASE", fmt.Errorf("three_phase: %w", err))
	}
	if !v1DeviceSNPattern.MatchString(raw.SN) {
		return permanentMessage("INVALID_THREE_PHASE", fmt.Errorf("three_phase: invalid topic device SN"))
	}
	var data threePhaseDataV1
	if err := decodeStrictV1Data(envelope.Data, &data,
		"voltage", "current", "active_power", "total_active_power", "line_voltage", "frequency",
		"voltage_unbalance", "current_unbalance"); err != nil {
		return permanentMessage("INVALID_THREE_PHASE", fmt.Errorf("three_phase: %w", err))
	}
	if err := validateThreePhaseV1(&data); err != nil {
		return permanentMessage("INVALID_THREE_PHASE", fmt.Errorf("three_phase: %w", err))
	}
	receivedAt, err := rawMessageReceivedAt(raw)
	if err != nil {
		return permanentMessage("INVALID_THREE_PHASE", fmt.Errorf("three_phase: %w", err))
	}
	request := internalEnvelopeRequest{
		SN: raw.SN, Topic: "three_phase", ReceivedAt: receivedAt,
		Envelope: append(json.RawMessage(nil), raw.Payload...),
	}
	if err := p.postInternal("/api/v1/internal/three-phase", request); err != nil {
		return err
	}
	p.markValidUplink(ctx, raw.SN)
	p.cacheProtocolSnapshot(ctx, raw.SN, "three_phase", envelope.T, data)
	logger.Info("Three-phase data processed", zap.String("sn", raw.SN),
		zap.Float64("total_active_power", data.TotalActivePower), zap.Float64("frequency", data.Frequency))
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
	maxRetries  = 3                // API 最大尝试次数（含首次）
	httpTimeout = 15 * time.Second // 单次 HTTP 请求超时
)

// TelemetryBatcher sends the API's batch-shaped payload synchronously. It
// intentionally contains no fire-and-forget buffer because Kafka offsets must
// not be committed before durable downstream acceptance.
type TelemetryBatcher struct {
	client      *http.Client
	apiURL      string
	internalKey string
}

func NewTelemetryBatcher(apiServer, internalKey string) *TelemetryBatcher {
	return &TelemetryBatcher{
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

// Send delivers one telemetry item and returns only after the API accepted it.
// It is used by the Kafka consumer so an offset is never committed for a
// message that only exists in an in-memory batch buffer.
func (b *TelemetryBatcher) Send(ctx context.Context, item *telemetryBatchItem) error {
	var lastErr error
	for attempt := 0; attempt < maxRetries; attempt++ {
		if attempt > 0 {
			if !waitConsumerRetry(ctx, retryBackoff(time.Second, attempt)) {
				return ctx.Err()
			}
		}
		if err := b.sendBatchContext(ctx, []*telemetryBatchItem{item}); err == nil {
			return nil
		} else {
			lastErr = err
		}
	}
	return fmt.Errorf("send telemetry after %d attempts: %w", maxRetries, lastErr)
}

func (b *TelemetryBatcher) sendBatchContext(parent context.Context, batch []*telemetryBatchItem) error {
	body, err := json.Marshal(batch)
	if err != nil {
		return fmt.Errorf("marshal batch: %w", err)
	}

	ctx, cancel := context.WithTimeout(parent, httpTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, b.apiURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if b.internalKey != "" {
		req.Header.Set("X-Internal-Key", b.internalKey)
	}

	resp, err := b.client.Do(req)
	if err != nil {
		return fmt.Errorf("send request: %w", err)
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		return &downstreamHTTPError{status: resp.StatusCode, body: string(respBody)}
	}

	logger.Info("TelemetryBatcher: batch sent successfully",
		zap.Int("count", len(batch)))
	return nil
}
