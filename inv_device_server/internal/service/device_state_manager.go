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
	EventOnlineReport    StateTransition = iota // 设备上报在线
	EventOfflineReport                          // 设备上报离线
	EventFaultDetected                          // 检测到故障
	EventFaultRecovered                         // 故障恢复
	EventHeartbeatTimeout                       // 心跳超时
	EventLWTOffline                             // LWT离线
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
// 刷新Redis心跳key的TTL
func (m *DeviceStateManager) UpdateHeartbeat(ctx context.Context, sn string) error {
	key := fmt.Sprintf("device:heartbeat:%s", sn)
	return m.rdb.Set(ctx, key, time.Now().Unix(), 120*time.Second).Err()
}

// HasHeartbeat 检查设备是否有活跃的心跳
func (m *DeviceStateManager) HasHeartbeat(ctx context.Context, sn string) bool {
	key := fmt.Sprintf("device:heartbeat:%s", sn)
	return m.rdb.Exists(ctx, key).Val() > 0
}

// shouldAllowTransition 检查是否允许状态转换（防抖判断）
func (m *DeviceStateManager) shouldAllowTransition(ctx context.Context, sn string, event StateTransition) bool {
	key := fmt.Sprintf("device:debounce:%s:%d", sn, event)
	exists, _ := m.rdb.Exists(ctx, key).Result()
	return exists == 0
}

// markTransitionExecuted 标记状态转换已执行
func (m *DeviceStateManager) markTransitionExecuted(ctx context.Context, sn string, event StateTransition) {
	key := fmt.Sprintf("device:debounce:%s:%d", sn, event)
	ttl := getDebounceTTL(event)
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
	key := fmt.Sprintf("device:state:%s", sn)
	m.rdb.Set(ctx, key, int(targetState), 0) // 不设置过期时间

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
	{StateOnline, -1, StateFault, -1, -1, -1},                      // 当前: Offline
	{-1, StateOffline, StateFault, -1, StateOffline, StateOffline},  // 当前: Online
	{StateFault, StateOffline, StateFault, StateOnline, StateOffline, StateOffline}, // 当前: Fault
}

// CanTransition 检查状态转换是否合法
// 返回目标状态和是否允许转换
func CanTransition(current DeviceState, event StateTransition) (DeviceState, bool) {
	if current < 0 || current > 2 || event < 0 || event > 5 {
		return current, false
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

	// 构建元数据
	metadata := map[string]interface{}{}
	if faultCode != nil {
		metadata["fault_code"] = faultCode
	}

	// 通过状态管理器处理故障事件
	return m.HandleStateChange(ctx, &StateChangeRequest{
		SN:        sn,
		Event:     EventFaultDetected,
		Timestamp: time.Now(),
		Metadata:  metadata,
	})
}
