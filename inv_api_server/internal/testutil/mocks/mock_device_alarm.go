package mocks

import (
	"context"
	"sync"

	"inv-api-server/internal/model"
)

// ==================== MockDeviceRepo ====================

// MockDeviceRepo 实现 testutil.DeviceRepo 接口
type MockDeviceRepo struct {
	mu sync.Mutex

	GetBySNFunc            func(ctx context.Context, sn string) (*model.Device, error)
	GetByUserIDFunc        func(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error)
	GetAllFunc             func(ctx context.Context, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error)
	GetByStationIDFunc     func(ctx context.Context, stationID int64) ([]*model.Device, error)
	EnsureDeviceFunc       func(ctx context.Context, sn string) error
	BindFunc               func(ctx context.Context, sn string, userID, stationID int64) error
	HasDataPermissionFunc  func(ctx context.Context, userID int64, sn string) bool
	GetAllowedDeviceSNsFunc func(ctx context.Context, userID int64) ([]string, error)
	GetRealtimeDataFunc    func(ctx context.Context, sn string) (map[string]interface{}, error)

	Calls []MockCall
}

func (m *MockDeviceRepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

// GetCallCount 返回指定方法的调用次数
func (m *MockDeviceRepo) GetCallCount(method string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	count := 0
	for _, c := range m.Calls {
		if c.Method == method {
			count++
		}
	}
	return count
}

func (m *MockDeviceRepo) GetBySN(ctx context.Context, sn string) (*model.Device, error) {
	m.record("GetBySN", sn)
	if m.GetBySNFunc != nil {
		return m.GetBySNFunc(ctx, sn)
	}
	return nil, nil
}

func (m *MockDeviceRepo) GetByUserID(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	m.record("GetByUserID", userID, stationID, status, page, pageSize)
	if m.GetByUserIDFunc != nil {
		return m.GetByUserIDFunc(ctx, userID, stationID, status, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockDeviceRepo) GetAll(ctx context.Context, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	m.record("GetAll", stationID, status, page, pageSize)
	if m.GetAllFunc != nil {
		return m.GetAllFunc(ctx, stationID, status, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockDeviceRepo) GetByStationID(ctx context.Context, stationID int64) ([]*model.Device, error) {
	m.record("GetByStationID", stationID)
	if m.GetByStationIDFunc != nil {
		return m.GetByStationIDFunc(ctx, stationID)
	}
	return nil, nil
}

func (m *MockDeviceRepo) EnsureDevice(ctx context.Context, sn string) error {
	m.record("EnsureDevice", sn)
	if m.EnsureDeviceFunc != nil {
		return m.EnsureDeviceFunc(ctx, sn)
	}
	return nil
}

func (m *MockDeviceRepo) Bind(ctx context.Context, sn string, userID, stationID int64) error {
	m.record("Bind", sn, userID, stationID)
	if m.BindFunc != nil {
		return m.BindFunc(ctx, sn, userID, stationID)
	}
	return nil
}

func (m *MockDeviceRepo) HasDataPermission(ctx context.Context, userID int64, sn string) bool {
	m.record("HasDataPermission", userID, sn)
	if m.HasDataPermissionFunc != nil {
		return m.HasDataPermissionFunc(ctx, userID, sn)
	}
	return false
}

func (m *MockDeviceRepo) GetAllowedDeviceSNs(ctx context.Context, userID int64) ([]string, error) {
	m.record("GetAllowedDeviceSNs", userID)
	if m.GetAllowedDeviceSNsFunc != nil {
		return m.GetAllowedDeviceSNsFunc(ctx, userID)
	}
	return nil, nil
}

func (m *MockDeviceRepo) GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error) {
	m.record("GetRealtimeData", sn)
	if m.GetRealtimeDataFunc != nil {
		return m.GetRealtimeDataFunc(ctx, sn)
	}
	return nil, nil
}

// ==================== MockAlarmRepo ====================

// MockAlarmRepo 实现 testutil.AlarmRepo 接口
type MockAlarmRepo struct {
	mu sync.Mutex

	GetByIDFunc       func(ctx context.Context, id int64) (*model.Alarm, error)
	GetByDeviceSNFunc func(ctx context.Context, sn string, page, pageSize int) ([]*model.Alarm, int64, error)
	MarkHandledFunc   func(ctx context.Context, id int64, userID int64) error
	MarkReadFunc      func(ctx context.Context, ids []int64, userID int64) error
	MarkIgnoredFunc   func(ctx context.Context, id int64) error
	DeleteFunc        func(ctx context.Context, id int64) error
	ClearAllFunc      func(ctx context.Context) error
	GetStatsFunc      func(ctx context.Context, userID int64, role ...int) (map[string]interface{}, error)

	Calls []MockCall
}

func (m *MockAlarmRepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

// GetCallCount 返回指定方法的调用次数
func (m *MockAlarmRepo) GetCallCount(method string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	count := 0
	for _, c := range m.Calls {
		if c.Method == method {
			count++
		}
	}
	return count
}

func (m *MockAlarmRepo) GetByID(ctx context.Context, id int64) (*model.Alarm, error) {
	m.record("GetByID", id)
	if m.GetByIDFunc != nil {
		return m.GetByIDFunc(ctx, id)
	}
	return nil, nil
}

func (m *MockAlarmRepo) GetByDeviceSN(ctx context.Context, sn string, page, pageSize int) ([]*model.Alarm, int64, error) {
	m.record("GetByDeviceSN", sn, page, pageSize)
	if m.GetByDeviceSNFunc != nil {
		return m.GetByDeviceSNFunc(ctx, sn, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockAlarmRepo) MarkHandled(ctx context.Context, id int64, userID int64) error {
	m.record("MarkHandled", id, userID)
	if m.MarkHandledFunc != nil {
		return m.MarkHandledFunc(ctx, id, userID)
	}
	return nil
}

func (m *MockAlarmRepo) MarkRead(ctx context.Context, ids []int64, userID int64) error {
	m.record("MarkRead", ids, userID)
	if m.MarkReadFunc != nil {
		return m.MarkReadFunc(ctx, ids, userID)
	}
	return nil
}

func (m *MockAlarmRepo) MarkIgnored(ctx context.Context, id int64) error {
	m.record("MarkIgnored", id)
	if m.MarkIgnoredFunc != nil {
		return m.MarkIgnoredFunc(ctx, id)
	}
	return nil
}

func (m *MockAlarmRepo) Delete(ctx context.Context, id int64) error {
	m.record("Delete", id)
	if m.DeleteFunc != nil {
		return m.DeleteFunc(ctx, id)
	}
	return nil
}

func (m *MockAlarmRepo) ClearAll(ctx context.Context) error {
	m.record("ClearAll")
	if m.ClearAllFunc != nil {
		return m.ClearAllFunc(ctx)
	}
	return nil
}

func (m *MockAlarmRepo) GetStats(ctx context.Context, userID int64, role ...int) (map[string]interface{}, error) {
	m.record("GetStats", userID, role)
	if m.GetStatsFunc != nil {
		return m.GetStatsFunc(ctx, userID, role...)
	}
	return map[string]interface{}{}, nil
}
