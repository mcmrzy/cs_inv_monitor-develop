package service

import (
	"context"
	"fmt"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
)

func (s *StationService) ListOverview(ctx context.Context, plan model.ScopePlan, systemAdmin bool, page, pageSize int) ([]*model.Station, int64, error) {
	return s.repo.ListOverview(ctx, plan, systemAdmin, page, pageSize)
}

func (s *StationService) OverviewDeviceStats(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationIDs []int64) (map[int64]repository.StationOverviewDeviceStats, error) {
	stats, err := s.repo.OverviewDeviceStats(ctx, stationPlan, devicePlan, systemAdmin, stationIDs)
	if err != nil {
		return nil, fmt.Errorf("aggregate overview devices: %w", err)
	}
	return stats, nil
}

func (s *StationService) GetOverviewByID(ctx context.Context, plan model.ScopePlan, systemAdmin bool, id int64) (*model.Station, error) {
	station, err := s.repo.GetOverviewByID(ctx, plan, systemAdmin, id)
	if err != nil {
		return nil, fmt.Errorf("get overview station: %w", err)
	}
	return station, nil
}

func (s *StationService) GetOverviewStatistics(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error) {
	data, err := s.repo.GetOverviewStatistics(ctx, stationPlan, devicePlan, systemAdmin, stationID, startDate, endDate, period, tz)
	if err != nil {
		return nil, fmt.Errorf("get overview station statistics: %w", err)
	}
	return data, nil
}

func (s *DeviceService) GetOverviewStationDevices(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationID int64) ([]*model.Device, error) {
	devices, err := s.repo.GetOverviewStationDevices(ctx, stationPlan, devicePlan, systemAdmin, stationID)
	if err != nil {
		return nil, fmt.Errorf("get overview station devices: %w", err)
	}
	return devices, nil
}

func (s *DeviceService) GetOverviewStationPower(ctx context.Context, stationPlan, devicePlan model.ScopePlan, systemAdmin bool, stationID int64) (repository.StationOverviewPower, error) {
	power, err := s.repo.GetOverviewStationPower(ctx, stationPlan, devicePlan, systemAdmin, stationID)
	if err != nil {
		return repository.StationOverviewPower{}, fmt.Errorf("get overview station power: %w", err)
	}
	return power, nil
}
