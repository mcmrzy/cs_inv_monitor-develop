package service

import (
	"context"
	"fmt"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"strings"
)

type otaFirmwareValidator interface {
	ValidateFirmwareForDevice(context.Context, string, int64) (*model.Firmware, *repository.DeviceInfo, error)
}

func (s *OTAService) validateFirmwareForDevice(ctx context.Context, sn string, id int64) (*model.Firmware, *repository.DeviceInfo, error) {
	if s.firmwareValidator != nil {
		return s.firmwareValidator.ValidateFirmwareForDevice(ctx, sn, id)
	}
	if s.repo == nil {
		return nil, nil, fmt.Errorf("OTA repository unavailable")
	}
	return s.repo.ValidateFirmwareForDevice(ctx, sn, id)
}

func (s *OTAService) ListHardwareVersions(ctx context.Context, m string) ([]model.DeviceHardwareVersion, error) {
	return s.repo.ListHardwareVersions(ctx, strings.TrimSpace(m))
}
func (s *OTAService) CreateHardwareVersion(ctx context.Context, v *model.DeviceHardwareVersion) error {
	v.Model = strings.TrimSpace(v.Model)
	v.Description = strings.TrimSpace(v.Description)
	if !firmwareTokenPattern.MatchString(v.Model) || len(v.Model) > 100 || len([]rune(v.Description)) > 500 {
		return fmt.Errorf("型号或硬件说明格式无效")
	}
	versions, err := model.NormalizeHardwareVersions([]string{v.Version})
	if err != nil {
		return err
	}
	v.Version = versions[0]
	return s.repo.CreateHardwareVersion(ctx, v)
}
func (s *OTAService) UpdateFirmwareHardwareVersions(ctx context.Context, id int64, versions []string) error {
	return s.repo.UpdateFirmwareHardwareVersions(ctx, id, versions)
}

func (s *OTAService) validateFirmwareTargets(ctx context.Context, fid int64, sns []string) error {
	for _, sn := range sns {
		if _, _, err := s.repo.ValidateFirmwareForDevice(ctx, sn, fid); err != nil {
			return fmt.Errorf("设备 %s: %w", sn, err)
		}
	}
	return nil
}
