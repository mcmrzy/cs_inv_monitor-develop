package repository

import (
	"testing"

	"inv-api-server/internal/model"
)

func TestTrustedOTAEligibility(t *testing.T) {
	good := trustedOTAIdentity{IdentityState: "verified", Model: "MODEL", ModuleState: "verified", BoardCode: "COMM-A", ProtectionLevel: "registry_verified", HasScope: true, Compatible: true, WindowValid: true}
	cases := []struct {
		name, channel, want string
		edit                func(*trustedOTAIdentity)
	}{
		{"approved window", "cloud", "", func(*trustedOTAIdentity) {}},
		{"report known does not verify", "cloud", "identity_unverified", func(v *trustedOTAIdentity) { v.IdentityState = "unverified" }},
		{"conflict", "cloud", "identity_conflict", func(v *trustedOTAIdentity) { v.IdentityState = "conflict" }},
		{"missing module", "cloud", "module_identity_missing", func(v *trustedOTAIdentity) { v.BoardCode = "" }},
		{"missing matrix", "cloud", "firmware_scope_missing", func(v *trustedOTAIdentity) { v.HasScope = false }},
		{"different board", "cloud", "firmware_incompatible", func(v *trustedOTAIdentity) { v.Compatible = false }},
		{"force cannot replace window", "cloud", "device_protection_required", func(v *trustedOTAIdentity) { v.WindowValid = false }},
		{"window cannot authorize local", "local", "device_protection_required", func(*trustedOTAIdentity) {}},
		{"frozen", "cloud", "identity_conflict", func(v *trustedOTAIdentity) { v.Frozen = true }},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v := good
			c.edit(&v)
			if got := v.reason(c.channel); got != c.want {
				t.Fatalf("reason %q, want %q", got, c.want)
			}
		})
	}
}

// The task-candidate list and the send path must agree on one verdict, otherwise a
// device offered as upgradable fails at submit time with no explanation.
func TestEvaluateTrustedFirmwareReportsDispatchReasons(t *testing.T) {
	published := func() *model.Firmware {
		return &model.Firmware{ID: 7, Model: "MODEL", TargetChip: "arm", Version: "2.0", BoardCodes: []string{"COMM-A"},
			ReleaseStatus: model.FirmwareReleasePublished, Status: 1, RolloutPercent: 100, RolloutType: "all"}
	}
	verified := func() trustedOTAIdentity {
		return trustedOTAIdentity{Model: "MODEL", IdentityState: "verified", IdentityRevision: 3, ModuleState: "verified",
			BoardCode: "COMM-A", ProtectionLevel: "registry_verified", HasScope: true, Compatible: true, WindowValid: true}
	}
	cases := []struct {
		name   string
		mutate func(*trustedOTAIdentity, *model.Firmware)
		want   string
	}{
		{"verified and windowed", func(*trustedOTAIdentity, *model.Firmware) {}, ""},
		{"no compatibility window", func(v *trustedOTAIdentity, _ *model.Firmware) { v.WindowValid = false }, "device_protection_required"},
		{"module absent", func(v *trustedOTAIdentity, _ *model.Firmware) { v.ModuleState = "absent"; v.BoardCode = "" }, "module_absent"},
		{"verified model mismatch", func(v *trustedOTAIdentity, _ *model.Firmware) { v.Model = "OTHER" }, "firmware_incompatible"},
		{"draft firmware", func(_ *trustedOTAIdentity, f *model.Firmware) {
			f.ReleaseStatus = model.FirmwareReleaseDraft
			f.Status = 0
		}, "firmware_not_published"},
		{"outside device rollout", func(_ *trustedOTAIdentity, f *model.Firmware) {
			f.RolloutType = "device"
			f.RolloutTargets = "OTHER-SN"
		}, "firmware_outside_rollout"},
		{"inside device rollout", func(_ *trustedOTAIdentity, f *model.Firmware) {
			f.RolloutType = "device"
			f.RolloutTargets = "MODEL-SN-1"
		}, ""},
		{"zero percent rollout", func(_ *trustedOTAIdentity, f *model.Firmware) { f.RolloutPercent = 0 }, "firmware_outside_rollout"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fw, identity := published(), verified()
			c.mutate(&identity, fw)
			err := evaluateTrustedFirmware(identity, fw, "MODEL-SN-1", "cloud")
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
