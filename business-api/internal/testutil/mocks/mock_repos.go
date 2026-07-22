// Package mocks 提供 inv_api_server 所有 Repository 接口的手工 mock 实现。
// 每个 mock 结构体均实现对应的接口，所有方法返回零值或可通过字段配置的返回值。
//
// 使用方式：
//
//	mock := &MockUserRepo{}
//	mock.GetByIDFunc = func(ctx context.Context, id int64) (*model.User, error) {
//	    return testutil.NewTestUser(), nil
//	}
//	user, err := mock.GetByID(ctx, 1)
package mocks

import (
	"context"
	"sync"

	"inv-api-server/internal/model"
	"inv-api-server/internal/testutil"
)

// ==================== MockUserRepo ====================

// MockUserRepo 实现 testutil.UserRepo 接口
type MockUserRepo struct {
	mu sync.Mutex

	GetByIDFunc            func(ctx context.Context, id int64) (*model.User, error)
	GetByPhoneFunc         func(ctx context.Context, phone string) (*model.User, error)
	GetByEmailFunc         func(ctx context.Context, email string) (*model.User, error)
	GetByNicknameFunc      func(ctx context.Context, nickname string) (*model.User, error)
	CreateFunc             func(ctx context.Context, user *model.User) error
	UpdatePasswordFunc     func(ctx context.Context, userID int64, passwordHash string) error
	UpdateProfileFunc      func(ctx context.Context, userID int64, nickname, avatar, tz string) error
	UpdateLoginInfoFunc    func(ctx context.Context, userID int64, ip string) error
	DeleteFunc             func(ctx context.Context, userID int64) error
	ListAllFunc            func(ctx context.Context) ([]model.User, error)
	ListFunc               func(ctx context.Context, params testutil.ListUsersParams) (*testutil.ListUsersResult, error)
	ListByParentIDFunc     func(ctx context.Context, parentID int64, page, pageSize int) ([]*model.User, int64, error)
	UpdateParentIDFunc     func(ctx context.Context, userID int64, parentID *int64) error
	UpdateRoleFunc         func(ctx context.Context, userID int64, role int) error
	UpdateStatusFunc       func(ctx context.Context, userID int64, status int) error
	LogAuditFunc           func(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string)
	GetUserRoleIDsFunc     func(ctx context.Context, userID int64) ([]int64, error)
	GetRolePermissionsFunc func(ctx context.Context, roleID int64) ([]testutil.PermissionEntry, error)
	UpsertPermissionFunc   func(ctx context.Context, role int, resource string, action string, isAllowed bool) error

	// 调用记录
	Calls []MockCall
}

// MockCall 记录一次 mock 方法调用
type MockCall struct {
	Method string
	Args   []interface{}
}

func (m *MockUserRepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

// GetCallCount 返回指定方法的调用次数
func (m *MockUserRepo) GetCallCount(method string) int {
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

func (m *MockUserRepo) GetByID(ctx context.Context, id int64) (*model.User, error) {
	m.record("GetByID", id)
	if m.GetByIDFunc != nil {
		return m.GetByIDFunc(ctx, id)
	}
	return nil, nil
}

func (m *MockUserRepo) GetByPhone(ctx context.Context, phone string) (*model.User, error) {
	m.record("GetByPhone", phone)
	if m.GetByPhoneFunc != nil {
		return m.GetByPhoneFunc(ctx, phone)
	}
	return nil, nil
}

func (m *MockUserRepo) GetByEmail(ctx context.Context, email string) (*model.User, error) {
	m.record("GetByEmail", email)
	if m.GetByEmailFunc != nil {
		return m.GetByEmailFunc(ctx, email)
	}
	return nil, nil
}

func (m *MockUserRepo) GetByNickname(ctx context.Context, nickname string) (*model.User, error) {
	m.record("GetByNickname", nickname)
	if m.GetByNicknameFunc != nil {
		return m.GetByNicknameFunc(ctx, nickname)
	}
	return nil, nil
}

func (m *MockUserRepo) Create(ctx context.Context, user *model.User) error {
	m.record("Create", user)
	if m.CreateFunc != nil {
		return m.CreateFunc(ctx, user)
	}
	return nil
}

func (m *MockUserRepo) UpdatePassword(ctx context.Context, userID int64, passwordHash string) error {
	m.record("UpdatePassword", userID, passwordHash)
	if m.UpdatePasswordFunc != nil {
		return m.UpdatePasswordFunc(ctx, userID, passwordHash)
	}
	return nil
}

func (m *MockUserRepo) UpdateProfile(ctx context.Context, userID int64, nickname, avatar, tz string) error {
	m.record("UpdateProfile", userID, nickname, avatar, tz)
	if m.UpdateProfileFunc != nil {
		return m.UpdateProfileFunc(ctx, userID, nickname, avatar, tz)
	}
	return nil
}

func (m *MockUserRepo) UpdateLoginInfo(ctx context.Context, userID int64, ip string) error {
	m.record("UpdateLoginInfo", userID, ip)
	if m.UpdateLoginInfoFunc != nil {
		return m.UpdateLoginInfoFunc(ctx, userID, ip)
	}
	return nil
}

func (m *MockUserRepo) Delete(ctx context.Context, userID int64) error {
	m.record("Delete", userID)
	if m.DeleteFunc != nil {
		return m.DeleteFunc(ctx, userID)
	}
	return nil
}

func (m *MockUserRepo) ListAll(ctx context.Context) ([]model.User, error) {
	m.record("ListAll")
	if m.ListAllFunc != nil {
		return m.ListAllFunc(ctx)
	}
	return nil, nil
}

func (m *MockUserRepo) List(ctx context.Context, params testutil.ListUsersParams) (*testutil.ListUsersResult, error) {
	m.record("List", params)
	if m.ListFunc != nil {
		return m.ListFunc(ctx, params)
	}
	return &testutil.ListUsersResult{}, nil
}

func (m *MockUserRepo) ListByParentID(ctx context.Context, parentID int64, page, pageSize int) ([]*model.User, int64, error) {
	m.record("ListByParentID", parentID, page, pageSize)
	if m.ListByParentIDFunc != nil {
		return m.ListByParentIDFunc(ctx, parentID, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockUserRepo) UpdateParentID(ctx context.Context, userID int64, parentID *int64) error {
	m.record("UpdateParentID", userID, parentID)
	if m.UpdateParentIDFunc != nil {
		return m.UpdateParentIDFunc(ctx, userID, parentID)
	}
	return nil
}

func (m *MockUserRepo) UpdateRole(ctx context.Context, userID int64, role int) error {
	m.record("UpdateRole", userID, role)
	if m.UpdateRoleFunc != nil {
		return m.UpdateRoleFunc(ctx, userID, role)
	}
	return nil
}

func (m *MockUserRepo) UpdateStatus(ctx context.Context, userID int64, status int) error {
	m.record("UpdateStatus", userID, status)
	if m.UpdateStatusFunc != nil {
		return m.UpdateStatusFunc(ctx, userID, status)
	}
	return nil
}

func (m *MockUserRepo) LogAudit(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string) {
	m.record("LogAudit", operatorID, operatorName, action, resourceType, resourceID, detail, ip)
	if m.LogAuditFunc != nil {
		m.LogAuditFunc(ctx, operatorID, operatorName, action, resourceType, resourceID, detail, ip)
	}
}

func (m *MockUserRepo) GetUserRoleIDs(ctx context.Context, userID int64) ([]int64, error) {
	m.record("GetUserRoleIDs", userID)
	if m.GetUserRoleIDsFunc != nil {
		return m.GetUserRoleIDsFunc(ctx, userID)
	}
	return []int64{}, nil
}

func (m *MockUserRepo) GetRolePermissions(ctx context.Context, roleID int64) ([]testutil.PermissionEntry, error) {
	m.record("GetRolePermissions", roleID)
	if m.GetRolePermissionsFunc != nil {
		return m.GetRolePermissionsFunc(ctx, roleID)
	}
	return nil, nil
}

func (m *MockUserRepo) UpsertPermission(ctx context.Context, role int, resource string, action string, isAllowed bool) error {
	m.record("UpsertPermission", role, resource, action, isAllowed)
	if m.UpsertPermissionFunc != nil {
		return m.UpsertPermissionFunc(ctx, role, resource, action, isAllowed)
	}
	return nil
}

// ==================== MockStationRepo ====================

// MockStationRepo 实现 testutil.StationRepo 接口
type MockStationRepo struct {
	mu sync.Mutex

	CreateFunc       func(ctx context.Context, station *model.Station) error
	UpdateFunc       func(ctx context.Context, station *model.Station) error
	DeleteFunc       func(ctx context.Context, id int64) error
	AssignFunc       func(ctx context.Context, id int64, userID int64) error
	GetByIDFunc      func(ctx context.Context, id int64) (*model.Station, error)
	GetByUserIDFunc  func(ctx context.Context, userID int64, page, pageSize int) ([]*model.Station, int64, error)
	GetAllFunc       func(ctx context.Context, page, pageSize int) ([]*model.Station, int64, error)
	GetDayDataFunc   func(ctx context.Context, stationID int64, date string) (*model.StationDayData, error)
	GetStatisticsFunc func(ctx context.Context, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error)

	Calls []MockCall
}

func (m *MockStationRepo) record(method string, args ...interface{}) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = append(m.Calls, MockCall{Method: method, Args: args})
}

func (m *MockStationRepo) GetCallCount(method string) int {
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

func (m *MockStationRepo) Create(ctx context.Context, station *model.Station) error {
	m.record("Create", station)
	if m.CreateFunc != nil {
		return m.CreateFunc(ctx, station)
	}
	return nil
}

func (m *MockStationRepo) Update(ctx context.Context, station *model.Station) error {
	m.record("Update", station)
	if m.UpdateFunc != nil {
		return m.UpdateFunc(ctx, station)
	}
	return nil
}

func (m *MockStationRepo) Delete(ctx context.Context, id int64) error {
	m.record("Delete", id)
	if m.DeleteFunc != nil {
		return m.DeleteFunc(ctx, id)
	}
	return nil
}

func (m *MockStationRepo) Assign(ctx context.Context, id int64, userID int64) error {
	m.record("Assign", id, userID)
	if m.AssignFunc != nil {
		return m.AssignFunc(ctx, id, userID)
	}
	return nil
}

func (m *MockStationRepo) GetByID(ctx context.Context, id int64) (*model.Station, error) {
	m.record("GetByID", id)
	if m.GetByIDFunc != nil {
		return m.GetByIDFunc(ctx, id)
	}
	return nil, nil
}

func (m *MockStationRepo) GetByUserID(ctx context.Context, userID int64, page, pageSize int) ([]*model.Station, int64, error) {
	m.record("GetByUserID", userID, page, pageSize)
	if m.GetByUserIDFunc != nil {
		return m.GetByUserIDFunc(ctx, userID, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockStationRepo) GetAll(ctx context.Context, page, pageSize int) ([]*model.Station, int64, error) {
	m.record("GetAll", page, pageSize)
	if m.GetAllFunc != nil {
		return m.GetAllFunc(ctx, page, pageSize)
	}
	return nil, 0, nil
}

func (m *MockStationRepo) GetDayData(ctx context.Context, stationID int64, date string) (*model.StationDayData, error) {
	m.record("GetDayData", stationID, date)
	if m.GetDayDataFunc != nil {
		return m.GetDayDataFunc(ctx, stationID, date)
	}
	return nil, nil
}

func (m *MockStationRepo) GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error) {
	m.record("GetStatistics", stationID, startDate, endDate, period, tz)
	if m.GetStatisticsFunc != nil {
		return m.GetStatisticsFunc(ctx, stationID, startDate, endDate, period, tz)
	}
	return nil, nil
}
