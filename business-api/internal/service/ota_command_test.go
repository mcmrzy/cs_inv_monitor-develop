package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"

	"github.com/stretchr/testify/require"
)

type offlineFirmwareValidator struct{}

func (offlineFirmwareValidator) ValidateFirmwareForDevice(context.Context, string, int64) (*model.Firmware, *repository.DeviceInfo, error) {
	return &model.Firmware{ID: 42, FileURL: "https://example.test/fw.bin"}, &repository.DeviceInfo{IsOnline: false}, nil
}

func TestSendUpgradeCommandWaitsForOfflineDevice(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	s := &OTAService{deviceServer: server.URL, httpClient: server.Client(), firmwareValidator: offlineFirmwareValidator{}}
	s.SendUpgradeCommand(context.Background(), &model.DeviceUpgrade{ID: 123, DeviceSN: "SN001", FirmwareID: 42}, nil, "")
	require.Zero(t, requests, "offline tasks must remain in the database until the device is online")
}

func TestSendUpgradeCommandIncludesStableUpgradeID(t *testing.T) {
	var payload map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.Equal(t, "/api/v1/device/SN001/command", r.URL.Path)
		require.Equal(t, "test-key", r.Header.Get("X-Internal-Key"))
		require.NoError(t, json.NewDecoder(r.Body).Decode(&payload))
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	s := &OTAService{
		deviceServer:      server.URL,
		internalKey:       "test-key",
		httpClient:        server.Client(),
		firmwareValidator: fixedFirmwareValidator{firmware: &model.Firmware{ID: 42, TargetChip: "arm", Version: "V1.2.3", FileURL: "https://example.test/fw.bin", HardwareVersions: []string{"HW-1"}}},
	}
	s.SendUpgradeCommand(context.Background(), &model.DeviceUpgrade{
		ID:         123,
		DeviceSN:   "SN001",
		FirmwareID: 42,
	}, &model.Firmware{
		ID:         42,
		TargetChip: "arm",
		Version:    "V1.2.3",
		FileSHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}, "https://example.test/fw.bin")

	require.Equal(t, "123", payload["task_id"])
	require.Equal(t, float64(123), payload["upgrade_id"])
	require.Equal(t, false, payload["queue_if_offline"])
	require.Equal(t, "arm", payload["target"])
	require.Equal(t, "V1.2.3", payload["version"])
}
