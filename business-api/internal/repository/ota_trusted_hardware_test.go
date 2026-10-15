package repository

import (
	"testing"

	"inv-api-server/internal/model"
)

// The task-candidate list and the send path must agree on one verdict, otherwise a
// device offered as upgradable fails at submit time with no explanation.
func TestEvaluateTrustedFirmwareReportsDispatchReasons(t *testing.T) {
	published := func() *model.Firmware {
		return &model.Firmware{ID: 7, Model: "MODEL", TargetChip: "arm", Version: "2.0", BoardCodes: []string{"COMM-A"},
			ReleaseStatus: model.FirmwareReleasePublished, Status: 1, RolloutPercent: 100, RolloutType: "all"}
	}
	verified := func() otaDeviceMetadata {
		return otaDeviceMetadata{Model: "MODEL", IdentityState: "verified", IdentityRevision: 3, ModuleState: "verified",
			BoardCode: "COMM-A", ProtectionLevel: "registry_verified"}
	}
	cases := []struct {
		name   string
		mutate func(*otaDeviceMetadata, *model.Firmware)
		want   string
	}{
		{"unknown registry and scope", func(v *otaDeviceMetadata, f *model.Firmware) {
			*v = otaDeviceMetadata{Model: "MODEL"}
			f.BoardCodes = nil
		}, ""},
		{"unknown target", func(_ *otaDeviceMetadata, f *model.Firmware) { f.TargetChip = "invalid" }, "firmware_incompatible"},
		{"verified and windowed", func(*otaDeviceMetadata, *model.Firmware) {}, ""},
		{"frozen historical registry", func(v *otaDeviceMetadata, _ *model.Firmware) { v.Frozen = true; v.IdentityState = "conflict" }, ""},
		{"module absent", func(v *otaDeviceMetadata, _ *model.Firmware) { v.ModuleState = "absent"; v.BoardCode = "" }, ""},
		{"verified model mismatch", func(v *otaDeviceMetadata, _ *model.Firmware) { v.Model = "OTHER" }, "firmware_incompatible"},
		{"draft firmware", func(_ *otaDeviceMetadata, f *model.Firmware) {
			f.ReleaseStatus = model.FirmwareReleaseDraft
			f.Status = 0
		}, "firmware_not_published"},
		{"outside device rollout", func(_ *otaDeviceMetadata, f *model.Firmware) {
			f.RolloutType = "device"
			f.RolloutTargets = "OTHER-SN"
		}, "firmware_outside_rollout"},
		{"inside device rollout", func(_ *otaDeviceMetadata, f *model.Firmware) {
			f.RolloutType = "device"
			f.RolloutTargets = "MODEL-SN-1"
		}, ""},
		{"zero percent rollout", func(_ *otaDeviceMetadata, f *model.Firmware) { f.RolloutPercent = 0 }, "firmware_outside_rollout"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fw, identity := published(), verified()
			c.mutate(&identity, fw)
			err := evaluateFirmwareForDevice(identity, fw, "MODEL-SN-1")
			if c.want == "" {
				if err != nil {
					t.Fatalf("unexpected verdict %v", err)
				}
				return
			}
			if err == nil {
				t.Fatalf("expected %q, got no error", c.want)
			}
			if got := OTAEligibilityReason(err); got != c.want {
				t.Fatalf("reason %q, want %q", got, c.want)
			}
		})
	}
}

// Unknown targets must never reach the interpolated version column.
func TestOTATargetVersionColumnRejectsUnknownTarget(t *testing.T) {
	for target, want := range map[string]string{"arm": "firmware_arm", "esp": "firmware_esp", "dsp": "firmware_dsp", "bms": "firmware_bms"} {
		column, ok := otaTargetVersionColumn(target)
		if !ok || column != want {
			t.Fatalf("target %q: got %q/%v, want %q", target, column, ok, want)
		}
	}
	for _, target := range []string{"", "ARM", "dsp; drop table devices", "unknown"} {
		if _, ok := otaTargetVersionColumn(target); ok {
			t.Fatalf("target %q must be rejected", target)
		}
	}
}
