package model

import "testing"

func TestHardwareMutationRequiresEvidenceAndOnlyRegistryProtection(t *testing.T) {
	base := HardwareMutation{ExpectedRevision: 0, VerifiedModel: "CS-L10", Source: "factory", EvidenceRef: "ledger-1", Reason: "factory record", Modules: []HardwareModule{{TargetChip: "esp", BoardCode: "COMM-A", State: "verified", ProtectionLevel: "registry_verified"}}}
	if err := ValidateHardwareMutation("SN123456", "verify", base); err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{"evidence", "reason", "protection", "duplicate"} {
		req := base
		req.Modules = append([]HardwareModule(nil), base.Modules...)
		switch field {
		case "evidence":
			req.EvidenceRef = ""
		case "reason":
			req.Reason = ""
		case "protection":
			req.Modules[0].ProtectionLevel = "device_enforced"
		case "duplicate":
			req.Modules = append(req.Modules, req.Modules[0])
		}
		if err := ValidateHardwareMutation("SN123456", "verify", req); err == nil {
			t.Errorf("accepted unsafe %s", field)
		}
	}
}

func TestHardwareBoardCodeDoesNotNormalizeUnknownIdentity(t *testing.T) {
	for _, code := range []string{"comm-a", " A", "A B", ""} {
		if err := ValidateHardwareBoardType(HardwareBoardType{Model: "CS-L10", TargetChip: "esp", BoardCode: code}); err == nil {
			t.Errorf("accepted %q", code)
		}
	}
	if err := ValidateHardwareBoardType(HardwareBoardType{Model: "CS-L10", TargetChip: "esp", BoardCode: "COMM-A.2"}); err != nil {
		t.Fatal(err)
	}
}
