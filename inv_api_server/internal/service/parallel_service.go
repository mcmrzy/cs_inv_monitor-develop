package service

import (
	"context"
	"errors"
	"fmt"

	"inv-api-server/internal/repository"
)

// ErrValidation is a sentinel error used to distinguish validation failures
// from database errors. Handlers use errors.Is to decide whether to return
// 400 (bad request) or 500 (internal server error).
var ErrValidation = errors.New("validation error")

type ParallelService struct {
	parallelRepo *repository.ParallelRepository
}

func NewParallelService(parallelRepo *repository.ParallelRepository) *ParallelService {
	return &ParallelService{parallelRepo: parallelRepo}
}

// CreateParallelGroupRequest is the payload for creating a parallel group.
type CreateParallelGroupRequest struct {
	Name        string   `json:"name" binding:"required"`
	Description string   `json:"description"`
	StationID   *int64   `json:"station_id"`
	MasterSN    string   `json:"master_sn"`
	PhaseConfig string   `json:"phase_config"`
	DeviceSNs   []string `json:"device_sns"`
}

// UpdateParallelGroupRequest uses pointer fields to distinguish "not provided"
// from "set to zero value", following the project convention.
type UpdateParallelGroupRequest struct {
	Name        *string  `json:"name"`
	Description *string  `json:"description"`
	StationID   *int64   `json:"station_id"`
	MasterSN    *string  `json:"master_sn"`
	PhaseConfig *string  `json:"phase_config"`
	DeviceSNs   []string `json:"device_sns"`
	Status      *string  `json:"status"`
}

// validPhaseConfigs defines the allowed phase configuration values.
var validPhaseConfigs = map[string]bool{
	"single_phase": true,
	"three_phase":  true,
}

// validStatuses defines the allowed status values.
var validStatuses = map[string]bool{
	"synced":      true,
	"syncing":     true,
	"out_of_sync": true,
}

func (s *ParallelService) List(ctx context.Context, page, pageSize int, search string, stationID *int64) ([]repository.ParallelGroup, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	return s.parallelRepo.List(ctx, page, pageSize, search, stationID)
}

func (s *ParallelService) GetByID(ctx context.Context, id int64) (*repository.ParallelGroup, error) {
	group, err := s.parallelRepo.GetByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("查询并联组失败: %w", err)
	}
	// Return (nil, nil) when not found; handler decides the HTTP response.
	return group, nil
}

func (s *ParallelService) Create(ctx context.Context, req *CreateParallelGroupRequest) (*repository.ParallelGroup, error) {
	// Validate phase_config
	phaseConfig := req.PhaseConfig
	if phaseConfig == "" {
		phaseConfig = "single_phase"
	}
	if !validPhaseConfigs[phaseConfig] {
		return nil, fmt.Errorf("%w: 无效的相配置: %s", ErrValidation, phaseConfig)
	}

	// Validate device_sns count (locale says "max 8 slaves", so 9 including master)
	if len(req.DeviceSNs) > 9 {
		return nil, fmt.Errorf("%w: 组成员数量不能超过9台", ErrValidation)
	}

	if req.DeviceSNs == nil {
		req.DeviceSNs = []string{}
	}

	group := &repository.ParallelGroup{
		Name:        req.Name,
		Description: req.Description,
		StationID:   req.StationID,
		MasterSN:    req.MasterSN,
		PhaseConfig: phaseConfig,
		DeviceSNs:   req.DeviceSNs,
		Status:      "synced",
	}

	if err := s.parallelRepo.Create(ctx, group); err != nil {
		return nil, fmt.Errorf("创建并联组失败: %w", err)
	}
	return group, nil
}

func (s *ParallelService) Update(ctx context.Context, id int64, req *UpdateParallelGroupRequest) error {
	// Validate phase_config if provided
	if req.PhaseConfig != nil && !validPhaseConfigs[*req.PhaseConfig] {
		return fmt.Errorf("%w: 无效的相配置: %s", ErrValidation, *req.PhaseConfig)
	}
	// Validate status if provided
	if req.Status != nil && !validStatuses[*req.Status] {
		return fmt.Errorf("%w: 无效的状态: %s", ErrValidation, *req.Status)
	}
	// Validate device_sns count if provided
	if req.DeviceSNs != nil && len(req.DeviceSNs) > 9 {
		return fmt.Errorf("%w: 组成员数量不能超过9台", ErrValidation)
	}

	err := s.parallelRepo.Update(ctx, id, req.Name, req.Description, req.StationID,
		req.MasterSN, req.PhaseConfig, req.DeviceSNs, req.Status)
	if err != nil {
		return fmt.Errorf("更新并联组失败: %w", err)
	}
	return nil
}

func (s *ParallelService) Delete(ctx context.Context, id int64) error {
	err := s.parallelRepo.Delete(ctx, id)
	if err != nil {
		return fmt.Errorf("删除并联组失败: %w", err)
	}
	return nil
}
