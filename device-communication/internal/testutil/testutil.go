// Package testutil 提供 inv_device_server 的测试基础设施，
// 包括 Repository 接口定义、MQTT/Redis mock 辅助和通用断言工具。
package testutil

import (
	"context"
	"sync"

	"inv-device-server/internal/model"

	"github.com/gin-gonic/gin"
)

// ==================== Repository 接口定义 ====================

// DeviceRepo 设备数据访问接口（对应 repository.DeviceRepository 的公开方法）
type DeviceRepo interface {
	GetStationIDBySN(ctx context.Context, sn string) (int64, error)
	GetAllActiveModels(ctx context.Context) ([]model.DeviceModel, error)
	GetModelFields(ctx context.Context, modelID int32) ([]model.DeviceModelField, error)
	GetDeviceModelID(ctx context.Context, sn string) (int32, error)
	GetLatestRealtimeData(ctx context.Context, sn string) (*model.DeviceRealtime, error)
	GetAllDevices(ctx context.Context) ([]DeviceSummary, error)
	GetModelProtocols(ctx context.Context, modelID int32) ([]model.DeviceModelProtocol, error)
}

// DeviceSummary 设备概要信息（与 repository.DeviceSummary 对应）
type DeviceSummary struct {
	SN      string `json:"sn"`
	ModelID int32  `json:"model_id"`
	Model   string `json:"model"`
}

// MetadataRepo 型号元数据访问接口（对应 repository.MetadataRepository 的公开方法）
type MetadataRepo interface {
	LoadAllModels(ctx context.Context) error
	GetMetadata(modelID int32) (*model.ModelMetadata, bool)
	GetFieldsByModelID(modelID int32) []*model.DeviceModelField
	GetFieldByKey(modelID int32, fieldKey string) *model.DeviceModelField
	ParseMetricsByModel(modelID int32, rawData map[string]interface{}) []model.ParsedField
	Refresh(ctx context.Context) error
}

// ==================== MQTT Mock 辅助 ====================

// MockMQTTHub 模拟 MQTT Hub，用于测试中替代真实的 MQTT/Redis 依赖
type MockMQTTHub struct {
	mu            sync.Mutex
	PublishedCmds []*model.DeviceCommand
	OnlineDevices map[string]bool
}

// NewMockMQTTHub 创建 MockMQTTHub 实例
func NewMockMQTTHub() *MockMQTTHub {
	return &MockMQTTHub{
		OnlineDevices: make(map[string]bool),
	}
}

// RecordCommand 记录一条已发送的命令
func (h *MockMQTTHub) RecordCommand(cmd *model.DeviceCommand) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.PublishedCmds = append(h.PublishedCmds, cmd)
}

// GetPublishedCmds 返回所有已记录的命令
func (h *MockMQTTHub) GetPublishedCmds() []*model.DeviceCommand {
	h.mu.Lock()
	defer h.mu.Unlock()
	result := make([]*model.DeviceCommand, len(h.PublishedCmds))
	copy(result, h.PublishedCmds)
	return result
}

// SetDeviceOnline 设置设备在线状态
func (h *MockMQTTHub) SetDeviceOnline(sn string, online bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.OnlineDevices[sn] = online
}

// IsDeviceOnline 检查设备是否在线
func (h *MockMQTTHub) IsDeviceOnline(sn string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.OnlineDevices[sn]
}

// ==================== Redis Mock 辅助 ====================

// MockRedisCache 模拟 Redis 缓存，用于测试中替代真实的 Redis 依赖
type MockRedisCache struct {
	mu   sync.RWMutex
	data map[string]string
}

// NewMockRedisCache 创建 MockRedisCache 实例
func NewMockRedisCache() *MockRedisCache {
	return &MockRedisCache{
		data: make(map[string]string),
	}
}

// Set 设置缓存值
func (c *MockRedisCache) Set(key, value string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.data[key] = value
}

// Get 获取缓存值
func (c *MockRedisCache) Get(key string) (string, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	v, ok := c.data[key]
	return v, ok
}

// Del 删除缓存值
func (c *MockRedisCache) Del(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.data, key)
}

// Clear 清空所有缓存
func (c *MockRedisCache) Clear() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.data = make(map[string]string)
}

// Keys 返回所有缓存键
func (c *MockRedisCache) Keys() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	keys := make([]string, 0, len(c.data))
	for k := range c.data {
		keys = append(keys, k)
	}
	return keys
}

// ==================== Gin 测试路由构建 ====================

// NewTestRouter 创建用于测试的 Gin Engine（TestMode）
func NewTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	gin.DisableConsoleColor()
	r := gin.New()
	r.Use(gin.Recovery())
	return r
}

// ==================== 通用断言 Helper ====================

// AssertDeviceOnline 断言设备在线
func AssertDeviceOnline(t interface{ Helper(); Fatalf(string, ...interface{}) }, hub *MockMQTTHub, sn string) {
	t.Helper()
	if !hub.IsDeviceOnline(sn) {
		t.Fatalf("设备 %s 应在线，但实际离线", sn)
	}
}

// AssertCommandSent 断言指定数量的命令已发送
func AssertCommandSent(t interface{ Helper(); Fatalf(string, ...interface{}) }, hub *MockMQTTHub, expected int) {
	t.Helper()
	cmds := hub.GetPublishedCmds()
	if len(cmds) != expected {
		t.Fatalf("预期发送 %d 条命令，实际 %d 条", expected, len(cmds))
	}
}
