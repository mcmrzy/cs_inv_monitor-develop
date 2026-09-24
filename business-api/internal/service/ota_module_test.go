package service

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

func TestNormalizeFirmwareTarget(t *testing.T) {
	cases := []struct {
		in      string
		want    string
		wantErr bool
	}{
		{"arm", "arm", false},
		{"ARM", "arm", false},
		{" Arm ", "arm", false},
		{"esp", "esp", false},
		{"ESP", "esp", false},
		{"dsp", "dsp", false},
		{"bms", "bms", false},
		{"gpu", "", true},
		{"", "", true},
	}
	for _, c := range cases {
		got, err := NormalizeFirmwareTarget(c.in)
		if c.wantErr {
			assert.Error(t, err, "input %q", c.in)
			continue
		}
		require.NoError(t, err)
		assert.Equal(t, c.want, got)
	}
}

func TestOrderFirmwareTargetsPlacesESPLast(t *testing.T) {
	got := OrderFirmwareTargets([]string{"esp", "bms", "arm", "dsp"})
	assert.Equal(t, []string{"bms", "arm", "dsp", "esp"}, got)
}

func TestOrderFirmwareTargetsDedupesAndSkipsUnknown(t *testing.T) {
	got := OrderFirmwareTargets([]string{"ARM", "arm", "gpu", "esp", "BMS"})
	assert.Equal(t, []string{"bms", "arm", "esp"}, got)
}

func TestCurrentModuleVersion(t *testing.T) {
	got, err := CurrentModuleVersion("M", "1.0.0", "2.0.0", "3.0.0", "4.0.0", "ESP")
	require.NoError(t, err)
	assert.Equal(t, "2.0.0", got)

	_, err = CurrentModuleVersion("M", "1", "2", "3", "4", "gpu")
	assert.Error(t, err)
}

func TestCompareModuleVersion(t *testing.T) {
	assert.Equal(t, 0, CompareModuleVersion("1.0.0", "1.0.0"))
	assert.Equal(t, -1, CompareModuleVersion("1.0.0", "1.0.1"))
	assert.Equal(t, 1, CompareModuleVersion("1.10.0", "1.9.0"))
	assert.Equal(t, -1, CompareModuleVersion("", "1.0.0"))
	assert.Equal(t, 1, CompareModuleVersion("1.0.0", ""))
	// 目录外/非点分版本仍可比较
	assert.Equal(t, 0, CompareModuleVersion("v2.3-beta", "v2.3-beta"))
}

func TestVersionState(t *testing.T) {
	state, upd := VersionState("", "1.0.0")
	assert.Equal(t, "unreported", state)
	assert.False(t, upd)

	state, upd = VersionState("1.0.0", "1.0.0")
	assert.Equal(t, "current", state)
	assert.False(t, upd)

	state, upd = VersionState("1.0.0", "1.2.0")
	assert.Equal(t, "outdated", state)
	assert.True(t, upd)

	state, upd = VersionState("2.0.0", "1.2.0")
	assert.Equal(t, "different", state)
	assert.True(t, upd)

	state, upd = VersionState("1.0.0", "")
	assert.Equal(t, "current", state)
	assert.False(t, upd)
}

func TestFirmwareModuleOverview(t *testing.T) {
	fw := &model.Firmware{ID: 9, Version: "1.1.0", Changelog: "fix"}
	ov := FirmwareModuleOverview("ARM", "1.0.0", true, fw)
	assert.Equal(t, "arm", ov.Target)
	assert.Equal(t, "1.0.0", ov.CurrentVersion)
	assert.Equal(t, int64(9), ov.LatestFirmwareID)
	assert.Equal(t, "outdated", ov.VersionState)
	assert.True(t, ov.UpdateAvailable)
	assert.True(t, ov.Supported)
	assert.True(t, ov.Connected)
	assert.True(t, ov.Eligible)
	assert.Equal(t, []string{"remote", "ble", "wifi_ap"}, ov.SupportedChannels)
	assert.Equal(t, "fix", ov.Changelog)
}

func TestFirmwareModuleOverviewFailsClosedWhenOfflineOrUnreported(t *testing.T) {
	fw := &model.Firmware{ID: 9, Version: "1.1.0"}
	offline := FirmwareModuleOverview("arm", "1.0.0", false, fw)
	assert.True(t, offline.Supported)
	assert.True(t, offline.Connected)
	assert.False(t, offline.Eligible)

	unreported := FirmwareModuleOverview("bms", "", true, fw)
	assert.True(t, unreported.Supported)
	assert.False(t, unreported.Connected)
	assert.False(t, unreported.Eligible)
}

func TestFirmwareSupportedChannels(t *testing.T) {
	assert.Equal(t, []string{"remote", "ble", "wifi_ap"}, FirmwareSupportedChannels("arm"))
	assert.Equal(t, []string{"remote", "ble", "wifi_ap"}, FirmwareSupportedChannels("esp"))
	assert.Equal(t, []string{"remote", "ble"}, FirmwareSupportedChannels("dsp"))
	assert.Equal(t, []string{"remote", "ble"}, FirmwareSupportedChannels("bms"))
	assert.Empty(t, FirmwareSupportedChannels("unknown"))
}
