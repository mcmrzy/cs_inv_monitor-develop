package service

import (
	"testing"
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
