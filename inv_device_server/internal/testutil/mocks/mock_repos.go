// Package mocks 提供 inv_device_server 所有 Repository 和 ProtocolAdapter 接口的手工 mock 实现。
package mocks

import (
	"context"
	"sync"

	"inv-device-server/internal/model"
	"inv-device-server/internal/testutil"
)

// MockCall 记录一次 mock 方法调用
type MockCall struct {
	Method string
	Args   []interface{}
}

// ==================== MockDeviceRepo ====================

// MockDeviceRepo 实现 testutil.DeviceRepo 接口
type MockDeviceRepo struct {
	mu sync.Mutex

	GetStationIDBySNFunc    func(ctx context.Context, sn string) (int64, error)
	GetAllActiveModelsFunc  func(ctx context.Context) ([]model.DeviceModel, error)
	GetModelFieldsFunc      func(ctx context.Context, modelID int32) ([]model.DeviceModelField, error)
	GetDeviceModelIDFunc    func(ctx context.Context, sn string) (int32, error)
	GetLatestRealtimeDataFunc func(ctx context.Context, sn string) (*model.DeviceRealtime, error)
	GetAllDevicesFunc       func(ctx context.Context) ([]testutil.DeviceSummary, error)
	GetModelProtocolsFunc   func(ctx context.Context, modelID int32) ([]model.DeviceModelProtocol, error)

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

func (m *MockDeviceRepo) GetStationIDBySN(ctx context.Context, sn string) (int64, error) {
	m.record("GetStationIDBySN", sn)
	if m.GetStationIDBySNFunc != nil {
		return m.GetStationIDBySNFunc(ctx, sn)
	}
	return 0, nil
}

func (m *MockDeviceRepo) GetAllActiveModels(ctx context.Context) ([]model.DeviceModel, error) {
	m.record("GetAllActiveModels")
	if m.GetAllActiveModelsFunc != nil {
		return m.GetAllActiveModelsFunc(ctx)
	}
	return nil, nil
}

func (m *MockDeviceRepo) GetModelFields(ctx context.Context, modelID int32) ([]model.DeviceModelField, error) {
	m.record("GetModelFields", modelID)
	if m.GetModelFieldsFunc != nil {
		return m.GetModelFieldsFunc(ctx, modelID)
	}
	return nil, nil
}

func (m *MockDeviceRepo) GetDeviceModelID(ctx context.Context, sn string) (int32, error) {
	m.record("GetDeviceModelID", sn)
	if m.GetDeviceModelIDFunc != nil {
		return m.GetDeviceModelIDFunc(ctx, sn)
	}
	return 0, nil
}

func (m *MockDeviceRepo) GetLatestRealtimeData(ctx context.Context, sn string) (*model.DeviceRealtime, error) {
	m.record("GetLatestRealtimeData", sn)
	if m.GetLatestRealtimeDataFunc != nil {
		return m.GetLatestRealtimeDataFunc(ctx, sn)
	}
	return nil, nil
}

func (m *MockDeviceRepo) GetAllDevices(ctx context.Context) ([]testutil.DeviceSummary, error) {
	m.record("GetAllDevices")
	if m.GetAllDevicesFunc != nil {
		return m.GetAllDevicesFunc(ctx)
	}
	return nil, nil
}

func (m *MockDeviceRepo) GetModelProtocols(ctx context.Context, modelID int32) ([]model.DeviceModelProtocol, error) {
	m.record("GetModelProtocols", modelID)
	if m.GetModelProtocolsFunc != nil {
		return m.GetModelProtocolsFunc(ctx, modelID)
	}
	return nil, nil
}

// ==================== MockMetadataRepo ====================

// MockMetadataRepo 实现 testutil.MetadataRepo 接口
type MockMetadataRepo struct {
	mu sync.Mutex

	LoadAllModelsFunc       func(ctx context.Context) error
	GetMetadataFunc         func(modelID int32) (*model.ModelMetadata, bool)
	GetFieldsByModelIDFunc  func(modelID int32) []*model.DeviceModelField
	GetFieldByKeyFunc       func(modelID int32, fieldKey string) *model.DeviceModelField
	ParseMetricsByModelFunc func(modelID int32, rawData map[string]interface{}) []model.ParsedField
	RefreshFunc             func(ctx context.Context) error

	Calls []MockCall
}

func (m *MockMetadataRepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

// GetCallCount 返回指定方法的调用次数
func (m *MockMetadataRepo) GetCallCount(method string) int {
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

func (m *MockMetadataRepo) LoadAllModels(ctx context.Context) error {
	m.record("LoadAllModels")
	if m.LoadAllModelsFunc != nil {
		return m.LoadAllModelsFunc(ctx)
	}
	return nil
}

func (m *MockMetadataRepo) GetMetadata(modelID int32) (*model.ModelMetadata, bool) {
	m.record("GetMetadata", modelID)
	if m.GetMetadataFunc != nil {
		return m.GetMetadataFunc(modelID)
	}
	return nil, false
}

func (m *MockMetadataRepo) GetFieldsByModelID(modelID int32) []*model.DeviceModelField {
	m.record("GetFieldsByModelID", modelID)
	if m.GetFieldsByModelIDFunc != nil {
		return m.GetFieldsByModelIDFunc(modelID)
	}
	return nil
}

func (m *MockMetadataRepo) GetFieldByKey(modelID int32, fieldKey string) *model.DeviceModelField {
	m.record("GetFieldByKey", modelID, fieldKey)
	if m.GetFieldByKeyFunc != nil {
		return m.GetFieldByKeyFunc(modelID, fieldKey)
	}
	return nil
}

func (m *MockMetadataRepo) ParseMetricsByModel(modelID int32, rawData map[string]interface{}) []model.ParsedField {
	m.record("ParseMetricsByModel", modelID, rawData)
	if m.ParseMetricsByModelFunc != nil {
		return m.ParseMetricsByModelFunc(modelID, rawData)
	}
	return nil
}

func (m *MockMetadataRepo) Refresh(ctx context.Context) error {
	m.record("Refresh")
	if m.RefreshFunc != nil {
		return m.RefreshFunc(ctx)
	}
	return nil
}

// ==================== MockProtocolAdapter ====================

// MockProtocolAdapter 实现 service.ProtocolAdapter 接口
type MockProtocolAdapter struct {
	ParseTopicFunc func(topic string, payload []byte) map[string]interface{}
	Calls          []MockCall
}

func (m *MockProtocolAdapter) ParseTopic(topic string, payload []byte) map[string]interface{} {
	m.Calls = append(m.Calls, MockCall{Method: "ParseTopic", Args: []interface{}{topic, payload}})
	if m.ParseTopicFunc != nil {
		return m.ParseTopicFunc(topic, payload)
	}
	return nil
}
