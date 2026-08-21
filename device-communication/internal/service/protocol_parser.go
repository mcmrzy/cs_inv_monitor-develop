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
	wg           *sync.WaitGroup     // graceful shutdown WaitGroup
	workerCount  int                 // number of concurrent Kafka consumers
	registry     *DeviceRegistry     // async device registration queue
	diagEngine   *DiagnosticEngine   // V2.1 诊断引擎（散热/并机/维护 + 健康度）

}

// DeviceRegistry handles asynchronous device registration via a buffered channel.
type DeviceRegistry struct {
	infoCh    chan *internalDeviceInfoRequest
	retryCh   chan *internalDeviceInfoRequest
	httpClient *http.Client
	apiServer  string
	internalKey string
	maxRetries int
	baseBackoff time.Duration
}

type internalDeviceInfoRequest struct {
	SN              string  `json:"sn"`
	Model           string  `json:"model"`
	Manufacturer    string  `json:"manufacturer"`
	FirmwareARM     string  `json:"firmware_arm"`
	FirmwareESP     string  `json:"firmware_esp"`
	FirmwareDSP     string  `json:"firmware_dsp"`
	FirmwareBMS     string  `json:"firmware_bms"`
	Type            string  `json:"device_type"`
	RatedPower      float64 `json:"rated_power"`
	RatedPowerW     int     `json:"rated_power_w"` // V2.1：协议 W 原值（与 rated_power 语义隔离）
	RatedVoltage    float64 `json:"rated_voltage"`
	RatedFreq       float64 `json:"rated_frequency"`
	BatteryVoltage  float64 `json:"battery_nominal_voltage"`
	BatteryType     string  `json:"battery_type"`
	CellCount       int     `json:"cell_count"`
	TempSensorCount int     `json:"temp_sensor_count"`
	// V2.1 新增只读字段（096 迁移落库列，与 model.DeviceInfo 契约同步）
	Phase             string `json:"phase"`
	InverterModule    string `json:"inverter_module"`
	HardwareVersion   string `json:"hardware_version"`
	BootloaderVersion string `json:"bootloader_version"`
	RetryCount        int    `json:"-"` // internal field for retry tracking
}

// NewDeviceRegistry creates a new async device registry with buffered channels.
func NewDeviceRegistry(apiServer, internalKey string) *DeviceRegistry {
	return &DeviceRegistry{
		infoCh:     make(chan *internalDeviceInfoRequest, 1000),
		retryCh:    make(chan *internalDeviceInfoRequest, 500),
		httpClient: &http.Client{Timeout: 5 * time.Second},
		apiServer:  strings.TrimRight(apiServer, "/"),
		internalKey: internalKey,
		maxRetries: 3,
		baseBackoff: 100 * time.Millisecond,
	}
}

// Start launches background goroutines for processing registration requests.
func (r *DeviceRegistry) Start(ctx context.Context) {
	go r.processMainQueue(ctx)
	go r.processRetryQueue(ctx)
}

// Enqueue adds a device info request to the async queue.
func (r *DeviceRegistry) Enqueue(info *internalDeviceInfoRequest) {
	select {
	case r.infoCh <- info:
		logger.Debug("Device info enqueued", zap.String("sn", info.SN))
	default:
		logger.Warn("Device registry queue full, dropping request", zap.String("sn", info.SN))
	}
}

func (r *DeviceRegistry) processMainQueue(ctx context.Context) {
	logger.Info("Device registry main queue started")
	for {
		select {
		case <-ctx.Done():
			logger.Info("Device registry main queue stopped")
			return
		case info := <-r.infoCh:
			r.processRegistration(info)
		}
	}
}

func (r *DeviceRegistry) processRetryQueue(ctx context.Context) {
	logger.Info("Device registry retry queue started")
	for {
		select {
		case <-ctx.Done():
			logger.Info("Device registry retry queue stopped")
			return
		case info := <-r.retryCh:
			// Exponential backoff before retry
			time.Sleep(r.baseBackoff * time.Duration(math.Pow(2, float64(info.RetryCount))))
			r.processRegistration(info)
		}
	}
}

func (r *DeviceRegistry) processRegistration(info *internalDeviceInfoRequest) {
	if err := r.postDeviceInfo(info); err != nil {
		logger.Warn("Device registration failed",
			zap.String("sn", info.SN),
			zap.Error(err),
			zap.Int("retry_count", info.RetryCount))
		if info.RetryCount < r.maxRetries {
			info.RetryCount++
			select {
			case r.retryCh <- info:
			default:
				logger.Error("Retry queue full, dropping request", zap.String("sn", info.SN))
			}
		} else {
			logger.Error("Max retries exceeded for device registration", zap.String("sn", info.SN))
		}
	} else {
		logger.Info("Device registered successfully", zap.String("sn", info.SN))
	}
}

func (r *DeviceRegistry) postDeviceInfo(info *internalDeviceInfoRequest) error {
	body, err := json.Marshal(info)
	if err != nil {
		return fmt.Errorf("marshal error: %w", err)
	}

	req, err := http.NewRequest("POST", r.apiServer+"/api/v1/internal/device-info", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request error: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Key", r.internalKey)

	resp, err := r.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("http error: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("status %d", resp.StatusCode)
	}
	return nil
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
	return NewProtocolParserWithWorkers(brokers, topic, groupID, repo, metaRepo, rdb, hub, apiServer, internalKey, 1)
}

// NewProtocolParserWithWorkers creates a ProtocolParser with configurable number of concurrent Kafka consumers.
// workerCount controls how many goroutines consume messages in parallel (default 1).
func NewProtocolParserWithWorkers(
	brokers []string, topic string, groupID string,
	repo *repository.DeviceRepository,
	metaRepo *repository.MetadataRepository,
	rdb *redis.Client,
	hub *mqtt.Hub,
	apiServer string,
	internalKey string,
	workerCount int,
) *ProtocolParser {
	if workerCount < 1 {
		workerCount = 1
	}
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
		workerCount:  workerCount,
		registry:     NewDeviceRegistry(apiServer, internalKey),
		diagEngine:   NewDiagnosticEngine(repo, rdb),
	}
	if repo != nil {
		parser.ingestErrors = repo
	}
	return parser
}

// SetStateManager 注入外部创建的 DeviceStateManager 实例。
// 用于依赖注入：main.go 创建共享的状态管理器后，通过此方法注入到 ProtocolParser，
// 确保 MQTT 层和 Kafka 消费层使用同一个状态管理器实例。
func (p *ProtocolParser) SetStateManager(sm *DeviceStateManager) {
	if sm != nil {
		p.stateManager = sm
	}
}

// SetWaitGroup 注入共享的 WaitGroup 用于优雅关闭。
// 在 Start 调用前设置，Start 内部会传递给 Kafka 消费者 goroutine。
func (p *ProtocolParser) SetWaitGroup(wg *sync.WaitGroup) {
	p.wg = wg
}

func (p *ProtocolParser) Start(ctx context.Context) {
	// Start multiple concurrent Kafka consumers based on workerCount
	logger.Info("Starting protocol parser workers", zap.Int("worker_count", p.workerCount))
	for i := 0; i < p.workerCount; i++ {
		workerName := fmt.Sprintf("protocol-parser-%d", i)
		go runOrderedKafkaConsumerWithRetry(ctx, workerName, p.consumer, p.processKafkaMessage, DefaultMaxRetries, DefaultBaseBackoff, nil, nil, p.wg)
	}
	// Start async device registry
	if p.registry != nil {
		p.registry.Start(ctx)
	}
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
	// Debug: log Kafka message consumption
	logger.Info("Kafka message consumed",
		zap.String("topic", message.Topic),
		zap.Int("partition", message.Partition),
		zap.Int64("offset", message.Offset),
		zap.Int("value_len", len(message.Value)))

	var raw RawMessage
	if err := json.Unmarshal(message.Value, &raw); err != nil {
		return p.isolatePermanentMessage(ctx, "", message.Topic, message.Value,
			"INVALID_BRIDGE_JSON", fmt.Errorf("decode bridge message: %w", err))
	}
	logger.Info("Kafka message parsed",
		zap.String("sn", raw.SN),
		zap.String("msg_type", raw.MsgType))
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
	// 按信封 v 分派：v==1 走旧数组路径（V1 解析器），v==2 走语义键值对（V2.1 文档 9.1）。
	var probe struct {
		Version uint16 `json:"v"`
	}
	if err := json.Unmarshal(raw.Payload, &probe); err != nil {
		return permanentMessage("INVALID_REPORTED_CONFIG", err)
	}
	if probe.Version == 2 {
		return p.handleReportedConfigV2(ctx, raw)
	}
	cfg, err := telemetryv2.ParseReportedConfig(raw.Payload)
	if err != nil {
		return permanentMessage("INVALID_REPORTED_CONFIG", err)
	}
	if err := p.repo.SaveReportedConfig(ctx, raw.SN, cfg); err != nil {
		return err
	}
	p.cacheReportedConfig(ctx, raw.SN, cfg.Values)
	return nil
}

// handleReportedConfigV2 处理 V2.1 config 语义键值对：
// schema 校验（无效键剔除）→ device_control_state 闭环（rev 防回退/sync_status）→ 审计 + Redis 缓存。
func (p *ProtocolParser) handleReportedConfigV2(ctx context.Context, raw *RawMessage) error {
	cfg, err := telemetryv2.ParseReportedConfigV2(raw.Payload)
	if err != nil {
		return permanentMessage("INVALID_REPORTED_CONFIG", err)
	}
	schemas, sErr := p.repo.LoadConfigSchema(ctx)
	if sErr != nil {
		logger.Warn("Load config schema failed, skip v2 validation", zap.String("sn", raw.SN), zap.Error(sErr))
	}
	syncStatus, invalidKeys, err := p.repo.SaveReportedConfigV2(ctx, raw.SN, cfg, schemas)
	if err != nil {
		return err
	}
	if len(invalidKeys) > 0 {
		logger.Warn("Reported config v2 params rejected by schema validation",
			zap.String("sn", raw.SN), zap.Uint64("rev", cfg.Revision), zap.Strings("keys", invalidKeys))
	}
	logger.Info("Reported config v2 saved",
		zap.String("sn", raw.SN), zap.Uint64("rev", cfg.Revision),
		zap.Int("params", len(cfg.Values)), zap.String("sync_status", syncStatus))
	p.cacheReportedConfig(ctx, raw.SN, cfg.Values)
	return nil
}

// cacheReportedConfig 缓存 config 到 Redis（24h），供管理后台/App 快速读取。
func (p *ProtocolParser) cacheReportedConfig(ctx context.Context, sn string, values map[string]any) {
	if p.rdb == nil {
		return
	}
	encoded, err := json.Marshal(values)
	if err == nil {
		_ = p.rdb.Set(ctx, "device:config:"+sn, encoded, 24*time.Hour).Err()
	}
}

func (p *ProtocolParser) handleHeartbeat(ctx context.Context, raw *RawMessage) error {
	receivedAt := time.Now().UTC()
	if raw.ReceivedAt != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, raw.ReceivedAt); err == nil {
			receivedAt = parsed.UTC()
		}
	}
	// 按 payload 的 v 字段分派：v=1 走 V1 解析（CS-I10-6k2 等旧型号），
	// v=2 走 V2 解析（CS-L10-6K2，位置数组 57 值，见 docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md）。
	var versionProbe struct {
		Version uint16 `json:"v"`
	}
	if err := json.Unmarshal(raw.Payload, &versionProbe); err != nil {
		if saveErr := p.repo.SaveIngestError(ctx, raw.SN, raw.MsgType, raw.Payload, "INVALID_HEARTBEAT", err.Error()); saveErr != nil {
			return fmt.Errorf("%v; save ingest error: %w", err, saveErr)
		}
		return nil
	}
	var sample *telemetryv2.Sample
	var parseErr error
	switch versionProbe.Version {
	case 1:
		cellCount, tempSensorCount, err := p.repo.GetDeviceCellCounts(ctx, raw.SN)
		if err != nil || cellCount <= 0 {
			cellCount = 16
		}
		if tempSensorCount <= 0 {
			tempSensorCount = 4
		}
		sample, parseErr = telemetryv2.ParseHeartbeat(raw.SN, raw.Payload, cellCount, tempSensorCount, receivedAt)
		if parseErr != nil {
			if saveErr := p.repo.SaveIngestError(ctx, raw.SN, raw.MsgType, raw.Payload, "INVALID_HEARTBEAT", parseErr.Error()); saveErr != nil {
				return fmt.Errorf("%v; save ingest error: %w", parseErr, saveErr)
			}
			return nil
		}
	case 2:
		sample, parseErr = telemetryv2.ParseHeartbeatV2(raw.SN, raw.Payload, receivedAt)
		if parseErr != nil {
			if saveErr := p.repo.SaveIngestError(ctx, raw.SN, raw.MsgType, raw.Payload, "INVALID_HEARTBEAT", parseErr.Error()); saveErr != nil {
				return fmt.Errorf("%v; save ingest error: %w", parseErr, saveErr)
			}
			return nil
		}
		// V2 推导字段：work_state（sys_status 位组合）与 battery_power（放电为正）
		deriveV2WorkState(sample)
		deriveV2BatteryPower(sample)
	default:
		if saveErr := p.repo.SaveIngestError(ctx, raw.SN, raw.MsgType, raw.Payload, "UNSUPPORTED_HEARTBEAT_VERSION", fmt.Sprintf("v=%d", versionProbe.Version)); saveErr != nil {
			return fmt.Errorf("unsupported heartbeat version %d; save ingest error: %w", versionProbe.Version, saveErr)
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

	// 故障恢复检测：fault_code=0 且设备当前处于 Fault 状态时，触发自动恢复
	faultCodeIsZero := false
	if sample.System.FaultCode != nil && *sample.System.FaultCode == 0 {
		faultCodeIsZero = true
	} else if sample.System.FaultCode == nil {
		// fault_code 字段不存在时也视为无故障
		faultCodeIsZero = true
	}
	if faultCodeIsZero && p.stateManager.GetDeviceState(ctx, raw.SN) == StateFault {
		logger.Info("Heartbeat fault_code=0 while in Fault state, triggering auto-recovery",
			zap.String("sn", raw.SN))
		if err := p.stateManager.HandleFaultRecovery(ctx, raw.SN); err != nil {
			logger.Warn("Failed to trigger fault recovery from heartbeat",
				zap.String("sn", raw.SN), zap.Error(err))
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

		// 将完整遥测数据写入 realtime:latest:{sn}，供前端实时展示
		eventTimeUnix := sample.EventTime.Unix()
		var realtime map[string]interface{}
		if sample.ProtocolVersion == 2 {
			realtime = buildRealtimeV2(sample, raw.SN, eventTimeUnix)
		} else {
			realtime = map[string]interface{}{
				"ac": map[string]interface{}{
					"data": map[string]interface{}{
						"voltage": sample.AC.Voltage, "current": sample.AC.Current,
						"active_power": sample.AC.ActivePower, "apparent_power": sample.AC.ApparentPower,
						"frequency": sample.AC.Frequency, "power_factor": sample.AC.PowerFactor,
						"load_percent": sample.AC.LoadPercent,
					},
					"timestamp": eventTimeUnix,
				},
				"batt": map[string]interface{}{
					"data": map[string]interface{}{
						"soc": sample.Battery.SOC, "soh": sample.Battery.SOH,
						"voltage": sample.Battery.Voltage, "current": sample.Battery.Current,
						"power": sample.Battery.Power, "temperature": sample.Battery.Temperature,
					},
					"timestamp": eventTimeUnix,
				},
				"pv": map[string]interface{}{
					"data": map[string]interface{}{
						"pv1_voltage": sample.PV.PV1Voltage, "pv1_current": sample.PV.PV1Current,
						"pv1_power": sample.PV.PV1Power, "pv2_voltage": sample.PV.PV2Voltage,
						"pv2_current": sample.PV.PV2Current, "pv2_power": sample.PV.PV2Power,
						"total_power": sample.PV.TotalPower,
					},
					"timestamp": eventTimeUnix,
				},
				"sys": map[string]interface{}{
					"data": map[string]interface{}{
						"work_state": sample.System.WorkState,
						"fault_code": sample.System.FaultCode, "alarm_code": sample.System.AlarmCode,
						"inverter_temperature": sample.System.InverterTemperature,
						"mos_temperature": sample.System.MOSTemperature,
						"ambient_temperature": sample.System.AmbientTemperature,
					},
					"timestamp": eventTimeUnix,
				},
				"energy": map[string]interface{}{
					"data": map[string]interface{}{
						"daily_pv": sample.Energy.DailyPV, "total_pv": sample.Energy.TotalPV,
						"daily_charge": sample.Energy.DailyCharge, "total_charge": sample.Energy.TotalCharge,
						"daily_discharge": sample.Energy.DailyDischarge, "total_discharge": sample.Energy.TotalDischarge,
						"daily_load": sample.Energy.DailyLoad, "total_load": sample.Energy.TotalLoad,
					},
					"timestamp": eventTimeUnix,
				},
			}
		}
		rtBytes, rtErr := json.Marshal(realtime)
		if rtErr == nil {
			_ = p.rdb.Set(ctx, "realtime:latest:"+raw.SN, rtBytes, 10*time.Minute).Err()
		}
	}

	// V2.1 诊断引擎：V2 心跳落库 + realtime 写入后触发（独立写入，失败不阻塞主链路，见 V2.1 文档 12.3）。
	// 回填数据不触发诊断（避免历史数据误判）。
	if sample.ProtocolVersion == 2 && p.diagEngine != nil && sample.QualityFlags&telemetryv2.QualityBackfill == 0 {
		p.diagEngine.Run(ctx, raw.SN, p.getModelID(ctx, raw.SN), sample)
	}
	return nil
}

// deriveV2WorkState 由 sys_status 位组合推导 work_state（枚举与 V1.0.26.713 完全一致）：
// Fault(bit1)→4、ACBypass(bit7)→2、StandBy(bit0)→0、其余→1(逆变)。
// L10 无关机指示位，3(关机) 保留定义不使用。见 V2.1 文档 6.3。
func deriveV2WorkState(s *telemetryv2.Sample) {
	if s.System.SysStatus == nil {
		return
	}
	st := *s.System.SysStatus
	ws := uint8(1)
	switch {
	case st&(1<<1) != 0:
		ws = 4
	case st&(1<<7) != 0:
		ws = 2
	case st&(1<<0) != 0:
		ws = 0
	}
	s.System.WorkState = &ws
}

// deriveV2BatteryPower 由充/放电功率推导 battery_power（放电为正），
// 与现有 realtime/存储的 battery_power 语义兼容。
func deriveV2BatteryPower(s *telemetryv2.Sample) {
	switch {
	case s.Battery.DischargePower != nil && s.Battery.ChargePower != nil:
		v := *s.Battery.DischargePower - *s.Battery.ChargePower
		s.Battery.Power = &v
	case s.Battery.DischargePower != nil:
		s.Battery.Power = s.Battery.DischargePower
	case s.Battery.ChargePower != nil:
		v := -(*s.Battery.ChargePower)
		s.Battery.Power = &v
	}
}

// buildRealtimeV2 组装 V2 心跳的 realtime:latest 扩展结构（组结构与前端对齐）。
// 组内 key 与 device_protocol_fields.field_key 一致（096 迁移后的文档键名），便于前端按字段能力配置动态取值。
// fan/diag/sock 为 V2.1 新增组；derived 组承载派生字段（parallel_role/parallel_health，见 V2.1 文档 6.3/12.4）。
func buildRealtimeV2(s *telemetryv2.Sample, sn string, eventTimeUnix int64) map[string]interface{} {
	realtime := map[string]interface{}{
		"sys": map[string]interface{}{
			"data": map[string]interface{}{
				"sys_status": s.System.SysStatus, "fault_code": s.System.FaultCode,
				"warning": s.System.Warning, "bms_warning": s.System.BmsWarning,
				"inverter_temperature": s.System.InverterTemperature,
				"boost_temperature":    s.System.BoostTemperature,
				"transformer_temperature": s.System.TransformerTemperature,
				"pv_temperature":          s.System.PVTemperature,
				"dc_bus_voltage":          s.System.DCBusVoltage, "load_percent": s.AC.LoadPercent,
				"battery_overcharge": s.System.BatteryOvercharge, "work_state": s.System.WorkState,
			},
			"timestamp": eventTimeUnix,
		},
		"pv": map[string]interface{}{
			"data": map[string]interface{}{
				"pv1_voltage": s.PV.PV1Voltage, "buck1_current": s.PV.Buck1Current,
				"pv2_voltage": s.PV.PV2Voltage, "buck2_current": s.PV.Buck2Current,
				"pv_total_power": s.PV.TotalPower,
			},
			"timestamp": eventTimeUnix,
		},
		"ac": map[string]interface{}{
			"data": map[string]interface{}{
				"ac_output_voltage": s.AC.Voltage, "ac_output_frequency": s.AC.Frequency,
				"output_power": s.AC.ActivePower, "output_apparent_power": s.AC.ApparentPower,
				"output_current": s.AC.Current, "grid_voltage": s.AC.GridVoltage,
				"grid_frequency": s.AC.GridFrequency, "ac_input_power": s.AC.ACInputPower,
				"ac_input_apparent_power": s.AC.ACInputApparentPower,
				"ac_bypass_power": s.AC.ACBypassPower, "ac_bypass_apparent_power": s.AC.ACBypassApparentPower,
			},
			"timestamp": eventTimeUnix,
		},
		"chr": map[string]interface{}{
			"data": map[string]interface{}{
				"ac_charge_power": s.AC.ACChargePower, "ac_charge_apparent_power": s.AC.ACChargeApparentPower,
				"ac_charge_current": s.AC.ACChargeCurrent,
			},
			"timestamp": eventTimeUnix,
		},
		"bat": map[string]interface{}{
			"data": map[string]interface{}{
				"battery_voltage": s.Battery.Voltage, "battery_soc": s.Battery.SOC,
				"battery_current": s.Battery.Current,
				"battery_charge_power": s.Battery.ChargePower, "battery_discharge_power": s.Battery.DischargePower,
				"battery_overcharge": s.System.BatteryOvercharge, "power": s.Battery.Power,
			},
			"timestamp": eventTimeUnix,
		},
		"eng": map[string]interface{}{
			"data": map[string]interface{}{
				"gen_energy_daily": s.Energy.GenDaily, "gen_energy_total": s.Energy.GenTotal,
				"daily_pv_energy": s.Energy.DailyPV, "total_pv_energy": s.Energy.TotalPV,
				"ac_charge_energy_daily": s.Energy.ACChargeDaily, "ac_charge_energy_total": s.Energy.ACChargeTotal,
				"daily_discharge_energy": s.Energy.DailyDischarge, "total_discharge_energy": s.Energy.TotalDischarge,
				"daily_charge_energy": s.Energy.DailyCharge, "total_charge_energy": s.Energy.TotalCharge,
				"ac_bypass_energy_daily": s.Energy.ACBypassDaily, "ac_bypass_energy_total": s.Energy.ACBypassTotal,
				"output_energy_daily": s.Energy.OutputDaily, "output_energy_total": s.Energy.OutputTotal,
			},
			"timestamp": eventTimeUnix,
		},
	}
	// V2.1 新增组：fan（风扇转速 %）、diag（诊断量）、sock（插座位掩码）
	if s.Fan.MPPTSpeed != nil || s.Fan.InvSpeed != nil {
		realtime["fan"] = map[string]interface{}{
			"data": map[string]interface{}{
				"mppt_fan_speed": s.Fan.MPPTSpeed, "inv_fan_speed": s.Fan.InvSpeed,
			},
			"timestamp": eventTimeUnix,
		}
	}
	if s.Diag.InvCurrent != nil || s.Diag.ParallelChargeCurrent != nil || s.Diag.WorkTimeTotal != nil {
		realtime["diag"] = map[string]interface{}{
			"data": map[string]interface{}{
				"inv_current": s.Diag.InvCurrent, "parallel_charge_current": s.Diag.ParallelChargeCurrent,
				"work_time_total": s.Diag.WorkTimeTotal,
			},
			"timestamp": eventTimeUnix,
		}
	}
	if s.Sock.PairedSocket != nil || s.Sock.OnlineSocket != nil || s.Sock.OnSocket != nil {
		realtime["sock"] = map[string]interface{}{
			"data": map[string]interface{}{
				"paired_socket": s.Sock.PairedSocket, "online_socket": s.Sock.OnlineSocket,
				"on_socket": s.Sock.OnSocket,
			},
			"timestamp": eventTimeUnix,
		}
	}
	// derived 组：并机角色/健康（见 V2.1 文档 6.3）；thermal_status/health_score/health_level 由诊断引擎补充
	realtime["derived"] = map[string]interface{}{
		"data": map[string]interface{}{
			"parallel_role":   deriveParallelRole(s),
			"parallel_health": deriveParallelHealth(s),
		},
		"timestamp": eventTimeUnix,
	}
	realtime["_sn"] = sn
	realtime["_msg_type"] = "heartbeat"
	realtime["_updated_at"] = time.Now().UTC().Format(time.RFC3339)
	realtime["_timestamp"] = eventTimeUnix
	return realtime
}

// deriveParallelRole 由插座位掩码判定并机角色：
// paired_socket>0 且 online_socket≥1 → master（主机）；仅自身在线 → standalone（单机）。
func deriveParallelRole(s *telemetryv2.Sample) string {
	if s.Sock.PairedSocket == nil {
		return "n/a"
	}
	paired := *s.Sock.PairedSocket
	if paired == 0 {
		return "standalone"
	}
	if s.Sock.OnlineSocket != nil && *s.Sock.OnlineSocket >= 1 {
		return "master"
	}
	return "standalone"
}

// deriveParallelHealth 并机健康状态：paired>0 且 online<paired → degraded；online≥paired → ok；无并机 → n/a。
func deriveParallelHealth(s *telemetryv2.Sample) string {
	if s.Sock.PairedSocket == nil || *s.Sock.PairedSocket == 0 {
		return "n/a"
	}
	paired := *s.Sock.PairedSocket
	online := uint32(0)
	if s.Sock.OnlineSocket != nil {
		online = *s.Sock.OnlineSocket
	}
	if online < paired {
		return "degraded"
	}
	return "ok"
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

	// Use async device registry for non-blocking registration
	if p.registry != nil {
		p.registry.Enqueue(&internalDeviceInfoRequest{
			SN:               info.SN,
			Model:            info.Model,
			Manufacturer:     info.Manufacturer,
			FirmwareARM:      info.FirmwareARM,
			FirmwareESP:      info.FirmwareESP,
			FirmwareDSP:      info.FirmwareDSP,
			FirmwareBMS:      info.FirmwareBMS,
			Type:             info.Type,
			RatedPower:       float64(info.RatedPower),
			RatedPowerW:      info.RatedPower,
			RatedVoltage:     float64(info.RatedVoltage),
			RatedFreq:        info.RatedFreq,
			BatteryVoltage:   info.BatteryVoltage,
			BatteryType:      info.BatteryType,
			CellCount:        info.CellCount,
			TempSensorCount:  info.TempSensorCount,
			Phase:            info.Phase,
			InverterModule:   info.InverterModule,
			HardwareVersion:  info.HardwareVersion,
			BootloaderVersion: info.BootloaderVersion,
		})
	} else {
		// Fallback to synchronous registration if registry not initialized
		if err := p.postInternal("/api/v1/internal/device-info", info); err != nil {
			return err
		}
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
				"phase":                   info.Phase,
				"inverter_module":         info.InverterModule,
				"hardware_version":        info.HardwareVersion,
				"bootloader_version":      info.BootloaderVersion,
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

	resp, err := retryHTTPPost(context.Background(), p.httpClient, p.apiServer+path, body, p.internalKey, DefaultRetryConfig())
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return &downstreamHTTPError{status: resp.StatusCode, body: string(bodyBytes)}
	}
	return nil
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
				return permanentMessage("INVALID_TELEMETRY_PAYLOAD", err)
			}
		}
	} else {
		var err error
		payloadMap, err = unwrapPayload(raw.Payload)
		if err != nil {
			return permanentMessage("INVALID_TELEMETRY_PAYLOAD", err)
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

	// V2.1 命令闭环扩展（文档 11.4）：提取 applied_args / reported_revision / result_code
	appliedArgs, reportedRevision, resultCode := extractCommandResultExtras(normalizedPayload)

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
	if resultCode != nil {
		payload["result_code"] = *resultCode
	}
	if len(appliedArgs) > 0 {
		payload["applied_args"] = json.RawMessage(appliedArgs)
	}
	if reportedRevision != nil {
		payload["reported_revision"] = *reportedRevision
	}
	if resp.Data != nil {
		payload["data"] = json.RawMessage(resp.Data)
	}

	if err := p.postInternal(endpoint, payload); err != nil {
		return err
	}

	// 命令闭环（文档 11.4.1）：设置类命令执行成功后立即下发 query_config 索取最新配置。
	// query_ 查询类命令自身豁免，避免 query_config → 成功 → query_config 无限自循环。
	if isCommandSuccess(result) && !strings.HasPrefix(resp.Cmd, "query_") && p.hub != nil {
		select {
		case p.hub.GetCmdChan() <- &mqtt.DeviceCommand{DeviceSN: raw.SN, CmdType: "query_config"}:
			logger.Info("query_config queued after command", zap.String("sn", raw.SN), zap.String("cmd", resp.Cmd))
		default:
			logger.Warn("cmd channel full, skip query_config", zap.String("sn", raw.SN))
		}
	}

	return nil
}

// extractCommandResultExtras 从归一化命令响应中提取 V2.1 扩展字段
// （applied_args / reported_revision / err），兼容扁平与嵌套 data 两种位置
// （normalizeCommandResultPayload 仅在 data 含 task_id 时提升到顶层）。
func extractCommandResultExtras(normalized []byte) (appliedArgs json.RawMessage, reportedRevision *uint64, resultCode *int) {
	var root map[string]json.RawMessage
	if err := json.Unmarshal(normalized, &root); err != nil {
		return nil, nil, nil
	}
	find := func(m map[string]json.RawMessage) {
		if raw, ok := m["applied_args"]; ok && len(bytes.TrimSpace(raw)) > 0 && string(bytes.TrimSpace(raw)) != "null" {
			appliedArgs = raw
		}
		if raw, ok := m["reported_revision"]; ok {
			var rev uint64
			if json.Unmarshal(raw, &rev) == nil && rev > 0 {
				reportedRevision = &rev
			}
		}
		if raw, ok := m["err"]; ok {
			var code int
			if json.Unmarshal(raw, &code) == nil {
				resultCode = &code
			}
		}
	}
	find(root)
	// 嵌套 data（旧格式：data 无 task_id 时 normalize 不提升）
	if resultCode == nil && reportedRevision == nil && len(appliedArgs) == 0 {
		if rawData, ok := root["data"]; ok {
			var data map[string]json.RawMessage
			if json.Unmarshal(rawData, &data) == nil {
				find(data)
			}
		}
	}
	// err 缺失时按 result 字符串映射拒绝码（文档 11.4.3）
	if resultCode == nil {
		if raw, ok := root["result"]; ok {
			var result string
			if json.Unmarshal(raw, &result) == nil {
				resultCode = mapCommandResultCode(result)
			}
		}
	}
	return appliedArgs, reportedRevision, resultCode
}

// mapCommandResultCode 拒绝码枚举映射（文档 11.4.3）：
// OK=0 / INVALID_ARGS=-2 / NOT_SUPPORTED=-4 / BUSY=-3 / EXPIRED=-6 / EXEC_FAILED=-1。
func mapCommandResultCode(result string) *int {
	result = strings.ToUpper(strings.TrimSpace(result))
	if result == "" || result == "FAILED" {
		return nil
	}
	code, ok := map[string]int{
		"OK":            0,
		"INVALID_ARGS":  -2,
		"NOT_SUPPORTED": -4,
		"BUSY":          -3,
		"EXPIRED":       -6,
		"EXEC_FAILED":   -1,
	}[result]
	if !ok {
		return nil
	}
	return &code
}

// isCommandSuccess 判断命令执行成功（OK/success，兼容大小写）。
func isCommandSuccess(result string) bool {
	switch strings.ToLower(strings.TrimSpace(result)) {
	case "ok", "success":
		return true
	}
	return false
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
