package model

import (
	"github.com/stretchr/testify/require"
	"testing"
)

func TestFirmwareHardwareCompatibility(t *testing.T) {
	fw := &Firmware{Model: "L10", HardwareVersions: []string{"HW-1", "HW-2"}}
	require.NoError(t, CheckFirmwareHardware(fw, "L10", " hw-2 "))
	require.ErrorIs(t, CheckFirmwareHardware(fw, "L10", ""), ErrHardwareVersionUnknown)
	require.ErrorIs(t, CheckFirmwareHardware(fw, "L10", "HW-3"), ErrHardwareIncompatible)
	require.ErrorIs(t, CheckFirmwareHardware(fw, "L10", "2"), ErrHardwareIncompatible)
	require.ErrorIs(t, CheckFirmwareHardware(fw, "OTHER", "HW-1"), ErrHardwareIncompatible)
	require.ErrorIs(t, CheckFirmwareHardware(&Firmware{Model: "L10"}, "L10", "HW-1"), ErrFirmwareHardwareUnspecified)
}

func TestNormalizeFirmwareHardwareVersions(t *testing.T) {
	versions, err := NormalizeHardwareVersions([]string{" hw-2 ", "HW-1", "HW-2"})
	require.NoError(t, err)
	require.Equal(t, []string{"HW-1", "HW-2"}, versions)
	for _, invalid := range [][]string{nil, {}, {""}, {"*"}, {"HW/2"}, {"HW-1", " "}} {
		_, err = NormalizeHardwareVersions(invalid)
		require.Error(t, err)
	}
}
