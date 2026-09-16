package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
)

var (
	ErrIdempotencyConflict   = repository.ErrIdempotencyConflict
	ErrDeviceNotFound        = repository.ErrDeviceNotFound
	ErrFirmwareNotPublished  = repository.ErrFirmwareNotPublished
	ErrDuplicateTarget       = repository.ErrDuplicateTarget
	ErrFirmwareNotDraft      = errors.New("only draft firmware can be deleted")
	ErrCurrentVersionUnknown = errors.New("current module version unreported")
)

// GetDeviceFirmwareOverview 组装设备四模块固件概览
func (s *OTAService) GetDeviceFirmwareOverview(ctx context.Context, sn string) (*model.DeviceFirmwareOverview, error) {
	device, err := s.repo.GetDeviceInfoForOTA(ctx, sn)
	if err != nil {
		return nil, err
	}
	targets := OrderFirmwareTargets([]string{"bms", "arm", "dsp", "esp"})
	modules := make([]model.FirmwareModuleOverview, 0, len(targets))
	for _, target := range targets {
		current, _ := CurrentModuleVersion(device.Model, device.FirmwareArm, device.FirmwareEsp, device.FirmwareDSP, device.FirmwareBMS, target)
		latest, _ := s.repo.GetLatestFirmware(ctx, sn, device.Model, target)
		modules = append(modules, FirmwareModuleOverview(target, current, device.IsOnline, latest))
	}
	return &model.DeviceFirmwareOverview{
		DeviceSN:    device.SN,
		DeviceModel: device.Model,
		IsOnline:    device.IsOnline,
		Modules:     modules,
	}, nil
}

// GetPublishedFirmwareResources 设备可安装已发布固件
func (s *OTAService) GetPublishedFirmwareResources(ctx context.Context, sn, target string) ([]model.Firmware, error) {
	resources, err := s.repo.ListPublishedFirmwareForDevice(ctx, sn, target)
	if err != nil {
		return nil, err
	}
	for i := range resources {
		// App/前端按 file_url 直接下载；库内为相对路径，必须补全域名
		resources[i].FileURL = s.BuildDownloadURL(resources[i].FileURL)
		resources[i].SupportedChannels = FirmwareSupportedChannels(resources[i].TargetChip)
	}
	return resources, nil
}

// PublishFirmware 发布固件（含范围/灰度/回退目标）
func (s *OTAService) PublishFirmware(ctx context.Context, id int64, actorID int64, opts model.FirmwarePublishOptions) error {
	return s.repo.PublishFirmware(ctx, id, actorID, opts)
}

// UpdateFirmwareRollout 发布后调整灰度
func (s *OTAService) UpdateFirmwareRollout(ctx context.Context, id int64, opts model.FirmwarePublishOptions) error {
	return s.repo.UpdateFirmwareRollout(ctx, id, opts)
}

// DisableFirmware 停用固件
func (s *OTAService) DisableFirmware(ctx context.Context, id int64, actorID int64) error {
	return s.repo.DisableFirmware(ctx, id, actorID)
}

// DeleteDraftFirmware 仅允许删除 draft
func (s *OTAService) DeleteDraftFirmware(ctx context.Context, id int64) error {
	st, err := s.repo.GetFirmwarePublishState(ctx, id)
	if err != nil {
		return err
	}
	if st != model.FirmwareReleaseDraft {
		return ErrFirmwareNotDraft
	}
	return s.repo.HardDeleteDraftFirmware(ctx, id)
}

// TriggerIndependentFirmware 触发独立模块升级（可多固件批量）
func (s *OTAService) TriggerIndependentFirmware(ctx context.Context, userID int64, req model.TriggerFirmwareRequest) ([]model.FirmwareTaskRef, error) {
	if strings.TrimSpace(req.DeviceSN) == "" {
		return nil, fmt.Errorf("device_sn required")
	}
	if len(req.FirmwareIDs) == 0 {
		return nil, fmt.Errorf("firmware_ids required")
	}
	if strings.TrimSpace(req.IdempotencyKey) == "" {
		return nil, fmt.Errorf("idempotency_key required")
	}
	refs, err := s.repo.CreateIndependentFirmwareTasks(ctx, userID, req.DeviceSN, req.FirmwareIDs, req.IdempotencyKey, "trigger", req.ForceReason)
	if err != nil {
		if errors.Is(err, repository.ErrDeviceOffline) {
			return nil, repository.ErrDeviceOffline
		}
		if errors.Is(err, repository.ErrCurrentVersionUnknown) {
			return nil, ErrCurrentVersionUnknown
		}
		return nil, err
	}
	// 同设备串行：立即尝试下发队首 pending
	if len(refs) > 0 {
		s.dispatchHeadPending(ctx, req.DeviceSN)
	}
	return refs, nil
}

// RollbackIndependentFirmware 回滚到指定固件
func (s *OTAService) RollbackIndependentFirmware(ctx context.Context, userID int64, sn string, firmwareID int64, idempotencyKey, forceReason string, isSystemAdmin bool) (*model.FirmwareTaskRef, error) {
	device, err := s.repo.GetDeviceInfoForOTA(ctx, sn)
	if err != nil {
		return nil, err
	}
	if !device.IsOnline {
		return nil, repository.ErrDeviceOffline
	}
	fw, err := s.repo.GetFirmware(ctx, firmwareID)
	if err != nil {
		return nil, fmt.Errorf("firmware not found: %w", err)
	}
	if fw.Model != device.Model {
		return nil, fmt.Errorf("firmware model mismatch")
	}
	target := strings.ToLower(strings.TrimSpace(fw.TargetChip))
	current, _ := CurrentModuleVersion(device.Model, device.FirmwareArm, device.FirmwareEsp, device.FirmwareDSP, device.FirmwareBMS, target)
	if current == "" && !isSystemAdmin {
		return nil, ErrCurrentVersionUnknown
	}
	if current == "" && isSystemAdmin && strings.TrimSpace(forceReason) == "" {
		return nil, fmt.Errorf("force_reason required when current version unreported")
	}
	refs, err := s.repo.CreateIndependentFirmwareTasks(ctx, userID, sn, []int64{firmwareID}, idempotencyKey, "rollback", forceReason)
	if err != nil {
		return nil, err
	}
	s.dispatchHeadPending(ctx, sn)
	if len(refs) == 0 {
		return nil, fmt.Errorf("rollback task not created")
	}
	return &refs[0], nil
}

// GetFilteredUpgradeHistory 历史筛选
func (s *OTAService) GetFilteredUpgradeHistory(ctx context.Context, f model.UpgradeHistoryFilter) ([]model.DeviceUpgrade, int, error) {
	return s.repo.ListUpgradeHistoryFiltered(ctx, f)
}

func (s *OTAService) ListAuthorizedDeviceSNs(ctx context.Context, actor model.ActorContext, permissionCode string) ([]string, error) {
	return s.repo.ListDeviceSNsByPermission(ctx, actor, permissionCode)
}

// dispatchHeadPending 仅下发同设备队首 pending 升级
func (s *OTAService) dispatchHeadPending(ctx context.Context, sn string) {
	du, fw, err := s.repo.GetPendingUpgradeForDevice(ctx, sn)
	if err != nil || du == nil || fw == nil {
		return
	}
	s.SendUpgradeCommand(ctx, du, fw, s.BuildDownloadURL(fw.FileURL))
}
