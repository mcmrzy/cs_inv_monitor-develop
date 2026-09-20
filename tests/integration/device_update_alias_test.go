//go:build integration

package integration

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestDeviceUpdateAliasPersistsWithModelID 覆盖后台「编辑设备」弹窗的改名回归：
// 该弹窗把设备名称与所选型号放在同一个 PUT /devices/by-sn/:sn 请求里提交
// （alias + model + model_id），而 handler 曾经在 model_id 分支里提前 return，
// 导致名称被静默丢弃——接口返回成功、刷新后名字照旧。
//
// 断言两侧：
//   - 同请求携带 model_id 时，alias 必须落库（回归点）；
//   - 型号同步分支必须照常生效（model / model_id / rated_power 全部更新）。
func TestDeviceUpdateAliasPersistsWithModelID(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	client := &http.Client{Timeout: 10 * time.Second}
	phone := fmt.Sprintf("136%08d", time.Now().UnixNano()%100000000)
	password := "RenameTest@2026"

	registerUser(t, cfg.APIBaseURL, phone, password)
	token := loginUser(t, cfg.APIBaseURL, phone, password)
	require.NotEmpty(t, token)

	suffix := time.Now().UnixNano()
	sn := fmt.Sprintf("E2E-RENAME-%d", suffix)
	bindResp, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/devices/bind", map[string]interface{}{
		"sn": sn, "station_id": 0, "pin": devicePIN(sn),
	}, token)
	require.Equal(t, http.StatusOK, status, "bind HTTP status")
	require.Equal(t, 0, bindResp.Code, "bind should succeed: %s", bindResp.Message)

	t.Cleanup(func() {
		// 自服务解绑，避免给后续用例留下已绑定设备
		doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/devices/by-sn/"+sn+"/unbind", nil, token)
	})

	ctx := context.Background()
	var modelID int64
	var modelCode string
	var ratedPowerKW float64
	err := pool.QueryRow(ctx,
		`SELECT id, model_code, COALESCE(rated_power_kw, 0) FROM device_models ORDER BY id LIMIT 1`,
	).Scan(&modelID, &modelCode, &ratedPowerKW)
	require.NoError(t, err, "test stack must seed at least one device model")

	alias := fmt.Sprintf("回归改名-%d", suffix)
	resp, status := doJSON(t, client, "PUT", cfg.APIBaseURL+"/api/v1/devices/by-sn/"+sn, map[string]interface{}{
		"sn":       sn,
		"alias":    alias,
		"model":    modelCode,
		"model_id": modelID,
	}, token)
	require.Equal(t, http.StatusOK, status, "update HTTP status")
	require.Equal(t, 0, resp.Code, "update should succeed: %s", resp.Message)

	var (
		gotAlias    string
		gotModel    string
		gotModelID  int64
		gotRatedPow float64
	)
	err = pool.QueryRow(ctx, `
		SELECT COALESCE(alias, ''), COALESCE(model, ''), COALESCE(model_id, 0), COALESCE(rated_power, 0)
		FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn,
	).Scan(&gotAlias, &gotModel, &gotModelID, &gotRatedPow)
	require.NoError(t, err, "device row should exist")

	assert.Equal(t, alias, gotAlias,
		"alias must persist when the same request carries model_id (名称被静默丢弃的回归)")
	assert.Equal(t, modelCode, gotModel, "model sync branch must still run")
	assert.Equal(t, modelID, gotModelID, "model_id must still be updated")
	assert.InDelta(t, ratedPowerKW, gotRatedPow, 0.001, "model-derived rated_power must still be updated")

	// App / 终端用户「设置名称」只提交 alias，这条路径不能因上面的调整而失效
	aliasOnly := fmt.Sprintf("仅改名-%d", suffix)
	resp, status = doJSON(t, client, "PUT", cfg.APIBaseURL+"/api/v1/devices/by-sn/"+sn,
		map[string]interface{}{"alias": aliasOnly}, token)
	require.Equal(t, http.StatusOK, status, "alias-only update HTTP status")
	require.Equal(t, 0, resp.Code, "alias-only update should succeed: %s", resp.Message)

	require.NoError(t, pool.QueryRow(ctx,
		`SELECT COALESCE(alias, '') FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn,
	).Scan(&gotAlias))
	assert.Equal(t, aliasOnly, gotAlias, "alias-only update must persist")
}
