package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"inv-api-server/internal/model"

	"github.com/stretchr/testify/require"
)

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
		deviceServer: server.URL,
		internalKey:  "test-key",
		httpClient:   server.Client(),
	}
	s.SendUpgradeCommand(context.Background(), &model.DeviceUpgrade{
		ID:       123,
		DeviceSN: "SN001",
	}, &model.Firmware{
		ID:         42,
		TargetChip: "arm",
		Version:    "V1.2.3",
		FileSHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
	}, "https://example.test/fw.bin")

	require.Equal(t, "123", payload["task_id"])
	require.Equal(t, float64(123), payload["upgrade_id"])
	require.Equal(t, "arm", payload["target"])
}
