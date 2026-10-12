package service

import (
	"context"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"net/http"
	"net/http/httptest"
	"testing"
)

type fixedFirmwareValidator struct {
	firmware *model.Firmware
	err      error
}

func (v fixedFirmwareValidator) ValidateFirmwareForDevice(context.Context, string, int64) (*model.Firmware, *repository.DeviceInfo, error) {
	return v.firmware, nil, v.err
}

func TestDispatchHardwareRejectionDoesNotContactDevice(t *testing.T) {
	count := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { count++; w.WriteHeader(200) }))
	defer server.Close()
	for _, err := range []error{model.ErrHardwareVersionUnknown, model.ErrHardwareIncompatible, model.ErrFirmwareHardwareUnspecified} {
		s := &OTAService{deviceServer: server.URL, httpClient: server.Client(), firmwareValidator: fixedFirmwareValidator{err: err}}
		s.SendUpgradeCommand(context.Background(), &model.DeviceUpgrade{ID: 1, FirmwareID: 2, DeviceSN: "SN"}, &model.Firmware{ID: 2}, server.URL+"/firmware.bin")
	}
	require.Zero(t, count)
}
