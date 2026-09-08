package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestParseDeviceListParams_NewFilters 正向用例：model 前缀过滤与
// lastOnlineStart/lastOnlineEnd（RFC3339 与 'YYYY-MM-DD HH:mm:ss' 两种格式）均被正确解析。
func TestParseDeviceListParams_NewFilters(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet,
		"/api/v1/devices?model=SP-5000&lastOnlineStart=2026-01-02T03:04:05Z&lastOnlineEnd=2026-01-31%2023%3A59%3A59&page=2&page_size=50", nil)
	setAuthClaimsInContext(c, 7, true, 1)

	params, err := parseDeviceListParams(c)
	require.NoError(t, err)

	assert.Equal(t, "SP-5000", params.Model)
	require.NotNil(t, params.LastOnlineStart)
	assert.True(t, time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC).Equal(*params.LastOnlineStart))
	require.NotNil(t, params.LastOnlineEnd)
	assert.True(t, time.Date(2026, 1, 31, 23, 59, 59, 0, time.UTC).Equal(*params.LastOnlineEnd))
	assert.Equal(t, 2, params.Page)
	assert.Equal(t, 50, params.PageSize)
	assert.True(t, params.IsSystemAdmin)
	assert.Equal(t, int64(7), params.UserID)
}

// TestParseDeviceListParams_MissingParamsKeepsBehavior 边界用例：不传新参数时
// model 为空、时间指针为 nil（repository 不追加条件），分页与状态默认值不变。
func TestParseDeviceListParams_MissingParamsKeepsBehavior(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
	setAuthClaimsInContext(c, 7, false, 1)

	params, err := parseDeviceListParams(c)
	require.NoError(t, err)

	assert.Empty(t, params.Model)
	assert.Nil(t, params.LastOnlineStart)
	assert.Nil(t, params.LastOnlineEnd)
	assert.Equal(t, -1, params.Status)
	assert.Equal(t, 1, params.Page)
	assert.Equal(t, 20, params.PageSize)
	assert.False(t, params.IsSystemAdmin)
}

// TestDeviceList_InvalidTimeParamReturns400 边界用例：时间格式非法时返回参数
// 错误（业务码 400），不会触达数据库。
func TestDeviceList_InvalidTimeParamReturns400(t *testing.T) {
	gin.SetMode(gin.TestMode)
	h := NewDeviceHandler(nil, nil, nil, nil, nil, nil, nil)
	router := gin.New()
	router.GET("/api/v1/devices", h.List)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/devices?lastOnlineStart=not-a-time", nil)
	router.ServeHTTP(w, req)

	assertBizResponse(t, w, 400, "invalid lastOnlineStart")
}
