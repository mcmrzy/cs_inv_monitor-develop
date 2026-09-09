//go:build integration

package repository

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 设备详情页三个列表接口的空结果契约（2026-09-09 审计修复）：
// Go 的 nil slice 会序列化成 JSON null，而前端 api.ts 的 expectedDataShape
// 校验（page 需 items 为数组、array 需整体为数组）会把 null 判为契约违规，
// 整页弹出「操作失败」错误条。仓储层必须返回非 nil 空切片。
//
// 复现的线上现象：
//   - GET /devices/by-sn/:sn/commands          → items: null（诊断与维护页报错 + 三列空白）
//   - GET /devices/by-sn/:sn/control-overrides → data: null（用户策略页报错）
//   - GET /devices/by-sn/:sn/battery-config    → 500（未绑定模板被当成服务端错误）

// TestGetCommandHistoryEmptyReturnsJSONArray 空命令记录必须序列化为 []。
func TestGetCommandHistoryEmptyReturnsJSONArray(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	commands, total, err := repo.GetCommandHistory(ctx, "SN-NO-COMMANDS", 1, 20)
	require.NoError(t, err)
	assert.Equal(t, int64(0), total)
	require.NotNil(t, commands, "nil slice marshals to null and breaks the page-shape contract")

	encoded, err := json.Marshal(commands)
	require.NoError(t, err)
	assert.JSONEq(t, `[]`, string(encoded))
}

// TestGetDeviceBatteryConfigMissingRowReturnsNilNoError 未绑定电池模板不是错误：
// 仓储返回 (nil, nil)，由 handler 映射为 404，避免 500「查询设备电池配置失败」。
func TestGetDeviceBatteryConfigMissingRowReturnsNilNoError(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewBatteryRepository(pool)

	cfg, err := repo.GetDeviceBatteryConfig(ctx, "SN-NO-BATTERY-CONFIG")
	require.NoError(t, err, "missing config row must not be reported as a server error")
	assert.Nil(t, cfg)
}

// TestListActiveOverridesEmptyReturnsJSONArray 空覆盖列表必须序列化为 []。
func TestListActiveOverridesEmptyReturnsJSONArray(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewEnergyScheduleRepository(pool)

	overrides, err := repo.ListActiveOverrides(ctx, "SN-NO-OVERRIDES")
	require.NoError(t, err)
	require.NotNil(t, overrides, "nil slice marshals to null and breaks the array-shape contract")

	encoded, err := json.Marshal(overrides)
	require.NoError(t, err)
	assert.JSONEq(t, `[]`, string(encoded))
}
