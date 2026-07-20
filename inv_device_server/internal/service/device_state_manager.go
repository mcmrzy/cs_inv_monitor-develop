package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"

	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// DeviceState 设备状态枚举
type DeviceState int

const (
	StateOffline DeviceState = 0 // 离线
	StateOnline  DeviceState = 1 // 在线
	StateFault   DeviceState = 2 // 故障
)

// StateTransition 状态转换事件
type StateTransition int

const (
	EventOnlineReport     StateTransition = iota // 设备上报在线
	EventOfflineReport                           // 设备上报离线
	EventFaultDetected                           // 检测到故障
	EventFaultRecovered                          // 故障恢复
	EventHeartbeatTimeout                        // 心跳超时
	EventLWTOffline                              // LWT离线
)

// StateChangeRequest 状态变更请求
type StateChangeRequest struct {
	SN        string                 `json:"sn"`
	Event     StateTransition        `json:"event"`
	Timestamp time.Time              `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"` // 附加信息（如故障码、告警级别等）
}

// DeviceStateManager 设备状态管理器
// 集中管理设备状态转换、防抖、心跳等逻辑
type DeviceStateManager struct {
	rdb         *redis.Client
	apiEndpoint string
	internalKey string
	httpClient  *http.Client

	// 状态缓存（内存缓存，减少Redis查询）
	stateCache sync.Map // map[string]DeviceState
}

// NewDeviceStateManager 创建设备状态管理器
func NewDeviceStateManager(rdb *redis.Client, apiEndpoint string, internalKey string) *DeviceStateManager {
	return &DeviceStateManager{
		rdb:         rdb,
		apiEndpoint: apiEndpoint,
		internalKey: internalKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 50,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}
}

// HandleStateChange 处理状态变更请求
// 这是状态管理器的核心入口，所有状态变更都通过此方法处理
func (m *DeviceStateManager) HandleStateChange(ctx context.Context, req *StateChangeRequest) error {
	// 1. 获取当前状态
	currentState := m.GetDeviceState(ctx, req.SN)

	// 2. 检查状态转换是否合法
	targetState, canTransition := CanTransition(currentState, req.Event)
	if !canTransition {
		logger.Info("State transition not allowed",
			zap.String("sn", req.SN),
			zap.Int("current", int(currentState)),
			zap.Int("event", int(req.Event)),
			zap.Int("target", int(targetState)))
		return nil
	}

	// 3. 检查防抖
	if !m.shouldAllowTransition(ctx, req.SN, req.Event) {
		logger.Info("State transition debounced",
			zap.String("sn", req.SN),
			zap.Int("event", int(req.Event)))
		return nil
	}

	// 4. 特殊处理：故障恢复需要检查未处理的严重告警
	if req.Event == EventOnlineReport && currentState == StateFault {
		hasActiveAlarms, err := m.hasActiveSevereAlarms(ctx, req.SN)
		if err != nil {
			logger.Warn("Failed to check active alarms", zap.String("sn", req.SN), zap.Error(err))
		}
		if hasActiveAlarms {
			logger.Info("Device still has active severe alarms, keeping fault state",
				zap.String("sn", req.SN))
			return nil
		}
	}

	// 5. 执行状态转换
	if err := m.executeStateChange(ctx, req.SN, targetState, req.Metadata); err != nil {
		return err
	}

	// 6. 更新缓存
	m.stateCache.Store(req.SN, targetState)

	// 7. 标记防抖
	m.markTransitionExecuted(ctx, req.SN, req.Event)

	logger.Info("Device state changed",
		zap.String("sn", req.SN),
		zap.Int("from", int(currentState)),
		zap.Int("to", int(targetState)),
		zap.Int("event", int(req.Event)))

	return nil
}

// GetDeviceState 获取设备当前状态
// 优先从内存缓存获取，缓存未命中则从Redis获取
func (m *DeviceStateManager) GetDeviceState(ctx context.Context, sn string) DeviceState {
	// 1. 检查内存缓存
	if cached, ok := m.stateCache.Load(sn); ok {
		return cached.(DeviceState)
	}

	// 2. 从Redis获取
	if m.rdb == nil {
		return StateOffline
	}
	key := fmt.Sprintf("device:state:%s", sn)
	val, err := m.rdb.Get(ctx, key).Int()
	if err == nil {
		state := DeviceState(val)
		m.stateCache.Store(sn, state)
		return state
	}

	// 3. 默认返回离线
	return StateOffline
}

// UpdateHeartbeat 更新设备心跳
// 刷新Redis心跳key的TTL，同时将设备SN加入在线集合（二级索引）
func (m *DeviceStateManager) UpdateHeartbeat(ctx context.Context, sn string) error {
	if m.rdb == nil {
		return nil
	}
	key := fmt.Sprintf("device:heartbeat:%s", sn)
	// Pipeline: set heartbeat TTL + SADD to online set (secondary index for O(1) retrieval)
	pipe := m.rdb.Pipeline()
	pipe.Set(ctx, key, time.Now().Unix(), 10*time.Minute)
	pipe.SAdd(ctx, "device:online_set", sn)
	_, err := pipe.Exec(ctx)
	return err
}

// HasHeartbeat 检查设备是否有活跃的心跳
func (m *DeviceStateManager) HasHeartbeat(ctx context.Context, sn string) bool {
	if m.rdb == nil {
		return false
	}
	key := fmt.Sprintf("device:heartbeat:%s", sn)
	return m.rdb.Exists(ctx, key).Val() > 0
}

// shouldAllowTransition 检查是否允许状态转换（防抖判断）
func (m *DeviceStateManager) shouldAllowTransition(ctx context.Context, sn string, event StateTransition) bool {
	if m.rdb == nil {
		return true // 无Redis时允许转换（测试场景）
	}
	key := fmt.Sprintf("device:debounce:%s:%d", sn, event)
	exists, _ := m.rdb.Exists(ctx, key).Result()
	return exists == 0
}

// markTransitionExecuted 标记状态转换已执行
func (m *DeviceStateManager) markTransitionExecuted(ctx context.Context, sn string, event StateTransition) {
	if m.rdb == nil {
		return
	}
	ttl := getDebounceTTL(event)
	if ttl == 0 {
		return // LWT 和心跳超时事件不做防抖
	}
	key := fmt.Sprintf("device:debounce:%s:%d", sn, event)
	m.rdb.Set(ctx, key, "1", ttl)
}

// getDebounceTTL 获取不同事件的防抖TTL
func getDebounceTTL(event StateTransition) time.Duration {
	switch event {
	case EventOnlineReport, EventOfflineReport:
		return 10 * time.Second // 状态上报防抖
	case EventFaultDetected:
		return 15 * time.Second // 故障防抖
	case EventFaultRecovered:
		return 10 * time.Second // 故障恢复防抖
	case EventHeartbeatTimeout, EventLWTOffline:
		return 0 // 超时和LWT不需要防抖
	default:
		return 10 * time.Second
	}
}

// hasActiveSevereAlarms 检查设备是否有未处理的严重告警
func (m *DeviceStateManager) hasActiveSevereAlarms(ctx context.Context, sn string) (bool, error) {
	// 通过内部API查询，或者直接查询数据库
	// 这里简化实现，实际应该调用API Server的接口
	return false, nil
}

// executeStateChange 执行状态变更
func (m *DeviceStateManager) executeStateChange(ctx context.Context, sn string, targetState DeviceState, metadata map[string]interface{}) error {
	// 更新Redis状态
	if m.rdb != nil {
		key := fmt.Sprintf("device:state:%s", sn)
		m.rdb.Set(ctx, key, int(targetState), 0) // 不设置过期时间

		// 离线时从在线集合中移除
		if targetState == StateOffline {
			m.rdb.SRem(ctx, "device:online_set", sn)
			m.rdb.Del(ctx, fmt.Sprintf("device:heartbeat:%s", sn))
		}
	}

	// 通知API Server更新数据库
	payload := map[string]interface{}{
		"sn":     sn,
		"status": int(targetState),
	}
	if metadata != nil {
		for k, v := range metadata {
			payload[k] = v
		}
	}
	return m.postInternal("/api/v1/internal/device-status", payload)
}

// postInternal 调用内部API
func (m *DeviceStateManager) postInternal(path string, payload interface{}) error {
	if m.apiEndpoint == "" {
		logger.Warn("API endpoint is empty, skipping internal API call")
		return nil
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, m.apiEndpoint+path, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if m.internalKey != "" {
		req.Header.Set("X-Internal-Key", m.internalKey)
	}

	// 简化实现：单次请求，无重试
	resp, err := m.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("internal api returned status %d", resp.StatusCode)
	}
	return nil
}

// 状态转换矩阵
// 行：当前状态，列：事件，值：目标状态（-1表示不允许）
var stateTransitionMatrix = [3][6]DeviceState{
	// EventOnlineReport, EventOfflineReport, EventFaultDetected, EventFaultRecovered, EventHeartbeatTimeout, EventLWTOffline
	{StateOnline, -1, StateFault, -1, -1, -1},                                        // 当前: Offline
	{-1, StateOffline, StateFault, -1, StateOffline, StateOffline},                   // 当前: Online
	{StateOnline, StateOffline, StateFault, StateOnline, StateOffline, StateOffline}, // 当前: Fault (允许 Fault→Online)
}

// CanTransition 检查状态转换是否合法
// 返回目标状态和是否允许转换
func CanTransition(current DeviceState, event StateTransition) (DeviceState, bool) {
	if current < 0 || current > 2 || event < 0 || event > 5 {
		return current, false
	}
	// A heartbeat proves connectivity, not fault recovery. Only an explicit
	// FaultRecovered event may clear the fault state.
	if current == StateFault && event == EventOnlineReport {
		return StateFault, true
	}
	target := stateTransitionMatrix[current][event]
	if target == -1 {
		return current, false
	}
	return target, true
}

// StateToString 状态转字符串
func StateToString(state DeviceState) string {
	switch state {
	case StateOffline:
		return "offline"
	case StateOnline:
		return "online"
	case StateFault:
		return "fault"
	default:
		return "unknown"
	}
}

// EventToString 事件转字符串
func EventToString(event StateTransition) string {
	switch event {
	case EventOnlineReport:
		return "online_report"
	case EventOfflineReport:
		return "offline_report"
	case EventFaultDetected:
		return "fault_detected"
	case EventFaultRecovered:
		return "fault_recovered"
	case EventHeartbeatTimeout:
		return "heartbeat_timeout"
	case EventLWTOffline:
		return "lwt_offline"
	default:
		return "unknown"
	}
}

// infoLevelFaultCodes 信息级（alarm_level=1）故障码集合
// 这些故障码对应的事件为提示性质（如"恢复并网运行"），不应触发设备故障状态转换
var infoLevelFaultCodes = map[int64]bool{
	10: true, // 系统启动完成
	11: true, // 进入待机模式
	12: true, // 恢复并网运行
}

// isInfoLevelFaultCode 判断 fault_code 是否为信息级（不应触发故障转换）
func isInfoLevelFaultCode(fc interface{}) bool {
	var code int64
	switch v := fc.(type) {
	case float64:
		code = int64(v)
	case int:
		code = int64(v)
	case int64:
		code = v
	default:
		return false
	}
	return infoLevelFaultCodes[code]
}

// DetectAndHandleFault 检测故障状态并处理状态变更
// 用于 data/status 主题的故障检测
// 注意：此函数只检测故障，不检测恢复。故障恢复由 alarm 主题的 code=0 触发
func (m *DeviceStateManager) DetectAndHandleFault(ctx context.Context, sn string, payload map[string]interface{}) error {
	// 处理可能的嵌套格式：{"data": {"state": "fault", ...}, "timestamp": ...}
	statusData := payload
	if data, ok := payload["data"].(map[string]interface{}); ok {
		statusData = data
	}

	isFault := false
	var faultCode interface{}

	// 检测故障状态
	if state, ok := statusData["state"].(string); ok && state == "fault" {
		isFault = true
		logger.Info("Fault detected via state field",
			zap.String("sn", sn),
			zap.String("state", state))
	}

	if !isFault {
		if fc, ok := statusData["fault_code"]; ok {
			faultCode = fc
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
					zap.String("sn", sn),
					zap.Any("fault_code", fc))
			}
		}
	}

	// 如果没有检测到故障，不触发任何事件
	// 故障恢复由 alarm 主题的 code=0 触发，避免与告警消息乱序
	if !isFault {
		logger.Info("No fault detected in data/status, skipping (recovery handled by alarm topic)",
			zap.String("sn", sn))
		return nil
	}

	// 信息级故障码过滤：alarm_level=1 的故障码（如"恢复并网运行"）不触发故障状态转换
	if faultCode != nil && isInfoLevelFaultCode(faultCode) {
		logger.Info("Info-level fault_code detected, skipping fault state transition",
			zap.String("sn", sn),
			zap.Any("fault_code", faultCode))
		return nil
	}

	// 构建元数据
	metadata := map[string]interface{}{}
	if faultCode != nil {
		metadata["fault_code"] = faultCode
	}

	// 通过状态管理器处理故障事件
	return m.HandleStateChange(ctx, &StateChangeRequest{
		SN:        sn,
		Event:     EventFaultDetected,
		Timestamp: time.Now().UTC(),
		Metadata:  metadata,
	})
}

// HandleLWTOffline 处理 MQTT LWT（Last Will and Testament）离线消息。
//
// LWT 竞态条件处理：
// MQTT broker 在设备断连时发送 LWT 消息，但该消息可能延迟到达。
// 如果设备已经重连并发送了心跳（heartbeat key 存在），则说明 LWT 已过时，
// 应忽略该离线消息，避免将已重连的设备误判为离线。
//
// 只有当设备确实没有活跃心跳时，才通过状态机执行离线转换。
func (m *DeviceStateManager) HandleLWTOffline(ctx context.Context, sn string) error {
	// 竞态条件检查：如果设备有活跃的心跳，说明已重连，忽略过时的 LWT
	if m.HasHeartbeat(ctx, sn) {
		logger.Info("LWT offline ignored: device has active heartbeat (reconnected)",
			zap.String("sn", sn))
		return nil
	}

	// 无活跃心跳 → 设备确实离线
	logger.Info("LWT offline: device has no active heartbeat, processing offline transition",
		zap.String("sn", sn))
	return m.HandleStateChange(ctx, &StateChangeRequest{
		SN:        sn,
		Event:     EventLWTOffline,
		Timestamp: time.Now().UTC(),
	})
}

// HandleMQTTStatusChange 是 MQTT 设备状态主题（cs_inv/{sn}/status）的统一入口。
//
// online=true:  设备主动上报在线 → 刷新心跳 + 触发 EventOnlineReport 状态转换
// online=false: LWT 离线消息 → 通过 HandleLWTOffline 处理竞态条件
//
// 所有 MQTT 层面的设备状态变更都应通过此方法，确保状态转换经过统一的
// 状态机（防抖、合法性检查、API 通知）。
func (m *DeviceStateManager) HandleMQTTStatusChange(ctx context.Context, sn string, online bool) error {
	if online {
		// 设备上报在线：刷新心跳
		if err := m.UpdateHeartbeat(ctx, sn); err != nil {
			logger.Warn("Failed to update heartbeat on MQTT online",
				zap.String("sn", sn), zap.Error(err))
		}
		// 通过状态机处理在线状态转换（内置防抖）
		return m.HandleStateChange(ctx, &StateChangeRequest{
			SN:        sn,
			Event:     EventOnlineReport,
			Timestamp: time.Now().UTC(),
		})
	}
	// LWT 离线：通过集中的竞态条件处理器处理
	return m.HandleLWTOffline(ctx, sn)
}

// MarkDeviceOffline 将设备标记为离线。
//
// 清理 Redis 中的心跳 key 和在线集合，并通过状态机触发 EventHeartbeatTimeout
// 状态转换。用于心跳超时检测和在线集合对账（reconciler）路径。
func (m *DeviceStateManager) MarkDeviceOffline(ctx context.Context, sn string) error {
	// 通过状态机处理心跳超时事件（内置合法性检查）
	return m.HandleStateChange(ctx, &StateChangeRequest{
		SN:        sn,
		Event:     EventHeartbeatTimeout,
		Timestamp: time.Now().UTC(),
	})
}

// HandleFaultRecovery 处理故障恢复事件。
// 当告警主题收到 code=0（告警清除）时，通过此方法将设备从故障状态恢复为在线。
func (m *DeviceStateManager) HandleFaultRecovery(ctx context.Context, sn string) error {
	return m.HandleStateChange(ctx, &StateChangeRequest{
		SN:        sn,
		Event:     EventFaultRecovered,
		Timestamp: time.Now().UTC(),
	})
}
