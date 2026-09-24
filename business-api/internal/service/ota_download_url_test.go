package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"inv-api-server/internal/model"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 用例取自实测：把 ESP-IDF 自带的 http_parser（HTTP_PARSER_STRICT=1）编到宿主上，
// 逐条跑 esp_http_client_set_url() 的第一步 http_parser_parse_url()。
func TestValidateDeviceDownloadURL(t *testing.T) {
	tests := []struct {
		name string
		url  string
		ok   bool
	}{
		{"线上实际形态", "https://download.jiuxiaoyw.online/firmware/CS-L10-6K2_1.7.13_1790046134000000000.bin", true},
		{"根域下载地址", "https://jiuxiaoyw.online/firmware/CS-L10-6K2_1.7.13_1.bin", true},
		{"百分号转义的中文可解析", "https://download.jiuxiaoyw.online/firmware/%E5%82%A8%E8%83%BD_1.7.13.bin", true},
		{"带端口", "https://download.example.com:8443/fw.bin", true},
		{"带 query 与 fragment", "https://download.example.com/fw.bin?token=1#frag", true},
		{"大写 scheme", "HTTPS://download.example.com/fw.bin", true},
		{"IPv6 字面量", "https://[2402:4e00::1]/fw.bin", true},
		{"文件名含空格", "https://download.example.com/firmware/CS L10-6K2_1.7.13_1.bin", false},
		{"文件名含中文", "https://download.example.com/firmware/储能_1.7.13_1.bin", false},
		{"主机名带下划线", "https://down_load.example.com/fw.bin", false},
		{"缺少主机名", "https:///firmware/fw.bin", false},
		{"相对路径", "/firmware/CS-L10-6K2_1.7.13_1.bin", false},
		{"没有 scheme", "download.example.com/fw.bin", false},
		{"非 http 协议", "ftp://download.example.com/fw.bin", false},
		{"空地址", "", false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateDeviceDownloadURL(tc.url)
			if tc.ok {
				assert.NoError(t, err)
				return
			}
			assert.Error(t, err, "设备端解析不了的地址必须在下发前拦掉")
		})
	}
}

// 非法地址必须一条命令都不发出去，并且不能在 repo 为空时 panic
// （SendUpgradeCommand 有多处 goroutine 调用点）。
func TestSendUpgradeCommandRejectsDeviceUnsafeURL(t *testing.T) {
	dispatched := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		dispatched = true
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	s := &OTAService{
		deviceServer: server.URL,
		httpClient:   server.Client(),
	}
	s.SendUpgradeCommand(context.Background(),
		&model.DeviceUpgrade{ID: 123, DeviceSN: "SN001"},
		&model.Firmware{ID: 42, TargetChip: "esp", Version: "1.7.13"},
		"https://download.example.com/firmware/CS L10-6K2_1.7.13_1.bin")

	assert.False(t, dispatched, "地址非法时不应下发命令")
}

// 合法地址照旧下发，且命令体里的 url 原样透传。
func TestSendUpgradeCommandStillDispatchesValidURL(t *testing.T) {
	var payload map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.NoError(t, json.NewDecoder(r.Body).Decode(&payload))
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	const url = "https://download.jiuxiaoyw.online/firmware/CS-L10-6K2_1.7.13_1790046134000000000.bin"
	s := &OTAService{deviceServer: server.URL, httpClient: server.Client()}
	s.SendUpgradeCommand(context.Background(),
		&model.DeviceUpgrade{ID: 123, DeviceSN: "SN001"},
		&model.Firmware{ID: 42, TargetChip: "esp", Version: "1.7.13"},
		url)

	require.Equal(t, url, payload["url"])
	require.Equal(t, "esp", payload["target"])
}

// JSON 方式创建固件时，脏地址要在创建阶段就 400，而不是等推送时才发现。
func TestValidateFirmwareRequestRejectsURLWithUnsafeBytes(t *testing.T) {
	base := func() *CreateFirmwareReq {
		return &CreateFirmwareReq{
			Model:      "CS-L10-6K2",
			TargetChip: "esp",
			Version:    "1.7.13",
			FileURL:    "/firmware/CS-L10-6K2_1.7.13_1790046134000000000.bin",
			FileSize:   1275152,
			FileSHA256: "7a710668c672311a7fd07d4c194593e8aac3b8af3b501cffe487bfa794af9518",
		}
	}

	require.NoError(t, ValidateFirmwareRequest(base()))

	spaced := base()
	spaced.FileURL = "/firmware/CS L10-6K2_1.7.13_1.bin"
	require.Error(t, ValidateFirmwareRequest(spaced))

	chinese := base()
	chinese.FileURL = "/firmware/储能_1.7.13_1.bin"
	require.Error(t, ValidateFirmwareRequest(chinese))

	absoluteWithSpace := base()
	absoluteWithSpace.FileURL = "https://download.example.com/firmware/CS L10_1.7.13.bin"
	require.Error(t, ValidateFirmwareRequest(absoluteWithSpace))
}
