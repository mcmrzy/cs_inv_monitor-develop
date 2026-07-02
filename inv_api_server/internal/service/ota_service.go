package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type OTAService struct {
	repo         *repository.OTARepository
	rdb          *redis.Client
	deviceServer string
	internalKey  string
	serverURL    string // 外部访问地址，用于构造ESP32下载URL
	httpClient   *http.Client
	concurrency  int
}

func NewOTAService(repo *repository.OTARepository, rdb *redis.Client, deviceServer string, internalKey string, serverURL string) *OTAService {
	return &OTAService{
		repo:         repo,
		rdb:          rdb,
		deviceServer: deviceServer,
		internalKey:  internalKey,
		serverURL:    serverURL,
		httpClient:   &http.Client{Timeout: 30 * time.Second},
		concurrency:  10,
	}
}

type CreateFirmwareReq struct {
	Model      string
	TargetChip string
	Version    string
	FileURL    string
	FileSize   int64
	FileMD5    string
	FileSHA256 string
	Changelog  string
	IsForce    bool
}

func (s *OTAService) CreateFirmware(ctx context.Context, req *CreateFirmwareReq) error {
	// 自动生成主版本号：查询当前芯片的最大主版本号，+1
	latestVersion, err := s.repo.GetLatestMainVersion(ctx, req.TargetChip)
	if err != nil {
		return fmt.Errorf("查询主版本号失败: %w", err)
	}

	var nextMainVersion string
	if latestVersion == "" {
		nextMainVersion = "V1.0.1"
	} else {
		// 解析 "V1.0.X" 格式，提取 X 部分并 +1
		v := latestVersion
		if len(v) > 1 && v[0] == 'V' {
			v = v[1:]
		}
		parts := strings.Split(v, ".")
		if len(parts) >= 3 {
			var num int
			fmt.Sscanf(parts[len(parts)-1], "%d", &num)
			num++
			parts[len(parts)-1] = fmt.Sprintf("%d", num)
			nextMainVersion = "V" + strings.Join(parts, ".")
		} else {
			nextMainVersion = "V1.0.1"
		}
	}

	fw := &model.Firmware{
		Model:       req.Model,
		TargetChip:  req.TargetChip,
		MainVersion: nextMainVersion,
		Version:     req.Version,
		FileURL:     req.FileURL,
		FileSize:    req.FileSize,
		FileMD5:     req.FileMD5,
		FileSHA256:  req.FileSHA256,
		Changelog:   req.Changelog,
		IsForce:     req.IsForce,
	}
	return s.repo.CreateFirmware(ctx, fw)
}

func (s *OTAService) ListFirmware(ctx context.Context, model string) ([]model.Firmware, error) {
	return s.repo.ListFirmware(ctx, model)
}

func (s *OTAService) GetFirmware(ctx context.Context, id int64) (*model.Firmware, error) {
	return s.repo.GetFirmware(ctx, id)
}

func (s *OTAService) DeleteFirmware(ctx context.Context, id int64) error {
	return s.repo.DeleteFirmware(ctx, id)
}

type PushUpgradeReq struct {
	FirmwareID int64
	DeviceSNs  []string
	PushedBy   int64
	Immediate  bool // true=立即执行升级, false=仅通知
}

// PushUpgrade 管理员推送升级到设备（支持批量）
// 替代原 CreateTask + DispatchTask + NotifyDevices
func (s *OTAService) PushUpgrade(ctx context.Context, req *PushUpgradeReq) error {
	// 1. 一次性查询固件信息
	fw, err := s.repo.GetFirmware(ctx, req.FirmwareID)
	if err != nil || fw == nil {
		return fmt.Errorf("固件不存在")
	}

	// 2. 构造下载URL
	downloadURL := fw.FileURL
	if s.serverURL != "" && strings.HasPrefix(fw.FileURL, "/") {
		downloadURL = strings.TrimRight(s.serverURL, "/") + fw.FileURL
	}

	// 3. 对每个设备 UPSERT device_upgrades 记录并发送命令
	sem := make(chan struct{}, s.concurrency)
	var wg sync.WaitGroup

	for _, sn := range req.DeviceSNs {
		wg.Add(1)
		go func(deviceSN string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			// 查询设备当前固件版本作为 old_version（只记录目标芯片的版本）
			device, err := s.repo.GetDeviceBySN(ctx, deviceSN)
			oldVersion := ""
			if err == nil && device != nil {
				switch fw.TargetChip {
				case "arm":
					oldVersion = device.FirmwareArm
				case "esp":
					oldVersion = device.FirmwareEsp
				case "dsp":
					oldVersion = device.FirmwareDSP
				case "bms":
					oldVersion = device.FirmwareBMS
				default:
					oldVersion = device.VersionSummary()
				}
			}

			// UPSERT 升级记录
			du := &model.DeviceUpgrade{
				DeviceSN:        deviceSN,
				FirmwareID:      fw.ID,
				FirmwareVersion: fw.Version,
				TargetChip:      fw.TargetChip,
				OldVersion:      oldVersion,
				Status:          "pending",
				PushedBy:        &req.PushedBy,
			}
			if err := s.repo.UpsertDeviceUpgrade(ctx, du); err != nil {
				logger.Error("UpsertDeviceUpgrade failed",
					zap.String("sn", deviceSN), zap.Error(err))
				return
			}

			// 根据 immediate 参数决定立即升级还是仅通知
			if req.Immediate {
				s.SendUpgradeCommand(ctx, du, fw, downloadURL)
			}
		}(sn)
	}

	wg.Wait()

	logger.Info("OTA upgrade pushed",
		zap.Int64("firmware_id", req.FirmwareID),
		zap.Int("devices", len(req.DeviceSNs)),
		zap.Bool("immediate", req.Immediate))
	return nil
}

// SendUpgradeCommand 发送MQTT升级命令到设备
func (s *OTAService) SendUpgradeCommand(ctx context.Context, du *model.DeviceUpgrade, fw *model.Firmware, downloadURL string) {
	cmdBody := map[string]interface{}{
		"command":     "start",
		"action":      "start",
		"target":      fw.TargetChip,
		"url":         downloadURL,
		"version":     fw.Version,
		"file_md5":    fw.FileMD5,
		"file_sha256": fw.FileSHA256,
		"file_size":   fw.FileSize,
		"upgrade_id":  du.ID,
	}
	body, err := json.Marshal(cmdBody)
	if err != nil {
		logger.Error("marshal OTA command failed",
			zap.String("sn", du.DeviceSN), zap.Error(err))
		return
	}

	url := fmt.Sprintf("%s/api/v1/device/%s/command", s.deviceServer, du.DeviceSN)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		logger.Error("create OTA request failed",
			zap.String("sn", du.DeviceSN), zap.Error(err))
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if s.internalKey != "" {
		req.Header.Set("X-Internal-Key", s.internalKey)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		logger.Error("OTA dispatch failed",
			zap.String("sn", du.DeviceSN), zap.Error(err))
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		respBody, _ := io.ReadAll(resp.Body)
		logger.Error("device server error",
			zap.String("sn", du.DeviceSN),
			zap.Int("status", resp.StatusCode),
			zap.String("body", string(respBody)))
		return
	}

	logger.Info("OTA command sent to device",
		zap.String("sn", du.DeviceSN),
		zap.String("version", fw.Version))
}

// CheckPendingUpgrade 设备CheckUpdate时调用
func (s *OTAService) CheckPendingUpgrade(ctx context.Context, sn string) (*model.DeviceUpgrade, *model.Firmware, error) {
	return s.repo.GetPendingUpgradeForDevice(ctx, sn)
}

// UpdateDeviceUpgradeStatus 设备上报OTA状态时调用
func (s *OTAService) UpdateDeviceUpgradeStatus(ctx context.Context, deviceSN string, status string, progress int, message string) (int64, error) {
	rows, err := s.repo.UpdateUpgradeStatus(ctx, deviceSN, status, progress, message)
	if err != nil {
		return 0, err
	}

	// 更新关联任务的统计
	if status == "downloading" || status == "upgrading" || status == "success" || status == "failed" {
		go func() {
			bgCtx := context.Background()
			du, _ := s.repo.GetLatestTaskDevice(bgCtx, deviceSN)
			if du != nil && du.TaskID != nil && *du.TaskID > 0 {
				task, _ := s.repo.GetUpgradeTask(bgCtx, *du.TaskID)
				if task == nil {
					return
				}

				// 设备开始升级时，自动将 pending/scheduled 任务转为 running
				if task.Status == "pending" || task.Status == "scheduled" || task.Status == "draft" {
					s.repo.UpdateUpgradeTaskStatus(bgCtx, *du.TaskID, "running")
					task.Status = "running"
				}

				// 设备升级完成时，更新任务统计并检查任务是否全部完成
				if status == "success" || status == "failed" {
					s.repo.UpdateUpgradeTaskCounts(bgCtx, *du.TaskID)
					devices, _ := s.repo.ListUpgradeDevicesByTaskID(bgCtx, *du.TaskID)
					allDone := true
					hasFailure := false
					for _, d := range devices {
						if d.Status == "pending" || d.Status == "downloading" || d.Status == "upgrading" {
							allDone = false
							break
						}
						if d.Status == "failed" {
							hasFailure = true
						}
					}
					if allDone {
						if hasFailure {
							s.repo.UpdateUpgradeTaskStatus(bgCtx, *du.TaskID, "partial_success")
						} else {
							s.repo.UpdateUpgradeTaskStatus(bgCtx, *du.TaskID, "completed")
						}
					}
				}
			}
		}()
	}

	// 单芯片升级成功时，自动触发同升级包中下一个芯片
	if status == "success" {
		go func() {
			bgCtx := context.Background()
			// 查找该设备最近的升级包升级记录
			du, _ := s.repo.GetLatestTaskDevice(bgCtx, deviceSN)
			if du != nil && du.UpgradePackageID != nil && *du.UpgradePackageID > 0 {
				s.OnChipUpgradeComplete(bgCtx, deviceSN, *du.UpgradePackageID)
			}
		}()
	}

	return rows, nil
}

// RetryUpgrade 重试失败的升级
func (s *OTAService) RetryUpgrade(ctx context.Context, firmwareID int64, deviceSNs []string) error {
	fw, err := s.repo.GetFirmware(ctx, firmwareID)
	if err != nil || fw == nil {
		return fmt.Errorf("固件不存在")
	}

	if err := s.repo.RetryFailedUpgrades(ctx, firmwareID, deviceSNs); err != nil {
		return err
	}

	// 重新发送升级命令
	downloadURL := fw.FileURL
	if s.serverURL != "" && strings.HasPrefix(fw.FileURL, "/") {
		downloadURL = strings.TrimRight(s.serverURL, "/") + fw.FileURL
	}

	for _, sn := range deviceSNs {
		du, err := s.repo.GetDeviceUpgrade(ctx, sn, firmwareID)
		if err != nil || du == nil || du.Status != "pending" {
			continue
		}
		go s.SendUpgradeCommand(context.Background(), du, fw, downloadURL)
	}

	return nil
}

// GetUpgradeDashboard 获取升级管理面板数据
func (s *OTAService) GetUpgradeDashboard(ctx context.Context, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	return s.repo.ListUpgradesByFirmware(ctx, page, pageSize)
}

// GetFirmwareUpgradeDetails 获取指定固件的升级详情列表
func (s *OTAService) GetFirmwareUpgradeDetails(ctx context.Context, firmwareID int64) ([]model.DeviceUpgrade, error) {
	return s.repo.ListUpgradesByFirmwareID(ctx, firmwareID)
}

// GetDeviceUpgradeHistory 获取设备升级历史
func (s *OTAService) GetDeviceUpgradeHistory(ctx context.Context, sn string, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	return s.repo.GetDeviceUpgradeHistory(ctx, sn, page, pageSize)
}

// CancelUpgrade 取消待执行的升级
func (s *OTAService) CancelUpgrade(ctx context.Context, deviceSN string, firmwareID int64) error {
	return s.repo.CancelUpgrade(ctx, deviceSN, firmwareID)
}

// DeleteUpgradesByFirmwareID 删除指定固件的所有升级记录
func (s *OTAService) DeleteUpgradesByFirmwareID(ctx context.Context, firmwareID int64) error {
	return s.repo.DeleteUpgradesByFirmwareID(ctx, firmwareID)
}

// GetDeviceBySN 获取设备信息
func (s *OTAService) GetDeviceBySN(ctx context.Context, sn string) (*repository.DeviceInfo, error) {
	return s.repo.GetDeviceBySN(ctx, sn)
}

// CheckDeviceOwnership 检查设备是否属于指定用户
func (s *OTAService) CheckDeviceOwnership(ctx context.Context, sn string, userID int64) (bool, error) {
	return s.repo.CheckDeviceOwnership(ctx, sn, userID)
}

// GetLatestFirmware 获取指定型号的最新固件
func (s *OTAService) GetLatestFirmware(ctx context.Context, deviceModel string, targetChip string) (*model.Firmware, error) {
	return s.repo.GetLatestFirmware(ctx, deviceModel, targetChip)
}

// GetLatestTaskDevice 兼容旧接口
func (s *OTAService) GetLatestTaskDevice(ctx context.Context, sn string) (*model.DeviceUpgrade, error) {
	return s.repo.GetLatestTaskDevice(ctx, sn)
}

// GetDeviceOTAHistory 兼容旧接口
func (s *OTAService) GetDeviceOTAHistory(ctx context.Context, sn string, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	return s.repo.GetDeviceUpgradeHistory(ctx, sn, page, pageSize)
}

// ========== App版本管理 ==========

// CheckAppUpdate 检查App是否有新版本
func (s *OTAService) CheckAppUpdate(ctx context.Context, platform string, currentVersionCode int) (*model.AppVersion, bool, error) {
	latest, err := s.repo.GetLatestAppVersion(ctx, platform)
	if err != nil {
		return nil, false, err
	}
	hasUpdate := latest.VersionCode > currentVersionCode
	return latest, hasUpdate, nil
}

// CreateAppVersion 创建App版本
func (s *OTAService) CreateAppVersion(ctx context.Context, v *model.AppVersion) error {
	return s.repo.CreateAppVersion(ctx, v)
}

// ListAppVersions 列出App版本
func (s *OTAService) ListAppVersions(ctx context.Context, platform string) ([]model.AppVersion, error) {
	return s.repo.ListAppVersions(ctx, platform)
}

// DeleteAppVersion 删除App版本
func (s *OTAService) DeleteAppVersion(ctx context.Context, id int64) error {
	return s.repo.DeleteAppVersion(ctx, id)
}

// UpdateAppVersionRollout 更新灰度比例
func (s *OTAService) UpdateAppVersionRollout(ctx context.Context, id int64, percentage int) error {
	return s.repo.UpdateAppVersionRollout(ctx, id, percentage)
}

// RollbackAppVersion 回滚App版本
func (s *OTAService) RollbackAppVersion(ctx context.Context, id int64) error {
	return s.repo.RollbackAppVersion(ctx, id)
}

// RestoreAppVersion 恢复已回滚的App版本
func (s *OTAService) RestoreAppVersion(ctx context.Context, id int64, percentage int) error {
	return s.repo.RestoreAppVersion(ctx, id, percentage)
}

// ========== 升级包管理 ==========

type CreatePackageReq struct {
	Model       string
	FirmwareIDs []int64
	Changelog   string
	IsForce     bool
	CreatedBy   int64
}

// CreateUpgradePackage 创建升级包
func (s *OTAService) CreateUpgradePackage(ctx context.Context, req *CreatePackageReq) error {
	if len(req.FirmwareIDs) == 0 {
		return fmt.Errorf("请至少选择一个固件")
	}

	// 查询所有固件并校验
	chipSeen := map[string]bool{}
	var items []model.UpgradePackageItem
	for _, fwID := range req.FirmwareIDs {
		fw, err := s.repo.GetFirmware(ctx, fwID)
		if err != nil || fw == nil {
			return fmt.Errorf("固件 %d 不存在", fwID)
		}
		if chipSeen[fw.TargetChip] {
			return fmt.Errorf("同一芯片 %s 不能选择多个固件", fw.TargetChip)
		}
		chipSeen[fw.TargetChip] = true
		items = append(items, model.UpgradePackageItem{
			FirmwareID:      fw.ID,
			TargetChip:      fw.TargetChip,
			FirmwareVersion: fw.Version,
		})
	}

	// 生成主版本号
	mainVersion, err := s.generateMainVersion(ctx, req.Model)
	if err != nil {
		return fmt.Errorf("生成主版本号失败: %w", err)
	}

	pkg := &model.UpgradePackage{
		Model:       req.Model,
		MainVersion: mainVersion,
		Changelog:   req.Changelog,
		IsForce:     req.IsForce,
		CreatedBy:   req.CreatedBy,
		Items:       items,
	}
	return s.repo.CreateUpgradePackage(ctx, pkg)
}

// ListUpgradePackages 升级包列表
func (s *OTAService) ListUpgradePackages(ctx context.Context, modelFilter string) ([]model.UpgradePackage, error) {
	return s.repo.ListUpgradePackages(ctx, modelFilter)
}

// GetUpgradePackage 升级包详情
func (s *OTAService) GetUpgradePackage(ctx context.Context, id int64) (*model.UpgradePackage, error) {
	return s.repo.GetUpgradePackage(ctx, id)
}

// DeleteUpgradePackage 删除升级包
func (s *OTAService) DeleteUpgradePackage(ctx context.Context, id int64) error {
	return s.repo.DeleteUpgradePackage(ctx, id)
}

type PushPackageUpgradeReq struct {
	PackageID      int64
	DeviceSNs      []string
	PushedBy       int64
	Immediate      bool
	RolloutPercent int
}

// PushPackageUpgrade 推送升级包升级
func (s *OTAService) PushPackageUpgrade(ctx context.Context, req *PushPackageUpgradeReq) error {
	// 1. 查询升级包
	pkg, err := s.repo.GetUpgradePackage(ctx, req.PackageID)
	if err != nil || pkg == nil {
		return fmt.Errorf("升级包不存在")
	}

	// 1.5 灰度推送：只选择 X% 的设备
	deviceSNs := req.DeviceSNs
	if req.RolloutPercent > 0 && req.RolloutPercent < 100 {
		targetCount := len(deviceSNs) * req.RolloutPercent / 100
		if targetCount < 1 {
			targetCount = 1
		}
		// 随机打乱
		rand.Shuffle(len(deviceSNs), func(i, j int) {
			deviceSNs[i], deviceSNs[j] = deviceSNs[j], deviceSNs[i]
		})
		deviceSNs = deviceSNs[:targetCount]
		logger.Info("Gray rollout",
			zap.Int("percent", req.RolloutPercent),
			zap.Int("total", len(req.DeviceSNs)),
			zap.Int("selected", targetCount))
	}

	// 2. 对每个设备处理
	sem := make(chan struct{}, s.concurrency)
	var wg sync.WaitGroup

	for _, sn := range deviceSNs {
		wg.Add(1)
		go func(deviceSN string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			// 查询设备当前各芯片版本
			device, err := s.repo.GetDeviceBySN(ctx, deviceSN)
			if err != nil || device == nil {
				logger.Error("PushPackageUpgrade: device not found", zap.String("sn", deviceSN))
				return
			}

			chipVersions := map[string]string{
				"arm": device.FirmwareArm,
				"esp": device.FirmwareEsp,
				"dsp": device.FirmwareDSP,
				"bms": device.FirmwareBMS,
			}

			var firstPendingDU *model.DeviceUpgrade
			var firstPendingFW *model.Firmware

			// 3. 对比每个芯片，确定需要升级的
			for _, item := range pkg.Items {
				currentVer := chipVersions[item.TargetChip]
				if currentVer == item.FirmwareVersion {
					// 版本相同，跳过
					continue
				}

				// 获取固件详情
				fw, err := s.repo.GetFirmware(ctx, item.FirmwareID)
				if err != nil || fw == nil {
					logger.Error("PushPackageUpgrade: firmware not found",
						zap.Int64("firmware_id", item.FirmwareID))
					continue
				}

				pkgID := pkg.ID
				du := &model.DeviceUpgrade{
					DeviceSN:         deviceSN,
					FirmwareID:       fw.ID,
					FirmwareVersion:  fw.Version,
					TargetChip:       fw.TargetChip,
					OldVersion:       currentVer,
					Status:           "pending",
					PushedBy:         &req.PushedBy,
					UpgradePackageID: &pkgID,
				}
				if err := s.repo.UpsertPackageUpgrade(ctx, du); err != nil {
					logger.Error("PushPackageUpgrade: UpsertPackageUpgrade failed",
						zap.String("sn", deviceSN), zap.String("chip", fw.TargetChip), zap.Error(err))
					continue
				}

				// 记录第一个待升级的芯片
				if firstPendingDU == nil {
					firstPendingDU = du
					firstPendingFW = fw
				}
			}

			// 4. 如果 immediate=true，发送第一个芯片的升级命令
			if req.Immediate && firstPendingDU != nil && firstPendingFW != nil {
				s.SendUpgradeCommand(ctx, firstPendingDU, firstPendingFW, s.BuildDownloadURL(firstPendingFW.FileURL))
			}
		}(sn)
	}

	wg.Wait()

	logger.Info("Package upgrade pushed",
		zap.Int64("package_id", req.PackageID),
		zap.Int("devices", len(req.DeviceSNs)),
		zap.Bool("immediate", req.Immediate))
	return nil
}

// RollbackPackageUpgrade 回滚升级包：对已成功升级的设备恢复到旧固件
func (s *OTAService) RollbackPackageUpgrade(ctx context.Context, packageID int64, immediate bool, pushedBy int64) error {
	// 1. 获取升级包信息
	pkg, err := s.repo.GetUpgradePackage(ctx, packageID)
	if err != nil || pkg == nil {
		return fmt.Errorf("升级包不存在")
	}

	// 2. 查询该包下所有成功升级的记录
	successUpgrades, err := s.repo.GetSuccessfulUpgradesByPackage(ctx, packageID)
	if err != nil {
		return fmt.Errorf("查询升级记录失败: %w", err)
	}
	if len(successUpgrades) == 0 {
		return fmt.Errorf("无可回滚的设备（无成功升级记录）")
	}

	// 3. 对每条记录查找旧固件并创建回滚升级记录
	sem := make(chan struct{}, s.concurrency)
	var wg sync.WaitGroup

	for _, du := range successUpgrades {
		wg.Add(1)
		go func(origDU model.DeviceUpgrade) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			if origDU.OldVersion == "" {
				logger.Warn("RollbackPackageUpgrade: no old_version recorded",
					zap.String("sn", origDU.DeviceSN), zap.String("chip", origDU.TargetChip))
				return
			}

			// 查找旧固件（按型号+版本+芯片）
			oldFW, err := s.repo.FindFirmwareByVersion(ctx, pkg.Model, origDU.OldVersion, origDU.TargetChip)
			if err != nil || oldFW == nil {
				logger.Error("RollbackPackageUpgrade: old firmware not found",
					zap.String("model", pkg.Model),
					zap.String("version", origDU.OldVersion),
					zap.String("chip", origDU.TargetChip))
				return
			}

			pkgID := pkg.ID
			rollbackDU := &model.DeviceUpgrade{
				DeviceSN:         origDU.DeviceSN,
				FirmwareID:       oldFW.ID,
				FirmwareVersion:  oldFW.Version,
				TargetChip:       oldFW.TargetChip,
				OldVersion:       origDU.FirmwareVersion, // 当前版本作为“旧版本”
				Status:           "pending",
				PushedBy:         &pushedBy,
				UpgradePackageID: &pkgID,
			}
			if err := s.repo.UpsertPackageUpgrade(ctx, rollbackDU); err != nil {
				logger.Error("RollbackPackageUpgrade: upsert failed",
					zap.String("sn", origDU.DeviceSN), zap.Error(err))
				return
			}

			// 4. 如果 immediate=true，发送升级命令
			if immediate {
				s.SendUpgradeCommand(ctx, rollbackDU, oldFW, s.BuildDownloadURL(oldFW.FileURL))
			}
		}(du)
	}

	wg.Wait()

	logger.Info("Package rollback completed",
		zap.Int64("package_id", packageID),
		zap.Int("devices", len(successUpgrades)),
		zap.Bool("immediate", immediate))
	return nil
}

// OnChipUpgradeComplete 单芯片升级完成后自动触发下一芯片
func (s *OTAService) OnChipUpgradeComplete(ctx context.Context, deviceSN string, packageID int64) {
	if packageID <= 0 {
		return
	}

	// 获取该设备在该升级包下的所有升级记录
	upgrades, err := s.repo.GetUpgradeBySNAndPackage(ctx, deviceSN, packageID)
	if err != nil || len(upgrades) == 0 {
		return
	}

	// 查找下一个 pending 的芯片
	var nextDU *model.DeviceUpgrade
	allDone := true
	for _, du := range upgrades {
		if du.Status == "pending" {
			if nextDU == nil {
				du2 := du // copy
				nextDU = &du2
			}
			allDone = false
		} else if du.Status != "success" && du.Status != "cancelled" {
			allDone = false
		}
	}

	if nextDU != nil {
		// 发送下一个芯片的升级命令
		fw, err := s.repo.GetFirmware(ctx, nextDU.FirmwareID)
		if err == nil && fw != nil {
			s.SendUpgradeCommand(ctx, nextDU, fw, s.BuildDownloadURL(fw.FileURL))
		}
		return
	}

	if allDone {
		// 全部芯片升级完成，更新设备主版本号
		pkg, err := s.repo.GetUpgradePackage(ctx, packageID)
		if err == nil && pkg != nil {
			if err := s.repo.UpdateDeviceMainVersion(ctx, deviceSN, pkg.MainVersion); err != nil {
				logger.Error("OnChipUpgradeComplete: update main_version failed",
					zap.String("sn", deviceSN), zap.Error(err))
			} else {
				logger.Info("All chips upgraded, main_version updated",
					zap.String("sn", deviceSN), zap.String("main_version", pkg.MainVersion))
			}
		}
	}
}

// CheckPendingPackageUpgrade 设备CheckUpdate时检查升级包模式
func (s *OTAService) CheckPendingPackageUpgrade(ctx context.Context, sn string) ([]model.DeviceUpgrade, *model.UpgradePackage, error) {
	return s.repo.GetPendingPackageUpgradeForDevice(ctx, sn)
}

// GetPackageUpgradesByPackageID 获取升级包的所有升级记录
func (s *OTAService) GetPackageUpgradesByPackageID(ctx context.Context, packageID int64) ([]model.DeviceUpgrade, error) {
	return s.repo.GetPackageUpgradesByPackageID(ctx, packageID)
}

// generateMainVersion 生成 Va.b.c.YYYYMMDD 格式版本号
func (s *OTAService) generateMainVersion(ctx context.Context, model string) (string, error) {
	latest, _ := s.repo.GetLatestPackageVersion(ctx, model)

	now := time.Now()
	dateStr := now.Format("20060102")

	if latest == "" {
		// 第一个版本
		return fmt.Sprintf("V1.0.0.%s", dateStr), nil
	}

	// 解析已有版本号: Va.b.c.YYYYMMDD
	re := regexp.MustCompile(`^V(\d+)\.(\d+)\.(\d+)\.(\d{8})$`)
	matches := re.FindStringSubmatch(latest)
	if len(matches) != 5 {
		// 无法解析，从 V1.0.0 开始
		return fmt.Sprintf("V1.0.0.%s", dateStr), nil
	}

	a, _ := strconv.Atoi(matches[1])
	b, _ := strconv.Atoi(matches[2])
	c, _ := strconv.Atoi(matches[3])
	latestDate := matches[4]

	if latestDate == dateStr {
		// 同一天，c+1
		c++
	} else {
		// 不同天，c 归零，b+1；如果 b >= 10 则 a+1, b 归零
		c = 0
		b++
		if b >= 10 {
			b = 0
			a++
		}
	}

	return fmt.Sprintf("V%d.%d.%d.%s", a, b, c, dateStr), nil
}

// BuildDownloadURL 构造固件下载URL（公开方法）
func (s *OTAService) BuildDownloadURL(fileURL string) string {
	if s.serverURL != "" && strings.HasPrefix(fileURL, "/") {
		return strings.TrimRight(s.serverURL, "/") + fileURL
	}
	return fileURL
}

// ResendPendingUpgradeCommand 重新发送设备待执行的升级命令
func (s *OTAService) ResendPendingUpgradeCommand(ctx context.Context, sn string) error {
	upgrades, err := s.repo.GetPendingUpgradesBySN(ctx, sn)
	if err != nil {
		return fmt.Errorf("查询待升级记录失败: %w", err)
	}
	if len(upgrades) == 0 {
		return fmt.Errorf("没有待执行的升级任务")
	}
	for _, du := range upgrades {
		fw, err := s.repo.GetFirmware(ctx, du.FirmwareID)
		if err != nil || fw == nil {
			logger.Error("ResendPendingUpgradeCommand: firmware not found",
				zap.Int64("firmware_id", du.FirmwareID))
			continue
		}
		go s.SendUpgradeCommand(context.Background(), &du, fw, s.BuildDownloadURL(fw.FileURL))
	}
	logger.Info("Pending upgrade commands resent",
		zap.String("sn", sn), zap.Int("count", len(upgrades)))
	return nil
}

// ========== 升级任务管理 ==========

type CreateUpgradeTaskReq struct {
	Name           string
	TaskType       string   // 'single' | 'package'
	FirmwareID     *int64   // 单芯片模式
	PackageID      *int64   // 升级包模式
	Model          string
	DeviceSNs      []string
	ExecuteMode    string   // 'immediate' | 'scheduled' | 'manual'
	ScheduledAt    *time.Time
	RolloutPercent int
	CreatedBy      int64
}

// CreateUpgradeTask 创建升级任务（统一入口）
func (s *OTAService) CreateUpgradeTask(ctx context.Context, req *CreateUpgradeTaskReq) (*model.UpgradeTask, error) {
	if len(req.DeviceSNs) == 0 {
		return nil, fmt.Errorf("请至少选择一台设备")
	}

	// 确定目标版本
	targetVersion := ""
	if req.TaskType == "single" && req.FirmwareID != nil {
		fw, err := s.repo.GetFirmware(ctx, *req.FirmwareID)
		if err != nil || fw == nil {
			return nil, fmt.Errorf("固件不存在")
		}
		targetVersion = fw.Version
		req.Model = fw.Model
	} else if req.TaskType == "package" && req.PackageID != nil {
		pkg, err := s.repo.GetUpgradePackage(ctx, *req.PackageID)
		if err != nil || pkg == nil {
			return nil, fmt.Errorf("升级包不存在")
		}
		targetVersion = pkg.MainVersion
		req.Model = pkg.Model
	} else {
		return nil, fmt.Errorf("请选择固件或升级包")
	}

	// 灰度处理
	deviceSNs := req.DeviceSNs
	if req.RolloutPercent > 0 && req.RolloutPercent < 100 {
		targetCount := len(deviceSNs) * req.RolloutPercent / 100
		if targetCount < 1 {
			targetCount = 1
		}
		rand.Shuffle(len(deviceSNs), func(i, j int) {
			deviceSNs[i], deviceSNs[j] = deviceSNs[j], deviceSNs[i]
		})
		deviceSNs = deviceSNs[:targetCount]
	}

	// 确定初始状态
	status := "pending"
	if req.ExecuteMode == "scheduled" {
		status = "scheduled"
	}

	createdBy := req.CreatedBy
	task := &model.UpgradeTask{
		Name:           req.Name,
		TaskType:       req.TaskType,
		FirmwareID:     req.FirmwareID,
		PackageID:      req.PackageID,
		Model:          req.Model,
		TargetVersion:  targetVersion,
		Status:         status,
		ExecuteMode:    req.ExecuteMode,
		ScheduledAt:    req.ScheduledAt,
		RolloutPercent: req.RolloutPercent,
		TotalDevices:   len(deviceSNs),
		CreatedBy:      &createdBy,
	}

	if err := s.repo.CreateUpgradeTask(ctx, task); err != nil {
		return nil, fmt.Errorf("创建任务失败: %w", err)
	}

	// 为每个设备创建 device_upgrades 记录
	if req.TaskType == "single" && req.FirmwareID != nil {
		fw, _ := s.repo.GetFirmware(ctx, *req.FirmwareID)
		if fw != nil {
			for _, sn := range deviceSNs {
				device, _ := s.repo.GetDeviceBySN(ctx, sn)
				oldVersion := ""
				if device != nil {
					switch fw.TargetChip {
					case "arm":
						oldVersion = device.FirmwareArm
					case "esp":
						oldVersion = device.FirmwareEsp
					case "dsp":
						oldVersion = device.FirmwareDSP
					case "bms":
						oldVersion = device.FirmwareBMS
					default:
						oldVersion = device.VersionSummary()
					}
				}
				taskID := task.ID
				du := &model.DeviceUpgrade{
					DeviceSN:        sn,
					FirmwareID:      fw.ID,
					FirmwareVersion: fw.Version,
					TargetChip:      fw.TargetChip,
					OldVersion:      oldVersion,
					Status:          "pending",
					PushedBy:        &createdBy,
					TaskID:          &taskID,
				}
				s.repo.UpsertDeviceUpgradeWithTask(ctx, du)
			}
		}
	} else if req.TaskType == "package" && req.PackageID != nil {
		pkg, _ := s.repo.GetUpgradePackage(ctx, *req.PackageID)
		if pkg != nil {
			for _, sn := range deviceSNs {
				device, _ := s.repo.GetDeviceBySN(ctx, sn)
				if device == nil {
					continue
				}
				chipVersions := map[string]string{
					"arm": device.FirmwareArm,
					"esp": device.FirmwareEsp,
					"dsp": device.FirmwareDSP,
					"bms": device.FirmwareBMS,
				}
				taskID := task.ID
				pkgID := pkg.ID
				for _, item := range pkg.Items {
					currentVer := chipVersions[item.TargetChip]
					if currentVer == item.FirmwareVersion {
						continue
					}
					du := &model.DeviceUpgrade{
						DeviceSN:         sn,
						FirmwareID:       item.FirmwareID,
						FirmwareVersion:  item.FirmwareVersion,
						TargetChip:       item.TargetChip,
						OldVersion:       currentVer,
						Status:           "pending",
						PushedBy:         &createdBy,
						UpgradePackageID: &pkgID,
						TaskID:           &taskID,
					}
					s.repo.UpsertDeviceUpgradeWithTask(ctx, du)
				}
			}
		}
	}

	// 如果 execute_mode = immediate，自动执行
	if req.ExecuteMode == "immediate" {
		go s.ExecuteTask(context.Background(), task.ID)
	}

	logger.Info("Upgrade task created",
		zap.Int64("task_id", task.ID),
		zap.String("type", req.TaskType),
		zap.Int("devices", len(deviceSNs)),
		zap.String("execute_mode", req.ExecuteMode))

	return task, nil
}

// ExecuteTask 执行升级任务
func (s *OTAService) ExecuteTask(ctx context.Context, taskID int64) error {
	task, err := s.repo.GetUpgradeTask(ctx, taskID)
	if err != nil || task == nil {
		return fmt.Errorf("任务不存在")
	}

	if task.Status != "pending" && task.Status != "scheduled" {
		return fmt.Errorf("任务状态不允许执行: %s", task.Status)
	}

	// 更新状态为 running
	s.repo.UpdateUpgradeTaskStatus(ctx, taskID, "running")

	// 获取任务下的所有 pending device_upgrades
	devices, err := s.repo.ListUpgradeDevicesByTaskID(ctx, taskID)
	if err != nil {
		return fmt.Errorf("查询设备列表失败: %w", err)
	}

	if task.TaskType == "single" && task.FirmwareID != nil {
		// 单芯片模式：直接发送命令
		fw, err := s.repo.GetFirmware(ctx, *task.FirmwareID)
		if err != nil || fw == nil {
			return fmt.Errorf("固件不存在")
		}
		downloadURL := s.BuildDownloadURL(fw.FileURL)
		sem := make(chan struct{}, s.concurrency)
		var wg sync.WaitGroup
		for _, du := range devices {
			if du.Status != "pending" {
				continue
			}
			wg.Add(1)
			go func(d model.DeviceUpgrade) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()
				s.SendUpgradeCommand(ctx, &d, fw, downloadURL)
			}(du)
		}
		wg.Wait()
	} else if task.TaskType == "package" && task.PackageID != nil {
		// 升级包模式：对每个设备发送第一个芯片的命令（链式升级由 OnChipUpgradeComplete 触发）
		sentDevices := map[string]bool{}
		sem := make(chan struct{}, s.concurrency)
		var wg sync.WaitGroup
		for _, du := range devices {
			if du.Status != "pending" || sentDevices[du.DeviceSN] {
				continue
			}
			sentDevices[du.DeviceSN] = true
			fw, err := s.repo.GetFirmware(ctx, du.FirmwareID)
			if err != nil || fw == nil {
				continue
			}
			wg.Add(1)
			go func(d model.DeviceUpgrade, f *model.Firmware) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()
				s.SendUpgradeCommand(ctx, &d, f, s.BuildDownloadURL(f.FileURL))
			}(du, fw)
		}
		wg.Wait()
	}

	logger.Info("Upgrade task executed", zap.Int64("task_id", taskID))
	return nil
}

// ListUpgradeTasks 升级任务列表
func (s *OTAService) ListUpgradeTasks(ctx context.Context, page, pageSize int, statusFilter string) ([]model.UpgradeTask, int, error) {
	tasks, total, err := s.repo.ListUpgradeTasks(ctx, page, pageSize, statusFilter)
	if err != nil {
		return nil, 0, err
	}

	// 填充关联信息
	for i := range tasks {
		if tasks[i].TaskType == "single" && tasks[i].FirmwareID != nil {
			fw, _ := s.repo.GetFirmware(ctx, *tasks[i].FirmwareID)
			if fw != nil {
				tasks[i].FirmwareVersion = fw.Version
				tasks[i].FirmwareTargetChip = fw.TargetChip
			}
		} else if tasks[i].TaskType == "package" && tasks[i].PackageID != nil {
			pkg, _ := s.repo.GetUpgradePackage(ctx, *tasks[i].PackageID)
			if pkg != nil {
				tasks[i].PackageMainVersion = pkg.MainVersion
				tasks[i].PackageItems = pkg.Items
			}
		}
	}
	return tasks, total, nil
}

// GetUpgradeTask 获取任务详情
func (s *OTAService) GetUpgradeTask(ctx context.Context, taskID int64) (*model.UpgradeTask, error) {
	task, err := s.repo.GetUpgradeTask(ctx, taskID)
	if err != nil {
		return nil, err
	}
	// 填充关联信息
	if task.TaskType == "single" && task.FirmwareID != nil {
		fw, _ := s.repo.GetFirmware(ctx, *task.FirmwareID)
		if fw != nil {
			task.FirmwareVersion = fw.Version
			task.FirmwareTargetChip = fw.TargetChip
		}
	} else if task.TaskType == "package" && task.PackageID != nil {
		pkg, _ := s.repo.GetUpgradePackage(ctx, *task.PackageID)
		if pkg != nil {
			task.PackageMainVersion = pkg.MainVersion
			task.PackageItems = pkg.Items
		}
	}
	return task, nil
}

// GetUpgradeTaskDevices 获取任务下设备详情
func (s *OTAService) GetUpgradeTaskDevices(ctx context.Context, taskID int64) ([]model.DeviceUpgrade, error) {
	return s.repo.ListUpgradeDevicesByTaskID(ctx, taskID)
}

// RetryTaskFailed 重试任务下失败的设备
func (s *OTAService) RetryTaskFailed(ctx context.Context, taskID int64) error {
	task, err := s.repo.GetUpgradeTask(ctx, taskID)
	if err != nil || task == nil {
		return fmt.Errorf("任务不存在")
	}

	// 重置失败记录
	if err := s.repo.RetryFailedUpgradesByTask(ctx, taskID); err != nil {
		return err
	}

	// 重新发送命令
	devices, err := s.repo.ListUpgradeDevicesByTaskID(ctx, taskID)
	if err != nil {
		return err
	}

	sentDevices := map[string]bool{}
	for _, du := range devices {
		if du.Status != "pending" || sentDevices[du.DeviceSN] {
			continue
		}
		fw, err := s.repo.GetFirmware(ctx, du.FirmwareID)
		if err != nil || fw == nil {
			continue
		}
		sentDevices[du.DeviceSN] = true
		go s.SendUpgradeCommand(context.Background(), &du, fw, s.BuildDownloadURL(fw.FileURL))
	}

	// 更新任务状态为 running
	s.repo.UpdateUpgradeTaskStatus(ctx, taskID, "running")
	return nil
}

// CancelTask 取消任务
func (s *OTAService) CancelTask(ctx context.Context, taskID int64) error {
	task, err := s.repo.GetUpgradeTask(ctx, taskID)
	if err != nil || task == nil {
		return fmt.Errorf("任务不存在")
	}
	if task.Status == "completed" || task.Status == "cancelled" {
		return fmt.Errorf("任务状态不允许取消: %s", task.Status)
	}

	// 取消待执行的设备升级
	if err := s.repo.CancelUpgradesByTask(ctx, taskID); err != nil {
		return fmt.Errorf("取消设备升级失败: %w", err)
	}
	// 更新任务状态
	if err := s.repo.UpdateUpgradeTaskStatus(ctx, taskID, "cancelled"); err != nil {
		return fmt.Errorf("更新任务状态失败: %w", err)
	}
	return nil
}

// DeleteUpgradeTask 删除任务
func (s *OTAService) DeleteUpgradeTask(ctx context.Context, taskID int64) error {
	task, err := s.repo.GetUpgradeTask(ctx, taskID)
	if err != nil || task == nil {
		return fmt.Errorf("任务不存在")
	}
	if task.Status == "running" {
		return fmt.Errorf("执行中的任务不能删除")
	}
	return s.repo.DeleteUpgradeTask(ctx, taskID)
}

// GetTaskStats 获取任务统计
func (s *OTAService) GetTaskStats(ctx context.Context) (pending, running, todayCompleted, failed int, err error) {
	return s.repo.GetTaskStats(ctx)
}

// ReportLocalOTAResult 本地OTA完成后，更新设备固件版本并记录升级历史
func (s *OTAService) ReportLocalOTAResult(ctx context.Context, sn string, targetChip string, newVersion string, mainVersion string) error {
	return s.repo.ReportLocalOTAResult(ctx, sn, targetChip, newVersion, mainVersion)
}
