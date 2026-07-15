package service

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCanTransition(t *testing.T) {
	tests := []struct {
		name      string
		current   DeviceState
		event     StateTransition
		wantState DeviceState
		wantOk    bool
	}{
		// Offline 状态转换
		{"Offline -> Online (OnlineReport)", StateOffline, EventOnlineReport, StateOnline, true},
		{"Offline -> Fault (FaultDetected)", StateOffline, EventFaultDetected, StateFault, true},
		{"Offline -> Offline (OfflineReport) 不允许", StateOffline, EventOfflineReport, StateOffline, false},
		{"Offline -> Offline (FaultRecovered) 不允许", StateOffline, EventFaultRecovered, StateOffline, false},
		{"Offline -> Offline (HeartbeatTimeout) 不允许", StateOffline, EventHeartbeatTimeout, StateOffline, false},
		{"Offline -> Offline (LWTOffline) 不允许", StateOffline, EventLWTOffline, StateOffline, false},

		// Online 状态转换
		{"Online -> Offline (OfflineReport)", StateOnline, EventOfflineReport, StateOffline, true},
		{"Online -> Fault (FaultDetected)", StateOnline, EventFaultDetected, StateFault, true},
		{"Online -> Offline (HeartbeatTimeout)", StateOnline, EventHeartbeatTimeout, StateOffline, true},
		{"Online -> Offline (LWTOffline)", StateOnline, EventLWTOffline, StateOffline, true},
		{"Online -> Online (OnlineReport) 不允许", StateOnline, EventOnlineReport, StateOnline, false},
		{"Online -> Online (FaultRecovered) 不允许", StateOnline, EventFaultRecovered, StateOnline, false},

		// Fault 状态转换
		{"Fault -> Online (FaultRecovered)", StateFault, EventFaultRecovered, StateOnline, true},
		{"Fault -> Offline (OfflineReport)", StateFault, EventOfflineReport, StateOffline, true},
		{"Fault -> Fault (FaultDetected)", StateFault, EventFaultDetected, StateFault, true},
		{"Fault -> Offline (HeartbeatTimeout)", StateFault, EventHeartbeatTimeout, StateOffline, true},
		{"Fault -> Offline (LWTOffline)", StateFault, EventLWTOffline, StateOffline, true},
		{"Fault -> Fault (OnlineReport) 保持故障", StateFault, EventOnlineReport, StateFault, true},

		// 边界情况
		{"无效状态 (-1)", DeviceState(-1), EventOnlineReport, DeviceState(-1), false},
		{"无效状态 (3)", DeviceState(3), EventOnlineReport, DeviceState(3), false},
		{"无效事件 (-1)", StateOnline, StateTransition(-1), StateOnline, false},
		{"无效事件 (6)", StateOnline, StateTransition(6), StateOnline, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotState, gotOk := CanTransition(tt.current, tt.event)
			if gotOk != tt.wantOk {
				t.Errorf("CanTransition(%v, %v) ok = %v, want %v", tt.current, tt.event, gotOk, tt.wantOk)
			}
			if gotOk && gotState != tt.wantState {
				t.Errorf("CanTransition(%v, %v) state = %v, want %v", tt.current, tt.event, gotState, tt.wantState)
			}
		})
	}
}

func TestStateToString(t *testing.T) {
	tests := []struct {
		state DeviceState
		want  string
	}{
		{StateOffline, "offline"},
		{StateOnline, "online"},
		{StateFault, "fault"},
		{DeviceState(99), "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			if got := StateToString(tt.state); got != tt.want {
				t.Errorf("StateToString(%v) = %v, want %v", tt.state, got, tt.want)
			}
		})
	}
}

func TestEventToString(t *testing.T) {
	tests := []struct {
		event StateTransition
		want  string
	}{
		{EventOnlineReport, "online_report"},
		{EventOfflineReport, "offline_report"},
		{EventFaultDetected, "fault_detected"},
		{EventFaultRecovered, "fault_recovered"},
		{EventHeartbeatTimeout, "heartbeat_timeout"},
		{EventLWTOffline, "lwt_offline"},
		{StateTransition(99), "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			if got := EventToString(tt.event); got != tt.want {
				t.Errorf("EventToString(%v) = %v, want %v", tt.event, got, tt.want)
			}
		})
	}
}

func TestGetDebounceTTL(t *testing.T) {
	tests := []struct {
		event StateTransition
		want  int // 期望的秒数
	}{
		{EventOnlineReport, 10},
		{EventOfflineReport, 10},
		{EventFaultDetected, 15},
		{EventFaultRecovered, 10},
		{EventHeartbeatTimeout, 0},
		{EventLWTOffline, 0},
	}

	for _, tt := range tests {
		t.Run(EventToString(tt.event), func(t *testing.T) {
			got := getDebounceTTL(tt.event)
			if int(got.Seconds()) != tt.want {
				t.Errorf("getDebounceTTL(%v) = %v, want %vs", tt.event, got, tt.want)
			}
		})
	}
}

// TestStateTransitionMatrix 测试状态转换矩阵的完整性
func TestStateTransitionMatrix(t *testing.T) {
	// 验证矩阵维度
	if len(stateTransitionMatrix) != 3 {
		t.Errorf("stateTransitionMatrix rows = %d, want 3", len(stateTransitionMatrix))
	}
	for i, row := range stateTransitionMatrix {
		if len(row) != 6 {
			t.Errorf("stateTransitionMatrix row %d columns = %d, want 6", i, len(row))
		}
	}

	// 验证关键转换规则
	// 1. 故障状态只能通过 FaultRecovered 恢复为在线
	state, ok := CanTransition(StateFault, EventOnlineReport)
	if !ok || state != StateFault {
		t.Error("Fault + OnlineReport should stay Fault")
	}

	state, ok = CanTransition(StateFault, EventFaultRecovered)
	if !ok || state != StateOnline {
		t.Error("Fault + FaultRecovered should become Online")
	}

	// 2. 离线状态不能通过 FaultRecovered 恢复
	_, ok = CanTransition(StateOffline, EventFaultRecovered)
	if ok {
		t.Error("Offline + FaultRecovered should not be allowed")
	}

	// 3. 心跳超时只对在线和故障状态有效
	_, ok = CanTransition(StateOffline, EventHeartbeatTimeout)
	if ok {
		t.Error("Offline + HeartbeatTimeout should not be allowed")
	}

	state, ok = CanTransition(StateOnline, EventHeartbeatTimeout)
	if !ok || state != StateOffline {
		t.Error("Online + HeartbeatTimeout should become Offline")
	}

	state, ok = CanTransition(StateFault, EventHeartbeatTimeout)
	if !ok || state != StateOffline {
		t.Error("Fault + HeartbeatTimeout should become Offline")
	}
}

// TestDetectAndHandleFault_NoFault 测试非故障 payload 直接返回 nil，不触发后续状态变更
func TestDetectAndHandleFault_NoFault(t *testing.T) {
	manager := NewDeviceStateManager(nil, "", "")
	manager.stateCache.Store("SN001", StateOnline)

	tests := []struct {
		name    string
		payload map[string]interface{}
	}{
		{"normal state", map[string]interface{}{"state": "normal"}},
		{"fault_code zero", map[string]interface{}{"fault_code": float64(0)}},
		{"fault_code missing", map[string]interface{}{"voltage": float64(220)}},
		{"empty payload", map[string]interface{}{}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := manager.DetectAndHandleFault(context.Background(), "SN001", tt.payload)
			assert.NoError(t, err)
		})
	}
}

// TestCanTransition_Concurrent 并发竞态测试：多 goroutine 同时查询状态转换矩阵
func TestCanTransition_Concurrent(t *testing.T) {
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			state, ok := CanTransition(DeviceState(idx%3), StateTransition(idx%6))
			_ = state
			_ = ok
		}(i)
	}
	wg.Wait()
}

// TestDeviceStateManager_ConcurrentCache 并发读写状态缓存不应触发竞态
func TestDeviceStateManager_ConcurrentCache(t *testing.T) {
	manager := NewDeviceStateManager(nil, "", "")

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			sn := "SN" + string(rune('A'+idx%26))
			manager.stateCache.Store(sn, DeviceState(idx%3))
		}(i)
	}
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			sn := "SN" + string(rune('A'+idx%26))
			_, _ = manager.stateCache.Load(sn)
		}(i)
	}
	wg.Wait()
}

// TestGetDebounceTTL_Concurrent 并发读取防抖 TTL
func TestGetDebounceTTL_Concurrent(t *testing.T) {
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			ttl := getDebounceTTL(StateTransition(idx % 6))
			assert.True(t, ttl >= 0)
		}(i)
	}
	wg.Wait()
}

// TestDebounceTTLValues 验证不同事件的防抖 TTL
func TestDebounceTTLValues(t *testing.T) {
	tests := []struct {
		event    StateTransition
		expected time.Duration
	}{
		{EventOnlineReport, 10 * time.Second},
		{EventOfflineReport, 10 * time.Second},
		{EventFaultDetected, 15 * time.Second},
		{EventFaultRecovered, 10 * time.Second},
		{EventHeartbeatTimeout, 0},
		{EventLWTOffline, 0},
	}

	for _, tt := range tests {
		t.Run(EventToString(tt.event), func(t *testing.T) {
			got := getDebounceTTL(tt.event)
			assert.Equal(t, tt.expected, got)
		})
	}
}

// ==================== Test Helpers ====================

// newTestStateManager creates a DeviceStateManager backed by miniredis for testing.
// Returns the manager and a cleanup function.
func newTestStateManager(t *testing.T) (*DeviceStateManager, *miniredis.Miniredis) {
	t.Helper()
	mr, err := miniredis.Run()
	require.NoError(t, err)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() {
		_ = rdb.Close()
		mr.Close()
	})
	return NewDeviceStateManager(rdb, "", ""), mr
}

// setStateInRedis sets the device state directly in Redis for test setup.
func setStateInRedis(t *testing.T, mr *miniredis.Miniredis, sn string, state DeviceState) {
	t.Helper()
	mr.Set(fmt.Sprintf("device:state:%s", sn), fmt.Sprintf("%d", int(state)))
}

// setHeartbeatInRedis sets a heartbeat key in Redis for test setup.
func setHeartbeatInRedis(t *testing.T, mr *miniredis.Miniredis, sn string) {
	t.Helper()
	mr.Set(fmt.Sprintf("device:heartbeat:%s", sn), fmt.Sprintf("%d", time.Now().Unix()))
	mr.SAdd("device:online_set", sn)
}

// ==================== LWT Race Condition Tests ====================

// TestHandleLWTOffline_RaceCondition_Reconnected 设备已重连（心跳存在），LWT 应被忽略
func TestHandleLWTOffline_RaceCondition_Reconnected(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-LWT-001"

	// 设备当前在线，且心跳存在（设备已重连）
	setStateInRedis(t, mr, sn, StateOnline)
	setHeartbeatInRedis(t, mr, sn)
	manager.stateCache.Store(sn, StateOnline)

	// 收到延迟的 LWT 离线消息
	err := manager.HandleLWTOffline(context.Background(), sn)
	assert.NoError(t, err)

	// 设备状态应保持在线，未被 LWT 影响
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOnline, state, "device should remain online when LWT is stale")

	// 心跳 key 应仍然存在
	assert.True(t, manager.HasHeartbeat(context.Background(), sn), "heartbeat should still exist")
}

// TestHandleLWTOffline_NoHeartbeat_GenuinelyOffline 设备无心跳，LWT 应触发离线转换
func TestHandleLWTOffline_NoHeartbeat_GenuinelyOffline(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-LWT-002"

	// 设备当前在线，但心跳已过期（无心跳 key）
	setStateInRedis(t, mr, sn, StateOnline)
	manager.stateCache.Store(sn, StateOnline)
	// 不设置心跳 key → HasHeartbeat 返回 false

	// 收到 LWT 离线消息
	err := manager.HandleLWTOffline(context.Background(), sn)
	assert.NoError(t, err)

	// 设备状态应转为离线
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOffline, state, "device should transition to offline")
}

// TestHandleLWTOffline_AlreadyOffline 设备已经离线，LWT 不应触发重复转换
func TestHandleLWTOffline_AlreadyOffline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-LWT-003"

	// 设备已经是离线状态
	manager.stateCache.Store(sn, StateOffline)

	// 收到 LWT 离线消息
	err := manager.HandleLWTOffline(context.Background(), sn)
	assert.NoError(t, err)

	// 状态应保持离线（CanTransition 拒绝 Offline + LWTOffline）
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOffline, state)
}

// TestHandleLWTOffline_FaultState_NoHeartbeat 设备在故障状态且无心跳，LWT 应转为离线
func TestHandleLWTOffline_FaultState_NoHeartbeat(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-LWT-004"

	setStateInRedis(t, mr, sn, StateFault)
	manager.stateCache.Store(sn, StateFault)
	// 不设置心跳 key

	err := manager.HandleLWTOffline(context.Background(), sn)
	assert.NoError(t, err)

	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOffline, state, "fault device with no heartbeat should go offline via LWT")
}

// ==================== HandleMQTTStatusChange Tests ====================

// TestHandleMQTTStatusChange_Online 离线设备收到在线消息 → 转为在线
func TestHandleMQTTStatusChange_Online(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-MQTT-001"

	// 设备当前离线
	manager.stateCache.Store(sn, StateOffline)

	err := manager.HandleMQTTStatusChange(context.Background(), sn, true)
	assert.NoError(t, err)

	// 设备应转为在线
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOnline, state)

	// 心跳应被设置
	assert.True(t, manager.HasHeartbeat(context.Background(), sn))
}

// TestHandleMQTTStatusChange_Offline 在线设备收到 LWT 离线消息 → 转为离线
func TestHandleMQTTStatusChange_Offline(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-MQTT-002"

	// 设备当前在线，但无心跳（模拟心跳已过期）
	setStateInRedis(t, mr, sn, StateOnline)
	manager.stateCache.Store(sn, StateOnline)

	err := manager.HandleMQTTStatusChange(context.Background(), sn, false)
	assert.NoError(t, err)

	// 设备应转为离线
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOffline, state)
}

// TestHandleMQTTStatusChange_Offline_RaceCondition 在线设备有心跳时收到 LWT → 忽略
func TestHandleMQTTStatusChange_Offline_RaceCondition(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-MQTT-003"

	// 设备在线且有心跳
	setStateInRedis(t, mr, sn, StateOnline)
	setHeartbeatInRedis(t, mr, sn)
	manager.stateCache.Store(sn, StateOnline)

	err := manager.HandleMQTTStatusChange(context.Background(), sn, false)
	assert.NoError(t, err)

	// 设备应保持在线（LWT 被忽略）
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOnline, state)
}

// TestHandleMQTTStatusChange_Online_AlreadyOnline 在线设备收到在线消息 → 防抖/状态机拒绝
func TestHandleMQTTStatusChange_Online_AlreadyOnline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-MQTT-004"

	manager.stateCache.Store(sn, StateOnline)

	err := manager.HandleMQTTStatusChange(context.Background(), sn, true)
	assert.NoError(t, err)

	// 状态应保持在线（CanTransition 拒绝 Online + OnlineReport）
	state := manager.GetDeviceState(context.Background(), sn)
	assert.Equal(t, StateOnline, state)
}

// ==================== Debounce Tests ====================

// TestDebounce_OnlineReport 防抖：连续的 OnlineReport 事件，第二次应被防抖拦截
func TestDebounce_OnlineReport(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-DEBOUNCE-001"

	// 设备离线
	manager.stateCache.Store(sn, StateOffline)

	// 第一次 OnlineReport → 应转换
	err := manager.HandleStateChange(context.Background(), &StateChangeRequest{
		SN: sn, Event: EventOnlineReport, Timestamp: time.Now().UTC(),
	})
	assert.NoError(t, err)
	assert.Equal(t, StateOnline, manager.GetDeviceState(context.Background(), sn))

	// 手动将状态改回离线（模拟外部干扰），然后立即再次发送 OnlineReport
	manager.stateCache.Store(sn, StateOffline)
	// 清除 Redis 中的状态 key，模拟状态被外部重置
	_ = manager.rdb.Del(context.Background(), fmt.Sprintf("device:state:%s", sn))

	// 第二次 OnlineReport → 应被防抖拦截（debounce key 存在）
	err = manager.HandleStateChange(context.Background(), &StateChangeRequest{
		SN: sn, Event: EventOnlineReport, Timestamp: time.Now().UTC(),
	})
	assert.NoError(t, err)

	// 防抖应该阻止了转换，但因为在 nil-apiEndpoint 模式下 executeStateChange 不做 HTTP 调用
	// 所以关键是检查 debounce key 是否存在
	ctx := context.Background()
	debounceKey := fmt.Sprintf("device:debounce:%s:%d", sn, int(EventOnlineReport))
	exists, _ := manager.rdb.Exists(ctx, debounceKey).Result()
	assert.Equal(t, int64(1), exists, "debounce key should exist after first transition")
}

// TestDebounce_LWTNoDebounce LWT 和心跳超时事件不做防抖（TTL=0）
func TestDebounce_LWTNoDebounce(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-DEBOUNCE-002"

	manager.stateCache.Store(sn, StateOnline)

	// 第一次 LWTOffline → 应转换到离线
	err := manager.HandleLWTOffline(context.Background(), sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOffline, manager.GetDeviceState(context.Background(), sn))

	// LWT 的 debounce TTL 为 0，所以 markTransitionExecuted 不会设置 key
	ctx := context.Background()
	debounceKey := fmt.Sprintf("device:debounce:%s:%d", sn, int(EventLWTOffline))
	exists, _ := manager.rdb.Exists(ctx, debounceKey).Result()
	assert.Equal(t, int64(0), exists, "LWT should not set debounce key (TTL=0)")
}

// ==================== Full Lifecycle Tests ====================

// TestFullLifecycle_OfflineOnlineFaultRecoverOffline 测试完整生命周期
// offline → online → fault → fault_recovered(online) → offline
func TestFullLifecycle_OfflineOnlineFaultRecoverOffline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-LIFECYCLE-001"
	ctx := context.Background()

	// 1. 初始状态：离线
	manager.stateCache.Store(sn, StateOffline)
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))

	// 2. 设备上报在线 → online
	err := manager.HandleStateChange(ctx, &StateChangeRequest{
		SN: sn, Event: EventOnlineReport, Timestamp: time.Now().UTC(),
	})
	assert.NoError(t, err)
	assert.Equal(t, StateOnline, manager.GetDeviceState(ctx, sn))

	// 3. 检测到故障 → fault
	err = manager.HandleStateChange(ctx, &StateChangeRequest{
		SN: sn, Event: EventFaultDetected, Timestamp: time.Now().UTC(),
	})
	assert.NoError(t, err)
	assert.Equal(t, StateFault, manager.GetDeviceState(ctx, sn))

	// 4. 故障恢复 → online
	err = manager.HandleFaultRecovery(ctx, sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOnline, manager.GetDeviceState(ctx, sn))

	// 5. 心跳超时 → offline
	err = manager.MarkDeviceOffline(ctx, sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))
}

// TestFullLifecycle_OfflineOnlineOfflineViaLWT 离线→在线→LWT离线
func TestFullLifecycle_OfflineOnlineOfflineViaLWT(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-LIFECYCLE-002"
	ctx := context.Background()

	// 1. 初始离线
	manager.stateCache.Store(sn, StateOffline)

	// 2. MQTT 上报在线
	err := manager.HandleMQTTStatusChange(ctx, sn, true)
	assert.NoError(t, err)
	assert.Equal(t, StateOnline, manager.GetDeviceState(ctx, sn))
	assert.True(t, manager.HasHeartbeat(ctx, sn))

	// 3. 心跳过期（删除心跳 key 模拟 TTL 过期）
	mr.Del(fmt.Sprintf("device:heartbeat:%s", sn))

	// 4. MQTT LWT 离线消息到达 → 设备真正离线
	err = manager.HandleMQTTStatusChange(ctx, sn, false)
	assert.NoError(t, err)
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))
}

// TestFullLifecycle_OnlineReconnectAfterLWT 在线→LWT(忽略)→保持在线
func TestFullLifecycle_OnlineReconnectAfterLWT(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-LIFECYCLE-003"
	ctx := context.Background()

	// 1. 设备在线且有心跳
	manager.stateCache.Store(sn, StateOnline)
	setHeartbeatInRedis(t, mr, sn)

	// 2. 收到延迟的 LWT（但设备已重连，心跳存在）
	err := manager.HandleMQTTStatusChange(ctx, sn, false)
	assert.NoError(t, err)

	// 3. 设备应保持在线
	assert.Equal(t, StateOnline, manager.GetDeviceState(ctx, sn))
	assert.True(t, manager.HasHeartbeat(ctx, sn))
}

// ==================== MarkDeviceOffline Tests ====================

// TestMarkDeviceOffline_OnlineToOffline 在线设备通过心跳超时转为离线
func TestMarkDeviceOffline_OnlineToOffline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-MDO-001"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOnline)

	err := manager.MarkDeviceOffline(ctx, sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))
}

// TestMarkDeviceOffline_FaultToOffline 故障设备通过心跳超时转为离线
func TestMarkDeviceOffline_FaultToOffline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-MDO-002"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateFault)

	err := manager.MarkDeviceOffline(ctx, sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))
}

// TestMarkDeviceOffline_AlreadyOffline 已离线设备不应重复转换
func TestMarkDeviceOffline_AlreadyOffline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-MDO-003"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOffline)

	err := manager.MarkDeviceOffline(ctx, sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))
}

// ==================== HandleFaultRecovery Tests ====================

// TestHandleFaultRecovery_FaultToOnline 故障设备恢复为在线
func TestHandleFaultRecovery_FaultToOnline(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-FR-001"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateFault)

	err := manager.HandleFaultRecovery(ctx, sn)
	assert.NoError(t, err)
	assert.Equal(t, StateOnline, manager.GetDeviceState(ctx, sn))
}

// TestHandleFaultRecovery_OfflineNotAllowed 离线设备不能通过故障恢复转为在线
func TestHandleFaultRecovery_OfflineNotAllowed(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-FR-002"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOffline)

	err := manager.HandleFaultRecovery(ctx, sn)
	assert.NoError(t, err)
	// CanTransition(Offline, FaultRecovered) = false → 状态不变
	assert.Equal(t, StateOffline, manager.GetDeviceState(ctx, sn))
}

// ==================== ExecuteStateChange Side Effects Tests ====================

// TestExecuteStateChange_OfflineCleansRedis 离线转换应清理心跳和在线集合
func TestExecuteStateChange_OfflineCleansRedis(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-EXEC-001"
	ctx := context.Background()

	// 设置心跳和在线集合
	setHeartbeatInRedis(t, mr, sn)
	manager.stateCache.Store(sn, StateOnline)

	// 执行离线转换
	err := manager.HandleStateChange(ctx, &StateChangeRequest{
		SN: sn, Event: EventOfflineReport, Timestamp: time.Now().UTC(),
	})
	assert.NoError(t, err)

	// 心跳 key 应被删除
	assert.False(t, manager.HasHeartbeat(ctx, sn), "heartbeat should be deleted on offline")

	// 设备不应在在线集合中
	isMember, _ := manager.rdb.SIsMember(ctx, "device:online_set", sn).Result()
	assert.False(t, isMember, "device should be removed from online set")
}

// TestExecuteStateChange_OnlineSetsRedis 在线转换应设置状态 key
func TestExecuteStateChange_OnlineSetsRedis(t *testing.T) {
	manager, mr := newTestStateManager(t)
	sn := "SN-EXEC-002"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOffline)

	err := manager.HandleStateChange(ctx, &StateChangeRequest{
		SN: sn, Event: EventOnlineReport, Timestamp: time.Now().UTC(),
	})
	assert.NoError(t, err)

	// 状态 key 应被设置
	val, err := mr.Get(fmt.Sprintf("device:state:%s", sn))
	require.NoError(t, err)
	assert.Equal(t, "1", val, "device:state should be 1 (online)")
}

// ==================== Concurrent State Change Tests ====================

// TestHandleStateChange_Concurrent 并发状态变更不应 panic
func TestHandleStateChange_Concurrent(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-CONC-001"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOffline)

	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			event := EventOnlineReport
			if idx%2 == 0 {
				event = EventFaultDetected
			}
			_ = manager.HandleStateChange(ctx, &StateChangeRequest{
				SN: sn, Event: event, Timestamp: time.Now().UTC(),
			})
		}(i)
	}
	wg.Wait()

	// 最终状态应为 online 或 fault（取决于竞态），但不能 panic
	state := manager.GetDeviceState(ctx, sn)
	assert.True(t, state == StateOnline || state == StateFault, "state should be online or fault, got %d", state)
}

// TestHandleMQTTStatusChange_Concurrent 并发 MQTT 状态变更
func TestHandleMQTTStatusChange_Concurrent(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-CONC-002"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOffline)

	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			online := idx%2 == 0
			_ = manager.HandleMQTTStatusChange(ctx, sn, online)
		}(i)
	}
	wg.Wait()

	// 不应 panic，状态应为有效值
	state := manager.GetDeviceState(ctx, sn)
	assert.True(t, state >= StateOffline && state <= StateFault)
}

// ==================== DetectAndHandleFault with State Manager Tests ====================

// TestDetectAndHandleFault_FaultDetected 通过状态管理器检测故障
func TestDetectAndHandleFault_FaultDetected(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-FAULT-001"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOnline)

	payload := map[string]interface{}{
		"state":      "fault",
		"fault_code": float64(42),
	}

	err := manager.DetectAndHandleFault(ctx, sn, payload)
	assert.NoError(t, err)

	// 设备应转为故障状态
	assert.Equal(t, StateFault, manager.GetDeviceState(ctx, sn))
}

// TestDetectAndHandleFault_NestedData 嵌套格式的故障检测
func TestDetectAndHandleFault_NestedData(t *testing.T) {
	manager, _ := newTestStateManager(t)
	sn := "SN-FAULT-002"
	ctx := context.Background()

	manager.stateCache.Store(sn, StateOnline)

	payload := map[string]interface{}{
		"data": map[string]interface{}{
			"fault_code": float64(1),
		},
		"timestamp": float64(time.Now().Unix()),
	}

	err := manager.DetectAndHandleFault(ctx, sn, payload)
	assert.NoError(t, err)
	assert.Equal(t, StateFault, manager.GetDeviceState(ctx, sn))
}
