package service

import (
	"context"
	"regexp"
	"strings"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/apperr"
)

type HardwareRegistryService struct {
	repo *repository.HardwareRegistryRepository
}

func NewHardwareRegistryService(repo *repository.HardwareRegistryRepository) *HardwareRegistryService {
	return &HardwareRegistryService{repo: repo}
}
func (s *HardwareRegistryService) ListBoardTypes(ctx context.Context, modelName, target string) ([]model.HardwareBoardType, error) {
	if target != "" && !model.HardwareTargetValid(target) {
		return nil, apperr.BadRequest("invalid target_chip")
	}
	return s.repo.ListBoardTypes(ctx, modelName, target)
}
func (s *HardwareRegistryService) CreateBoardType(ctx context.Context, b model.HardwareBoardType) error {
	if err := model.ValidateHardwareBoardType(b); err != nil {
		return err
	}
	return s.repo.CreateBoardType(ctx, b)
}
func (s *HardwareRegistryService) Get(ctx context.Context, sn string) (*model.HardwareRegistry, error) {
	return s.repo.Get(ctx, sn)
}
func (s *HardwareRegistryService) Mutate(ctx context.Context, sn, action string, req model.HardwareMutation, actor int64) (*model.HardwareRegistry, error) {
	if err := model.ValidateHardwareMutation(sn, action, req); err != nil {
		return nil, err
	}
	if actor <= 0 {
		return nil, apperr.Forbidden("authenticated administrator required")
	}
	return s.repo.Mutate(ctx, sn, action, req, actor)
}
func (s *HardwareRegistryService) History(ctx context.Context, sn string, page, size int) ([]model.HardwareHistory, int64, error) {
	return s.repo.History(ctx, sn, page, size)
}
func (s *HardwareRegistryService) StageImport(ctx context.Context, rows []model.HardwareImportInput, actor int64) (*model.HardwareImportBatch, error) {
	if len(rows) == 0 || len(rows) > 10000 {
		return nil, apperr.BadRequest("import must contain 1..10000 rows")
	}
	if actor <= 0 {
		return nil, apperr.Forbidden("authenticated administrator required")
	}
	return s.repo.StageImport(ctx, rows, actor)
}
func (s *HardwareRegistryService) ImportBatch(ctx context.Context, id, actor int64) (*model.HardwareImportBatch, error) {
	return s.repo.ImportBatch(ctx, id, actor)
}
func (s *HardwareRegistryService) CommitImport(ctx context.Context, id, actor int64, req model.HardwareImportCommit) (*model.HardwareImportBatch, error) {
	if len(req.RowIndexes) == 0 || len(req.RowIndexes) > 10000 || strings.TrimSpace(req.IdempotencyKey) == "" || len(req.IdempotencyKey) > 100 {
		return nil, apperr.BadRequest("selected rows and idempotency_key required")
	}
	if actor <= 0 {
		return nil, apperr.Forbidden("authenticated administrator required")
	}
	return s.repo.CommitImport(ctx, id, actor, req)
}
func (s *HardwareRegistryService) SetFirmwareBoards(ctx context.Context, id, actor int64, codes []string, reason, evidence string) error {
	if id <= 0 || actor <= 0 || len(codes) == 0 || len(codes) > 100 || strings.TrimSpace(reason) == "" || strings.TrimSpace(evidence) == "" || len(reason) > 1000 || len(evidence) > 500 {
		return apperr.BadRequest("firmware, board_codes, reason and evidence_ref required")
	}
	seen := map[string]bool{}
	for _, code := range codes {
		if seen[code] {
			return apperr.BadRequest("duplicate board_code")
		}
		seen[code] = true
		if err := model.ValidateHardwareBoardType(model.HardwareBoardType{Model: "validation", TargetChip: "esp", BoardCode: code}); err != nil {
			return err
		}
	}
	return s.repo.SetFirmwareBoards(ctx, id, actor, codes, reason, evidence)
}

var hardwareHashPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

func (s *HardwareRegistryService) CreateCompatibilityWindow(ctx context.Context, w model.OTACompatibilityWindow, actor int64) (*model.OTACompatibilityWindow, error) {
	now := time.Now().UTC()
	if w.FirmwareID <= 0 || actor <= 0 || w.IdentityRevision <= 0 || !model.HardwareTargetValid(w.TargetChip) || !hardwareHashPattern.MatchString(w.FileSHA256) || !w.ExpiresAt.After(now) || w.ExpiresAt.After(now.Add(72*time.Hour)) || strings.TrimSpace(w.Reason) == "" || strings.TrimSpace(w.EvidenceRef) == "" || len(w.Reason) > 1000 || len(w.EvidenceRef) > 500 {
		return nil, apperr.BadRequest("exact identity, firmware SHA256, evidence and expiry within 72h required")
	}
	if err := model.ValidateHardwareMutation(w.SN, "freeze", model.HardwareMutation{EvidenceRef: w.EvidenceRef, Reason: w.Reason}); err != nil {
		return nil, err
	}
	return s.repo.CreateCompatibilityWindow(ctx, w, actor)
}
func (s *HardwareRegistryService) ListCompatibilityWindows(ctx context.Context, sn string) ([]model.OTACompatibilityWindow, error) {
	return s.repo.ListCompatibilityWindows(ctx, sn)
}

func (s *HardwareRegistryService) FirmwareBoards(ctx context.Context, id int64) ([]string, error) {
	return s.repo.FirmwareBoards(ctx, id)
}
