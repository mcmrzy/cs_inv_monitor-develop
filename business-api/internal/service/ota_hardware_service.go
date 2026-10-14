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

// ListTaskCandidates lists the devices a task could target for this firmware,
// ineligible ones included with their reason. It never decides dispatch: both
// the queued task and the send path re-run the same per-device check.
func (s *OTAService) ListTaskCandidates(ctx context.Context, id int64, plan model.ScopePlan, systemAdmin bool) (*model.OTATaskCandidateList, error) {
	fw, err := s.repo.GetFirmware(ctx, id)
	if err != nil {
		return nil, err
	}
	if fw == nil {
		return nil, fmt.Errorf("固件不存在")
	}
	return s.repo.ListTaskCandidates(ctx, fw, plan, systemAdmin)
}

func (s *OTAService) Preflight(ctx context.Context, sn string, id int64, channel string) (map[string]interface{}, error) {
	if channel != "cloud" && channel != "local" && channel != "offline" {
		return nil, fmt.Errorf("invalid channel")
	}
	f, d, err := s.repo.ValidateFirmwareForDevice(ctx, sn, id)
	reason := ""
	if err != nil {
		reason = repository.OTAEligibilityReason(err)
	} else if channel != "cloud" {
		reason = "device_protection_required"
	}
	result := map[string]interface{}{"eligible": reason == "", "compatibility_reason": reason, "channel": channel, "firmware_id": id}
	if f != nil {
		result["target_chip"] = f.TargetChip
		result["file_sha256"] = f.FileSHA256
	}
	if d != nil {
		result["identity_state"] = d.IdentityState
		result["identity_revision"] = d.IdentityRevision
	}
	return result, nil
}
