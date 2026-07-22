package service

import (
	"context"

	"inv-api-server/internal/repository"
)

type BatteryService struct {
	repo *repository.BatteryRepository
}

func NewBatteryService(repo *repository.BatteryRepository) *BatteryService {
	return &BatteryService{repo: repo}
}

func (s *BatteryService) ListProfiles(ctx context.Context) ([]repository.BatteryProfile, error) {
	return s.repo.ListBatteryProfiles(ctx)
}

func (s *BatteryService) GetProfile(ctx context.Context, id int64) (*repository.BatteryProfile, error) {
	return s.repo.GetBatteryProfile(ctx, id)
}

func (s *BatteryService) CreateProfile(ctx context.Context, req repository.CreateBatteryProfileReq) (*repository.BatteryProfile, error) {
	return s.repo.CreateBatteryProfile(ctx, req)
}

func (s *BatteryService) GetDeviceConfig(ctx context.Context, sn string) (*repository.DeviceBatteryConfig, error) {
	return s.repo.GetDeviceBatteryConfig(ctx, sn)
}

func (s *BatteryService) BindDeviceConfig(ctx context.Context, sn string, req repository.UpsertBatteryConfigReq) error {
	return s.repo.UpsertDeviceBatteryConfig(ctx, sn, req)
}
