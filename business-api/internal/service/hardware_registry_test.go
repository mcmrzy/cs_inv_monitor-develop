package service

import (
	"context"
	"inv-api-server/internal/model"
	"testing"
	"time"
)

// Safety validation must run before repository access (nil repository would panic).
func TestHardwareServiceRejectsUnsafeInputsBeforeDB(t *testing.T) {
	s := NewHardwareRegistryService(nil)
	ctx := context.Background()
	if _, err := s.Mutate(ctx, "SN123456", "verify", model.HardwareMutation{}, 1); err == nil {
		t.Fatal("missing evidence accepted")
	}
	if _, err := s.StageImport(ctx, []model.HardwareImportInput{}, 1); err == nil {
		t.Fatal("empty import accepted")
	}
	if _, err := s.StageImport(ctx, make([]model.HardwareImportInput, 10001), 1); err == nil {
		t.Fatal("unbounded import accepted")
	}
	if err := s.SetFirmwareBoards(ctx, 1, 1, []string{"A", "A"}, "check", "ledger"); err == nil {
		t.Fatal("duplicate scope accepted")
	}
	if _, err := s.CreateCompatibilityWindow(ctx, model.OTACompatibilityWindow{SN: "SN123456", TargetChip: "esp", FirmwareID: 1, IdentityRevision: 1, FileSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", ExpiresAt: time.Now().Add(96 * time.Hour), Reason: "migration", EvidenceRef: "job"}, 1); err == nil {
		t.Fatal("unbounded compatibility window accepted")
	}
}
