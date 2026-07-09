package mocks

import (
	"context"
	"sync"

	"inv-api-server/internal/model"
)

// ==================== MockModelRepo ====================

// MockModelRepo 实现 testutil.ModelRepo 接口
type MockModelRepo struct {
	mu sync.Mutex

	ListModelsFunc              func(ctx context.Context) ([]model.DeviceModel, error)
	GetModelByIDFunc            func(ctx context.Context, id int64) (*model.DeviceModel, error)
	GetModelByCodeFunc          func(ctx context.Context, code string) (*model.DeviceModel, error)
	CreateModelFunc             func(ctx context.Context, m *model.DeviceModel) error
	UpdateModelFunc             func(ctx context.Context, id int64, name *string, manufacturer *string, category *string, ratedPower *float64, description *string) error
	DeleteModelFunc             func(ctx context.Context, id int64) error
	GetFieldsByModelIDFunc      func(ctx context.Context, modelID int64) ([]model.DeviceModelField, error)
	CreateFieldFunc             func(ctx context.Context, f *model.DeviceModelField) error
	DeleteFieldFunc             func(ctx context.Context, fieldID int64) error
	GetModelIDByDeviceSNFunc    func(ctx context.Context, sn string) (int64, error)
	GetControlFieldsByModelIDFunc func(ctx context.Context, modelID int64) ([]model.DeviceModelField, error)
	GetProtocolsByModelIDFunc   func(ctx context.Context, modelID int64) ([]model.DeviceModelProtocol, error)
	CreateProtocolFunc          func(ctx context.Context, p *model.DeviceModelProtocol) error
	UpdateProtocolFunc          func(ctx context.Context, id int64, topicPattern *string, parseType *string, parseConfig map[string]interface{}, isActive *bool) error

	Calls []MockCall
}

func (m *MockModelRepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

// GetCallCount 返回指定方法的调用次数
func (m *MockModelRepo) GetCallCount(method string) int {
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

func (m *MockModelRepo) ListModels(ctx context.Context) ([]model.DeviceModel, error) {
	m.record("ListModels")
	if m.ListModelsFunc != nil {
		return m.ListModelsFunc(ctx)
	}
	return nil, nil
}

func (m *MockModelRepo) GetModelByID(ctx context.Context, id int64) (*model.DeviceModel, error) {
	m.record("GetModelByID", id)
	if m.GetModelByIDFunc != nil {
		return m.GetModelByIDFunc(ctx, id)
	}
	return nil, nil
}

func (m *MockModelRepo) GetModelByCode(ctx context.Context, code string) (*model.DeviceModel, error) {
	m.record("GetModelByCode", code)
	if m.GetModelByCodeFunc != nil {
		return m.GetModelByCodeFunc(ctx, code)
	}
	return nil, nil
}

func (m *MockModelRepo) CreateModel(ctx context.Context, dm *model.DeviceModel) error {
	m.record("CreateModel", dm)
	if m.CreateModelFunc != nil {
		return m.CreateModelFunc(ctx, dm)
	}
	return nil
}

func (m *MockModelRepo) UpdateModel(ctx context.Context, id int64, name *string, manufacturer *string, category *string, ratedPower *float64, description *string) error {
	m.record("UpdateModel", id, name, manufacturer, category, ratedPower, description)
	if m.UpdateModelFunc != nil {
		return m.UpdateModelFunc(ctx, id, name, manufacturer, category, ratedPower, description)
	}
	return nil
}

func (m *MockModelRepo) DeleteModel(ctx context.Context, id int64) error {
	m.record("DeleteModel", id)
	if m.DeleteModelFunc != nil {
		return m.DeleteModelFunc(ctx, id)
	}
	return nil
}

func (m *MockModelRepo) GetFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error) {
	m.record("GetFieldsByModelID", modelID)
	if m.GetFieldsByModelIDFunc != nil {
		return m.GetFieldsByModelIDFunc(ctx, modelID)
	}
	return nil, nil
}

func (m *MockModelRepo) CreateField(ctx context.Context, f *model.DeviceModelField) error {
	m.record("CreateField", f)
	if m.CreateFieldFunc != nil {
		return m.CreateFieldFunc(ctx, f)
	}
	return nil
}

func (m *MockModelRepo) DeleteField(ctx context.Context, fieldID int64) error {
	m.record("DeleteField", fieldID)
	if m.DeleteFieldFunc != nil {
		return m.DeleteFieldFunc(ctx, fieldID)
	}
	return nil
}

func (m *MockModelRepo) GetModelIDByDeviceSN(ctx context.Context, sn string) (int64, error) {
	m.record("GetModelIDByDeviceSN", sn)
	if m.GetModelIDByDeviceSNFunc != nil {
		return m.GetModelIDByDeviceSNFunc(ctx, sn)
	}
	return 0, nil
}

func (m *MockModelRepo) GetControlFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error) {
	m.record("GetControlFieldsByModelID", modelID)
	if m.GetControlFieldsByModelIDFunc != nil {
		return m.GetControlFieldsByModelIDFunc(ctx, modelID)
	}
	return nil, nil
}

func (m *MockModelRepo) GetProtocolsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelProtocol, error) {
	m.record("GetProtocolsByModelID", modelID)
	if m.GetProtocolsByModelIDFunc != nil {
		return m.GetProtocolsByModelIDFunc(ctx, modelID)
	}
	return nil, nil
}

func (m *MockModelRepo) CreateProtocol(ctx context.Context, p *model.DeviceModelProtocol) error {
	m.record("CreateProtocol", p)
	if m.CreateProtocolFunc != nil {
		return m.CreateProtocolFunc(ctx, p)
	}
	return nil
}

func (m *MockModelRepo) UpdateProtocol(ctx context.Context, id int64, topicPattern *string, parseType *string, parseConfig map[string]interface{}, isActive *bool) error {
	m.record("UpdateProtocol", id, topicPattern, parseType, parseConfig, isActive)
	if m.UpdateProtocolFunc != nil {
		return m.UpdateProtocolFunc(ctx, id, topicPattern, parseType, parseConfig, isActive)
	}
	return nil
}
