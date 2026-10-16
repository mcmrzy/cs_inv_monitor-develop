package service

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
)

func TestPreflightDoesNotRequireHardwareRecordsOrProtectionWindow(t *testing.T) {
	s := &OTAService{firmwareValidator: fixedFirmwareValidator{firmware: &model.Firmware{ID: 101, Model: "L10", TargetChip: "dsp", FileSHA256: "hash"}}}
	for _, channel := range []string{"cloud", "local", "offline"} {
		t.Run(channel, func(t *testing.T) {
			result, err := s.Preflight(context.Background(), "H1ZZX00139000079", 101, channel)
			require.NoError(t, err)
			require.Equal(t, true, result["eligible"])
			require.Empty(t, result["compatibility_reason"])
			require.Equal(t, "dsp", result["target_chip"])
		})
	}
}
