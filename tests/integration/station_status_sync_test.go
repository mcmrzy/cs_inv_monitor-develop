//go:build integration

package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// 电站状态与设备在线状态联动回归：
// stations.status 曾因联动缺失/失效而永远停在建站默认"正常"，
// 这里覆盖 建站→绑定未上线设备→上线→离线 全链路。

func postInternalDeviceStatus(t *testing.T, sn string, status int) {
	t.Helper()
	// 内部接口不走网关（网关侧该路径要求管理员 JWT），测试栈为 api-server
	// 暴露了直连端口，与生产 device-server 直连拓扑一致
	internalBase := getEnvOrDefault("TEST_INTERNAL_API_BASE_URL", "http://localhost:18080")
	payload, err := json.Marshal(map[string]interface{}{"sn": sn, "status": status})
	require.NoError(t, err)
	req, err := http.NewRequest(http.MethodPost, internalBase+"/api/v1/internal/device-status", bytes.NewReader(payload))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")
	// 与 deploy/docker-compose.test.yml 的 INTERNAL_KEY 保持一致
	req.Header.Set("X-Internal-Key", getEnvOrDefault("TEST_INTERNAL_KEY", "test-internal-key-with-more-than-32-characters"))
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, http.StatusOK, resp.StatusCode, "internal device-status HTTP status")
}

func stationStatusByName(t *testing.T, cfg EnvConfig, token, name string) (int, bool) {
	t.Helper()
	resp, status := doJSON(t, &http.Client{Timeout: 10 * time.Second}, "GET", cfg.APIBaseURL+"/api/v1/stations", nil, token)
	require.Equal(t, 200, status, "list stations HTTP status")
	require.Equal(t, 0, resp.Code, "list stations should succeed")

	var data struct {
		Items []struct {
			Name   string `json:"name"`
			Status int    `json:"status"`
		} `json:"items"`
	}
	if err := json.Unmarshal(resp.Data, &data); err != nil {
		// 兼容直接返回数组的形态
		var list []struct {
			Name   string `json:"name"`
			Status int    `json:"status"`
		}
		require.NoError(t, json.Unmarshal(resp.Data, &list), "stations data should be items-object or array")
		for _, s := range list {
			if s.Name == name {
				return s.Status, true
			}
		}
		return 0, false
	}
	for _, s := range data.Items {
		if s.Name == name {
			return s.Status, true
		}
	}
	return 0, false
}

func TestStationStatusSync(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}
	phone := fmt.Sprintf("138%08d", time.Now().UnixNano()%100000000)
	password := "StationSync@2026"
	registerUser(t, cfg.APIBaseURL, phone, password)
	token := loginUser(t, cfg.APIBaseURL, phone, password)

	// 1. 新建电站: 初始状态应为离线(0), 而非"正常"
	stationName := fmt.Sprintf("状态联动站-%d", time.Now().UnixNano()%1000000)
	createPayload := map[string]interface{}{
		"name":       stationName,
		"capacity":   6.2,
		"timezone":   "Asia/Shanghai",
		"country":    "中国",
		"province":   "湖南省",
		"city":       "湘潭市",
		"district":   "岳塘区",
		"address":    "文轩路27号",
		"peak_price": 0.6,
	}
	resp, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/stations", createPayload, token)
	require.Equal(t, 200, status, "create station HTTP status")
	require.Equal(t, 0, resp.Code, "create station should succeed: %s", resp.Message)

	var created struct {
		ID int64 `json:"id"`
	}
	require.NoError(t, json.Unmarshal(resp.Data, &created), "create response should carry station id")
	require.NotZero(t, created.ID, "created station id should be non-zero")

	st, found := stationStatusByName(t, cfg, token, stationName)
	require.True(t, found, "created station should be listed")
	require.Equal(t, 0, st, "新建电站(无在线设备)状态应为离线(0)")

	// 2. 绑定一台从未上线的设备到该电站: 设备 status=0, 电站应保持离线
	testSN := fmt.Sprintf("SYNC-TEST-%d", time.Now().UnixNano())
	bindPayload := map[string]interface{}{
		"sn":         testSN,
		"station_id": created.ID,
		"pin":        devicePIN(testSN),
	}
	resp, status = doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/devices/bind", bindPayload, token)
	require.Equal(t, 0, resp.Code, "bind should succeed: %s", resp.Message)

	st, found = stationStatusByName(t, cfg, token, stationName)
	require.True(t, found)
	require.Equal(t, 0, st, "绑定未上线设备后电站应保持离线(0)")

	// 3. 设备上线(内部状态接口): 电站联动为正常(1)
	postInternalDeviceStatus(t, testSN, 1)
	st, found = stationStatusByName(t, cfg, token, stationName)
	require.True(t, found)
	require.Equal(t, 1, st, "设备上线后电站应为正常(1)")

	// 4. 设备上报离线: 电站必须联动回离线(0) —— 回归点:
	//    修复前 InternalDeviceStatus 无条件把电站强写为 1
	postInternalDeviceStatus(t, testSN, 0)
	st, found = stationStatusByName(t, cfg, token, stationName)
	require.True(t, found)
	require.Equal(t, 0, st, "设备上报离线后电站应为离线(0)")
}
