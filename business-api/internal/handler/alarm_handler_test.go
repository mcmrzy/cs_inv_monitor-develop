package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestParseAlarmListParams_WithDateRange 正向用例：startTime/endTime 与既有过滤、
// 分页参数同时传入时均被正确解析（契约：YYYY-MM-DD，按 created_at 日期范围过滤）。
func TestParseAlarmListParams_WithDateRange(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet,
		"/api/v1/alarms?station_id=3&status=1&alarmLevel=2&keyword=inv&startTime=2026-01-01&endTime=2026-01-31&page=2&page_size=50", nil)
	setAuthClaimsInContext(c, 7, true, 1)

	params := parseAlarmListParams(c)

	assert.Equal(t, int64(7), params.UserID)
	assert.True(t, params.IsSystemAdmin)
	assert.Equal(t, int64(3), params.StationID)
	assert.Equal(t, 1, params.Status)
	assert.Equal(t, 2, params.AlarmLevel)
	assert.Equal(t, "inv", params.Keyword)
	assert.Equal(t, "2026-01-01", params.StartTime)
	assert.Equal(t, "2026-01-31", params.EndTime)
	assert.Equal(t, 2, params.Page)
	assert.Equal(t, 50, params.PageSize)
}

// TestParseAlarmListParams_MissingParamsKeepsBehavior 边界用例：不传 startTime/endTime
// 时两者为空（repository 不追加任何时间条件），分页与状态默认值保持原有行为。
func TestParseAlarmListParams_MissingParamsKeepsBehavior(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/api/v1/alarms", nil)
	setAuthClaimsInContext(c, 7, false, 1)

	params := parseAlarmListParams(c)

	require.NotNil(t, params)
	assert.Empty(t, params.StartTime)
	assert.Empty(t, params.EndTime)
	assert.Equal(t, 1, params.Page)
	assert.Equal(t, 20, params.PageSize)
	assert.Equal(t, -1, params.Status)
	assert.False(t, params.IsSystemAdmin)
}
