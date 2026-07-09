package mocks

import (
	"context"
	"sync"

	"inv-api-server/internal/model"
)

// ==================== MockOTARepo ====================

// MockOTARepo 实现 testutil.OTARepo 接口
type MockOTARepo struct {
	mu sync.Mutex

	CreateFirmwareFunc          func(ctx context.Context, f *model.Firmware) error
	ListFirmwareFunc            func(ctx context.Context, modelFilter string) ([]model.Firmware, error)
	GetFirmwareFunc             func(ctx context.Context, id int64) (*model.Firmware, error)
	DeleteFirmwareFunc          func(ctx context.Context, id int64) error
	UpsertDeviceUpgradeFunc     func(ctx context.Context, du *model.DeviceUpgrade) error
	GetPendingUpgradeForDeviceFunc func(ctx context.Context, sn string) (*model.DeviceUpgrade, *model.Firmware, error)
	GetActiveUpgradeBySNFunc    func(ctx context.Context, deviceSN string) (*model.DeviceUpgrade, error)
	UpdateUpgradeStatusByIDFunc func(ctx context.Context, upgradeID int64, status string, progress int, errMsg string) error
	UpdateUpgradeStatusFunc     func(ctx context.Context, deviceSN string, status string, progress int, errMsg string) (int64, error)
	ListUpgradesByFirmwareFunc  func(ctx context.Context, page, pageSize int) ([]model.DeviceUpgrade, int, error)
	ListUpgradesByFirmwareIDFunc func(ctx context.Context, firmwareID int64) ([]model.DeviceUpgrade, error)
	DeleteUpgradesByFirmwareIDFunc func(ctx context.Context, firmwareID int64) error
	GetDeviceUpgradeHistoryFunc func(ctx context.Context, deviceSN string, page, pageSize int) ([]model.DeviceUpgrade, int, error)
	RetryFailedUpgradesFunc     func(ctx context.Context, firmwareID int64, deviceSNs []string) error
	CancelUpgradeFunc           func(ctx context.Context, deviceSN string, firmwareID int64) error

	Calls []MockCall
}

func (m *MockOTARepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

// GetCallCount 返回指定方法的调用次数
func (m *MockOTARepo) GetCallCount(method string) int {
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

func (m *MockOTARepo) CreateFirmware(ctx context.Context, f *model.Firmware) error {
	m.record("CreateFirmware", f)
	if m.CreateFirmwareFunc != nil {
		return m.CreateFirmwareFunc(ctx, f)
	}
	return nil
}

func (m *MockOTARepo) ListFirmware(ctx context.Context, modelFilter string) ([]model.Firmware, error) {
	m.record("ListFirmware", modelFilter)
	if m.ListFirmwareFunc != nil {
		return m.ListFirmwareFunc(ctx, modelFilter)
	}
	return nil, nil
}

func (m *MockOTARepo) GetFirmware(ctx context.Context, id int64) (*model.Firmware, error) {
	m.record("GetFirmware", id)
	if m.GetFirmwareFunc != nil {
		return m.GetFirmwareFunc(ctx, id)
	}
	return nil, nil
}

func (m *MockOTARepo) DeleteFirmware(ctx context.Context, id int64) error {
	m.record("DeleteFirmware", id)
	if m.DeleteFirmwareFunc != nil {
		return m.DeleteFirmwareFunc(ctx, id)
	}
	return nil
}

func (m *MockOTARepo) UpsertDeviceUpgrade(ctx context.Context, du *model.DeviceUpgrade) error {
	m.record("UpsertDeviceUpgrade", du)
	if m.UpsertDeviceUpgradeFunc != nil {
		return m.UpsertDeviceUpgradeFunc(ctx, du)
	}
	return nil
}

func (m *MockOTARepo) GetPendingUpgradeForDevice(ctx context.Context, sn string) (*model.DeviceUpgrade, *model.Firmware, error) {
	m.record("GetPendingUpgradeForDevice", sn)
	if m.GetPendingUpgradeForDeviceFunc != nil {
		return m.GetPendingUpgradeForDeviceFunc(ctx, sn)
	}
	return nil, nil, nil
}

func (m *MockOTARepo) GetActiveUpgradeBySN(ctx context.Context, deviceSN string) (*model.DeviceUpgrade, error) {
	m.record("GetActiveUpgradeBySN", deviceSN)
	if m.GetActiveUpgradeBySNFunc != nil {
		return m.GetActiveUpgradeBySNFunc(ctx, deviceSN)
	}
	return nil, nil
}

func (m *MockOTARepo) UpdateUpgradeStatusByID(ctx context.Context, upgradeID int64, status string, progress int, errMsg string) error {
	m.record("UpdateUpgradeStatusByID", upgradeID, status, progress, errMsg)
	if m.UpdateUpgradeStatusByIDFunc != nil {
		return m.UpdateUpgradeStatusByIDFunc(ctx, upgradeID, status, progress, errMsg)
	}
	return nil
}

func (m *MockOTARepo) UpdateUpgradeStatus(ctx context.Context, deviceSN string, status string, progress int, errMsg string) (int64, error) {
	m.record("UpdateUpgradeStatus", deviceSN, status, progress, errMsg)
	if m.UpdateUpgradeStatusFunc != nil {
		return m.UpdateUpgradeStatusFunc(ctx, deviceSN, status, progress, errMsg)
	}
	return 0, nil
}

func (m *MockOTARepo) ListUpgradesByFirmware(ctx context.Context, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	m.record("ListUpgradesByFirmware", page, pageSize)
	if m.ListUpgradesByFirmwareFunc != nil {
		return m.ListUpgradesByFirmwareFunc(ctx, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockOTARepo) ListUpgradesByFirmwareID(ctx context.Context, firmwareID int64) ([]model.DeviceUpgrade, error) {
	m.record("ListUpgradesByFirmwareID", firmwareID)
	if m.ListUpgradesByFirmwareIDFunc != nil {
		return m.ListUpgradesByFirmwareIDFunc(ctx, firmwareID)
	}
	return nil, nil
}

func (m *MockOTARepo) DeleteUpgradesByFirmwareID(ctx context.Context, firmwareID int64) error {
	m.record("DeleteUpgradesByFirmwareID", firmwareID)
	if m.DeleteUpgradesByFirmwareIDFunc != nil {
		return m.DeleteUpgradesByFirmwareIDFunc(ctx, firmwareID)
	}
	return nil
}

func (m *MockOTARepo) GetDeviceUpgradeHistory(ctx context.Context, deviceSN string, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	m.record("GetDeviceUpgradeHistory", deviceSN, page, pageSize)
	if m.GetDeviceUpgradeHistoryFunc != nil {
		return m.GetDeviceUpgradeHistoryFunc(ctx, deviceSN, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockOTARepo) RetryFailedUpgrades(ctx context.Context, firmwareID int64, deviceSNs []string) error {
	m.record("RetryFailedUpgrades", firmwareID, deviceSNs)
	if m.RetryFailedUpgradesFunc != nil {
		return m.RetryFailedUpgradesFunc(ctx, firmwareID, deviceSNs)
	}
	return nil
}

func (m *MockOTARepo) CancelUpgrade(ctx context.Context, deviceSN string, firmwareID int64) error {
	m.record("CancelUpgrade", deviceSN, firmwareID)
	if m.CancelUpgradeFunc != nil {
		return m.CancelUpgradeFunc(ctx, deviceSN, firmwareID)
	}
	return nil
}

// ==================== MockPermissionChecker ====================

// MockPermissionChecker 实现 middleware.PermissionChecker 接口
type MockPermissionChecker struct {
	CheckPermissionFunc func(userID int64, resource string, action string) bool
	Calls               []MockCall
}

func (m *MockPermissionChecker) CheckPermission(userID int64, resource string, action string) bool {
	m.Calls = append(m.Calls, MockCall{Method: "CheckPermission", Args: []interface{}{userID, resource, action}})
	if m.CheckPermissionFunc != nil {
		return m.CheckPermissionFunc(userID, resource, action)
	}
	return true
}

// ==================== MockNotificationService ====================

// MockNotificationService 实现 handler.NotificationService 接口
type MockNotificationService struct {
	ListUnreadFunc func(ctx context.Context, userID int64, limit int) ([]map[string]interface{}, error)
	MarkReadFunc   func(ctx context.Context, userID int64, notificationID int64) error
	Calls          []MockCall
}

func (m *MockNotificationService) ListUnread(ctx context.Context, userID int64, limit int) ([]map[string]interface{}, error) {
	m.Calls = append(m.Calls, MockCall{Method: "ListUnread", Args: []interface{}{userID, limit}})
	if m.ListUnreadFunc != nil {
		return m.ListUnreadFunc(ctx, userID, limit)
	}
	return nil, nil
}

func (m *MockNotificationService) MarkRead(ctx context.Context, userID int64, notificationID int64) error {
	m.Calls = append(m.Calls, MockCall{Method: "MarkRead", Args: []interface{}{userID, notificationID}})
	if m.MarkReadFunc != nil {
		return m.MarkReadFunc(ctx, userID, notificationID)
	}
	return nil
}

// ==================== MockSMSProvider ====================

// MockSMSProvider 实现 service.SMSProvider 接口
type MockSMSProvider struct {
	SendFunc func(ctx context.Context, phone, code string) error
	Calls    []MockCall
}

func (m *MockSMSProvider) Send(ctx context.Context, phone, code string) error {
	m.Calls = append(m.Calls, MockCall{Method: "Send", Args: []interface{}{phone, code}})
	if m.SendFunc != nil {
		return m.SendFunc(ctx, phone, code)
	}
	return nil
}
