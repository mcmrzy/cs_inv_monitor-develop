package service

import (
	"context"
	"errors"

	"inv-api-server/internal/repository"
	"inv-api-server/pkg/apperr"
)

type EnergyScheduleService struct {
	repo *repository.EnergyScheduleRepository
}

func NewEnergyScheduleService(repo *repository.EnergyScheduleRepository) *EnergyScheduleService {
	return &EnergyScheduleService{repo: repo}
}

func (s *EnergyScheduleService) GetSchedule(ctx context.Context, sn string) (*repository.EnergySchedule, error) {
	return s.repo.GetEnergySchedule(ctx, sn)
}

// UpdateSchedule 使用乐观锁更新能源计划。
// 如果 expectedRevision 与数据库中的 revision 不匹配，返回 409 Conflict。
func (s *EnergyScheduleService) UpdateSchedule(ctx context.Context, sn string, req repository.UpsertScheduleReq, expectedRevision int64) (*repository.EnergySchedule, error) {
	result, err := s.repo.UpsertEnergySchedule(ctx, sn, req, expectedRevision)
	if err != nil {
		if errors.Is(err, repository.ErrRevisionMismatch) {
			return nil, apperr.Conflict("能源计划版本冲突，请刷新后重试")
		}
		return nil, err
	}
	return result, nil
}

func (s *EnergyScheduleService) CreateOverride(ctx context.Context, sn string, req repository.CreateOverrideReq) (*repository.ControlOverride, error) {
	return s.repo.CreateControlOverride(ctx, sn, req)
}

func (s *EnergyScheduleService) ListActiveOverrides(ctx context.Context, sn string) ([]repository.ControlOverride, error) {
	return s.repo.ListActiveOverrides(ctx, sn)
}

func (s *EnergyScheduleService) CancelOverride(ctx context.Context, sn string, id int64) error {
	return s.repo.CancelOverride(ctx, sn, id)
}
