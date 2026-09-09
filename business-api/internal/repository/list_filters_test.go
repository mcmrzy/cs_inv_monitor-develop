package repository

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// ── 告警列表 startTime/endTime ─────────────────────────────────────────────

// TestAppendAlarmDateRangeFilter 正向用例：两端日期均追加 created_at 范围条件，
// endTime 追加到当日 23:59:59（与 notifications 列表接口语义一致，含边界日期）。
func TestAppendAlarmDateRangeFilter(t *testing.T) {
	q, args, idx := appendAlarmDateRangeFilter("FROM alarms WHERE user_id = $1", []interface{}{int64(7)}, 2,
		"2026-01-01", "2026-01-31")

	assert.Contains(t, q, " AND created_at >= $2")
	assert.Contains(t, q, " AND created_at <= $3")
	assert.Equal(t, []interface{}{int64(7), "2026-01-01", "2026-01-31 23:59:59"}, args)
	assert.Equal(t, 4, idx)
}

// TestAppendAlarmDateRangeFilter_EmptyParamsUnchanged 边界用例：参数为空时
// 原样返回，查询行为不变。
func TestAppendAlarmDateRangeFilter_EmptyParamsUnchanged(t *testing.T) {
	q, args, idx := appendAlarmDateRangeFilter("FROM alarms WHERE 1=1", []interface{}{}, 1, "", "")

	assert.Equal(t, "FROM alarms WHERE 1=1", q)
	assert.Empty(t, args)
	assert.Equal(t, 1, idx)
}

// ── 设备列表 model / lastOnline 过滤 ───────────────────────────────────────

// TestAppendDeviceListFilters 正向用例：model 按前缀匹配（ILIKE model%），
// 最后在线时间范围按 d.last_online_at 比较，占位符序号连续。
func TestAppendDeviceListFilters(t *testing.T) {
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(2026, 1, 31, 23, 59, 59, 0, time.UTC)

	q, args, idx := appendDeviceListFilters(
		" FROM devices d WHERE d.deleted_at IS NULL", nil, 1,
		5, 1, "inv", "SP-5000", &start, &end)

	for _, want := range []string{
		" AND d.station_id = $1",
		" AND d.status = $2",
		" AND (d.sn ILIKE $3 OR d.model ILIKE $3 OR dm.model_code ILIKE $3 OR dm.model_name ILIKE $3)",
		" AND d.model ILIKE $4",
		" AND d.last_online_at >= $5",
		" AND d.last_online_at <= $6",
	} {
		assert.Contains(t, q, want)
	}
	assert.Equal(t, []interface{}{int64(5), 1, "%inv%", "SP-5000%", start, end}, args)
	assert.Equal(t, 7, idx)
}

// TestAppendDeviceListFilters_OnlyModel 正向补充：仅传 model 时也生效
// （前缀匹配，含完整型号的精确匹配）。
func TestAppendDeviceListFilters_OnlyModel(t *testing.T) {
	q, args, idx := appendDeviceListFilters(
		" FROM devices d WHERE d.deleted_at IS NULL", []interface{}{}, 1,
		0, -1, "", "SP", nil, nil)

	assert.Contains(t, q, " AND d.model ILIKE $1")
	assert.NotContains(t, q, "station_id")
	assert.NotContains(t, q, "last_online_at")
	assert.Equal(t, []interface{}{"SP%"}, args)
	assert.Equal(t, 2, idx)
}

// TestAppendDeviceListFilters_EmptyParamsUnchanged 边界用例：全部零值参数时
// 原样返回，既有查询行为不变。
func TestAppendDeviceListFilters_EmptyParamsUnchanged(t *testing.T) {
	original := " FROM devices d WHERE d.deleted_at IS NULL AND d.sn IN (SELECT sn FROM devices WHERE user_id = $1)"
	q, args, idx := appendDeviceListFilters(original, []interface{}{int64(9)}, 2,
		0, -1, "", "", nil, nil)

	assert.Equal(t, original, q)
	assert.Equal(t, []interface{}{int64(9)}, args)
	assert.Equal(t, 2, idx)
}

// TestDeviceListScopeClause 系统管理员无范围限制；普通用户限自有/共享设备。
func TestDeviceListScopeClause(t *testing.T) {
	assert.Empty(t, deviceListScopeClause(true))

	scope := deviceListScopeClause(false)
	assert.Contains(t, scope, "user_device_rel")
	assert.Contains(t, scope, "$1")
}

// ── 用户列表 org_role 过滤 ────────────────────────────────────────────────

// TestApplyUserListOrgRoleFilter 正向用例：org_role=installer 时向分页与计数查询
// 同步追加 EXISTS 过滤（ organizations.org_type 实际枚举值之一），占位符序号
// 与既有参数衔接。
func TestApplyUserListOrgRoleFilter(t *testing.T) {
	base := "SELECT id FROM users WHERE deleted_at IS NULL AND (phone ILIKE $1 OR email ILIKE $1 OR nickname ILIKE $1)"
	count := "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND (phone ILIKE $1 OR email ILIKE $1 OR nickname ILIKE $1)"

	gotBase, gotCount, args := applyUserListOrgRoleFilter(base, count, []interface{}{"%kw%"}, "installer")

	for _, q := range []string{gotBase, gotCount} {
		assert.Contains(t, q, "EXISTS")
		assert.Contains(t, q, "organization_memberships")
		assert.Contains(t, q, "organizations o ON o.id = om.organization_id AND o.deleted_at IS NULL")
		assert.Contains(t, q, "om.user_id = users.id AND om.status = 'active' AND o.org_type = $2")
	}
	assert.Equal(t, []interface{}{"%kw%", "installer"}, args)
}

// TestApplyUserListOrgRoleFilter_AdminAlias 归一化：org_admin 是 manufacturer
// 组织类型在管理端的展示别名，过滤时应映射回 manufacturer。
func TestApplyUserListOrgRoleFilter_AdminAlias(t *testing.T) {
	_, _, args := applyUserListOrgRoleFilter("Q", "Q", nil, "org_admin")
	assert.Equal(t, []interface{}{"manufacturer"}, args)
}

// TestApplyUserListOrgRoleFilter_EmptyAndUnknown 边界用例：空值原样返回
// （行为不变）；非法组织类型不追加参数错误，直接作为 org_type 等值条件，
// 匹配不到任何组织，结果为空。
func TestApplyUserListOrgRoleFilter_EmptyAndUnknown(t *testing.T) {
	gotBase, gotCount, args := applyUserListOrgRoleFilter("Q1", "Q2", nil, "")
	assert.Equal(t, "Q1", gotBase)
	assert.Equal(t, "Q2", gotCount)
	assert.Empty(t, args)

	gotBase, gotCount, args = applyUserListOrgRoleFilter("Q1", "Q2", nil, "no_such_role")
	assert.Contains(t, gotBase, "o.org_type = $1")
	assert.Contains(t, gotCount, "o.org_type = $1")
	assert.Equal(t, []interface{}{"no_such_role"}, args)
}
