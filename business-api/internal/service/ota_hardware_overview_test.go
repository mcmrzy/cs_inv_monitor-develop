package service

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUnsupportedBatteryModuleDoesNotBlockHardwareCompatibleDevice(t *testing.T) {
	bms := FirmwareModuleOverview("bms", "", true, nil)
	applyModuleHardwareCompatibility(&bms, true, false)
	require.False(t, bms.Supported)
	require.Empty(t, bms.CompatibilityReason)
	arm := FirmwareModuleOverview("arm", "1.0.0", true, nil)
	applyModuleHardwareCompatibility(&arm, true, false)
	require.Equal(t, "no_compatible_firmware", arm.CompatibilityReason)
	require.False(t, arm.Eligible)
	applyModuleHardwareCompatibility(&arm, false, false)
	require.Equal(t, "hardware_version_unknown", arm.CompatibilityReason)
	require.False(t, arm.UpdateAvailable)
}
