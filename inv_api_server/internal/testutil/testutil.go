// Package testutil 提供 inv_api_server 的测试基础设施，
// 包括测试数据库管理、Repository 接口定义、Gin 路由构建辅助和通用断言工具。
package testutil

import (
	"context"
	"fmt"
	"io"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"
	"time"

	"inv-api-server/internal/model"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

// ==================== 测试数据库管理 ====================

// TestDB 封装测试用数据库连接和容器信息
type TestDB struct {
	Pool      *pgxpool.Pool
	Container testcontainers.Container
	ConnStr   string
}

// SetupTestDB 启动一个 PostgreSQL 15 容器，执行所有 migration 文件，返回可用的 TestDB。
// 需要本机安装 Docker 并且 Docker daemon 正在运行。
// 测试完成后必须调用 TeardownTestDB 清理资源。
func SetupTestDB(t *testing.T) *TestDB {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	// 启动 PostgreSQL 15 容器
	pgContainer, err := postgres.Run(ctx, "postgres:15-alpine",
		postgres.WithDatabase("inv_test"),
		postgres.WithUsername("postgres"),
		postgres.WithPassword("postgres"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).
				WithStartupTimeout(60*time.Second),
		),
	)
	require.NoError(t, err, "启动 PostgreSQL 容器失败")

	connStr, err := pgContainer.ConnectionString(ctx, "sslmode=disable")
	require.NoError(t, err, "获取连接字符串失败")

	// 创建连接池
	pool, err := pgxpool.New(ctx, connStr)
	require.NoError(t, err, "创建连接池失败")

	// 执行 migration 文件
	runMigrations(t, pool)

	return &TestDB{
		Pool:      pool,
		Container: pgContainer,
		ConnStr:   connStr,
	}
}

// TeardownTestDB 关闭连接池并终止测试容器
func TeardownTestDB(t *testing.T, db *TestDB) {
	t.Helper()
	if db.Pool != nil {
		db.Pool.Close()
	}
	if db.Container != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = db.Container.Terminate(ctx)
	}
}

// runMigrations 按序号顺序执行 database/migrations/ 下所有 .up.sql 文件
func runMigrations(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()

	// 定位 migration 文件目录（相对于当前源文件向上查找）
	migrationsDir := findMigrationsDir(t)
	if migrationsDir == "" {
		t.Skip("未找到 migration 文件目录，跳过数据库初始化")
		return
	}

	// 读取并排序 migration 文件
	entries, err := filepath.Glob(filepath.Join(migrationsDir, "*.up.sql"))
	require.NoError(t, err, "读取 migration 文件失败")

	sort.Strings(entries) // 按文件名序号排序

	for _, f := range entries {
		content, err := readFileContent(f)
		require.NoError(t, err, "读取 migration 文件失败: %s", f)

		_, err = pool.Exec(context.Background(), content)
		require.NoError(t, err, "执行 migration 失败: %s", filepath.Base(f))
	}
}

// findMigrationsDir 向上查找 database/migrations 目录
func findMigrationsDir(t *testing.T) string {
	t.Helper()
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		return ""
	}

	// 从当前文件位置向上遍历
	dir := filepath.Dir(currentFile)
	for i := 0; i < 10; i++ {
		candidate := filepath.Join(dir, "database", "migrations")
		if matches, _ := filepath.Glob(filepath.Join(candidate, "*.up.sql")); len(matches) > 0 {
			return candidate
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}

// readFileContent 读取文件内容为字符串
func readFileContent(path string) (string, error) {
	data, err := io.ReadAll(mustOpen(path))
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// mustOpen 打开文件并返回 io.Reader
func mustOpen(path string) io.Reader {
	f, err := openFile(path)
	if err != nil {
		panic(fmt.Sprintf("无法打开文件: %s: %v", path, err))
	}
	return f
}

// openFile 跨平台打开文件
func openFile(path string) (io.ReadCloser, error) {
	return openFileOS(path)
}

// ==================== Repository 接口定义 ====================
// 这些接口与 repository 包中的具体结构体方法一一对应，
// 用于在测试中提供 mock 实现。

// UserRepo 用户数据访问接口
type UserRepo interface {
	GetByID(ctx context.Context, id int64) (*model.User, error)
	GetByPhone(ctx context.Context, phone string) (*model.User, error)
	GetByEmail(ctx context.Context, email string) (*model.User, error)
	GetByNickname(ctx context.Context, nickname string) (*model.User, error)
	Create(ctx context.Context, user *model.User) error
	UpdatePassword(ctx context.Context, userID int64, passwordHash string) error
	UpdateProfile(ctx context.Context, userID int64, nickname, avatar, tz string) error
	UpdateLoginInfo(ctx context.Context, userID int64, ip string) error
	Delete(ctx context.Context, userID int64) error
	ListAll(ctx context.Context) ([]model.User, error)
	List(ctx context.Context, params ListUsersParams) (*ListUsersResult, error)
	ListByParentID(ctx context.Context, parentID int64, page, pageSize int) ([]*model.User, int64, error)
	UpdateParentID(ctx context.Context, userID int64, parentID *int64) error
	UpdateRole(ctx context.Context, userID int64, role int) error
	UpdateStatus(ctx context.Context, userID int64, status int) error
	LogAudit(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string)
	GetUserRoleIDs(ctx context.Context, userID int64) ([]int64, error)
	GetRolePermissions(ctx context.Context, roleID int64) ([]PermissionEntry, error)
	UpsertPermission(ctx context.Context, role int, resource string, action string, isAllowed bool) error
}

// ListUsersParams 用户列表查询参数（与 repository.ListUsersParams 对应）
type ListUsersParams struct {
	Role     int
	Status   int
	ParentID *int64
	Keyword  string
	Page     int
	PageSize int
}

// ListUsersResult 用户列表查询结果（与 repository.ListUsersResult 对应）
type ListUsersResult struct {
	Users []*model.User
	Total int64
}

// PermissionEntry 权限条目（与 repository.PermissionEntry 对应）
type PermissionEntry struct {
	Resource string `json:"resource"`
	Action   string `json:"action"`
}

// StationRepo 电站数据访问接口
type StationRepo interface {
	Create(ctx context.Context, station *model.Station) error
	Update(ctx context.Context, station *model.Station) error
	Delete(ctx context.Context, id int64) error
	Assign(ctx context.Context, id int64, userID int64) error
	GetByID(ctx context.Context, id int64) (*model.Station, error)
	GetByUserID(ctx context.Context, userID int64, page, pageSize int) ([]*model.Station, int64, error)
	GetAll(ctx context.Context, page, pageSize int) ([]*model.Station, int64, error)
	GetDayData(ctx context.Context, stationID int64, date string) (*model.StationDayData, error)
	GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error)
}

// DeviceRepo 设备数据访问接口
type DeviceRepo interface {
	GetBySN(ctx context.Context, sn string) (*model.Device, error)
	GetByUserID(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error)
	GetAll(ctx context.Context, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error)
	GetByStationID(ctx context.Context, stationID int64) ([]*model.Device, error)
	EnsureDevice(ctx context.Context, sn string) error
	Bind(ctx context.Context, sn string, userID, stationID int64) error
	HasDataPermission(ctx context.Context, userID int64, sn string) bool
	GetAllowedDeviceSNs(ctx context.Context, userID int64) ([]string, error)
	GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error)
}

// AlarmRepo 告警数据访问接口
type AlarmRepo interface {
	GetByID(ctx context.Context, id int64) (*model.Alarm, error)
	GetByDeviceSN(ctx context.Context, sn string, page, pageSize int) ([]*model.Alarm, int64, error)
	MarkHandled(ctx context.Context, id int64, userID int64) error
	MarkRead(ctx context.Context, ids []int64, userID int64) error
	MarkIgnored(ctx context.Context, id int64) error
	Delete(ctx context.Context, id int64) error
	ClearAll(ctx context.Context) error
	GetStats(ctx context.Context, userID int64, role ...int) (map[string]interface{}, error)
}

// AlarmListParams 告警列表查询参数（与 repository.AlarmListParams 对应）
type AlarmListParams struct {
	UserID    int64
	Role      int
	DeviceSN  string
	AlarmLevel int
	Status    int
	Page      int
	PageSize  int
}

// ModelRepo 设备型号数据访问接口
type ModelRepo interface {
	ListModels(ctx context.Context) ([]model.DeviceModel, error)
	GetModelByID(ctx context.Context, id int64) (*model.DeviceModel, error)
	GetModelByCode(ctx context.Context, code string) (*model.DeviceModel, error)
	CreateModel(ctx context.Context, m *model.DeviceModel) error
	UpdateModel(ctx context.Context, id int64, name *string, manufacturer *string, category *string, ratedPower *float64, description *string) error
	DeleteModel(ctx context.Context, id int64) error
	GetFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error)
	CreateField(ctx context.Context, f *model.DeviceModelField) error
	DeleteField(ctx context.Context, fieldID int64) error
	GetModelIDByDeviceSN(ctx context.Context, sn string) (int64, error)
	GetControlFieldsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelField, error)
	GetProtocolsByModelID(ctx context.Context, modelID int64) ([]model.DeviceModelProtocol, error)
	CreateProtocol(ctx context.Context, p *model.DeviceModelProtocol) error
	UpdateProtocol(ctx context.Context, id int64, topicPattern *string, parseType *string, parseConfig map[string]interface{}, isActive *bool) error
}

// OTARepo OTA 固件与升级数据访问接口
type OTARepo interface {
	CreateFirmware(ctx context.Context, f *model.Firmware) error
	ListFirmware(ctx context.Context, modelFilter string) ([]model.Firmware, error)
	GetFirmware(ctx context.Context, id int64) (*model.Firmware, error)
	DeleteFirmware(ctx context.Context, id int64) error
	UpsertDeviceUpgrade(ctx context.Context, du *model.DeviceUpgrade) error
	GetPendingUpgradeForDevice(ctx context.Context, sn string) (*model.DeviceUpgrade, *model.Firmware, error)
	GetActiveUpgradeBySN(ctx context.Context, deviceSN string) (*model.DeviceUpgrade, error)
	UpdateUpgradeStatusByID(ctx context.Context, upgradeID int64, status string, progress int, errMsg string) error
	UpdateUpgradeStatus(ctx context.Context, deviceSN string, status string, progress int, errMsg string) (int64, error)
	ListUpgradesByFirmware(ctx context.Context, page, pageSize int) ([]model.DeviceUpgrade, int, error)
	ListUpgradesByFirmwareID(ctx context.Context, firmwareID int64) ([]model.DeviceUpgrade, error)
	DeleteUpgradesByFirmwareID(ctx context.Context, firmwareID int64) error
	GetDeviceUpgradeHistory(ctx context.Context, deviceSN string, page, pageSize int) ([]model.DeviceUpgrade, int, error)
	RetryFailedUpgrades(ctx context.Context, firmwareID int64, deviceSNs []string) error
	CancelUpgrade(ctx context.Context, deviceSN string, firmwareID int64) error
}

// ==================== Gin 测试路由构建 ====================

// TestDeps 测试依赖集合，用于构建带 mock 的 Gin 路由
type TestDeps struct {
	UserRepo    UserRepo
	StationRepo StationRepo
	DeviceRepo  DeviceRepo
	AlarmRepo   AlarmRepo
	ModelRepo   ModelRepo
	OTARepo     OTARepo
}

// NewTestRouter 创建用于测试的 Gin Engine（TestMode），
// 调用方可在此基础之上注册具体 handler 路由。
func NewTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	// 禁止 Gin 输出彩色日志
	gin.DisableConsoleColor()
	r := gin.New()
	r.Use(gin.Recovery())
	return r
}

// ==================== 通用断言 Helper ====================

// AssertNoError 断言无错误
func AssertNoError(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatalf("预期无错误，但得到: %v", err)
	}
}

// AssertModelNotEmpty 断言字符串非空
func AssertModelNotEmpty(t *testing.T, field, value string) {
	t.Helper()
	if strings.TrimSpace(value) == "" {
		t.Fatalf("字段 %s 不应为空", field)
	}
}
