package service

import (
	"testing"

	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
)

func TestModuleOverviewNeedsNoHardwareScope(t *testing.T) {
	bms := FirmwareModuleOverview("bms", "", true, nil)
	require.False(t, bms.Supported)
	require.Empty(t, bms.CompatibilityReason)
	arm := FirmwareModuleOverview("arm", "1.0.0", true, &model.Firmware{ID: 12, Model: "L10", TargetChip: "arm", Version: "1.1.0", Status: 1, ReleaseStatus: model.FirmwareReleasePublished})
	require.Empty(t, arm.CompatibilityReason)
	require.True(t, arm.UpdateAvailable)
}
