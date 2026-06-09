package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
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

type CreateTaskReq struct {
	Name        string
	FirmwareID  int64
	Model       string
	TargetType  string
	TargetValue string
	DeviceSNs   []string
	Description string
}

func (s *OTAService) CreateTask(ctx context.Context, req *CreateTaskReq) (*model.OtaTask, error) {
	fw, err := s.repo.GetFirmware(ctx, req.FirmwareID)
	if err != nil || fw == nil {
		return nil, fmt.Errorf("固件不存在")
	}

	task := &model.OtaTask{
		ID: fmt.Sprintf("ota-%d-%d", req.FirmwareID, time.Now().UnixMilli()),
		Name:        req.Name,
		FirmwareID:  req.FirmwareID,
		FirmwareVersion: fw.Version,
		Model:       req.Model,
		TargetType:  req.TargetType,
		TargetValue: req.TargetValue,
		TotalCount:  len(req.DeviceSNs),
		Status:      "pending",
		Description: req.Description,
		PushStrategy: "all_at_once",
		PushPercentage: 100,
		BatchSize:   10,
	}

	if err := s.repo.CreateTask(ctx, task); err != nil {
		return nil, err
	}

	for _, sn := range req.DeviceSNs {
		s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:     task.ID,
			DeviceSN:   sn,
			Status:     "pending",
			NewVersion: fw.Version,
		})
	}

	return task, nil
}

func (s *OTAService) ListTasks(ctx context.Context, status string, page, pageSize int) ([]model.OtaTask, int, error) {
	return s.repo.ListTasks(ctx, status, page, pageSize)
}

func (s *OTAService) GetTask(ctx context.Context, id string) (*model.OtaTask, error) {
	return s.repo.GetTask(ctx, id)
}

// DeleteTask 删除任务
func (s *OTAService) DeleteTask(ctx context.Context, id string) error {
	return s.repo.DeleteTask(ctx, id)
}

func (s *OTAService) ListTaskDevices(ctx context.Context, taskID string) ([]model.OtaTaskDevice, error) {
	return s.repo.ListTaskDevices(ctx, taskID)
}

// GetDeviceBySN 获取设备信息
func (s *OTAService) GetDeviceBySN(ctx context.Context, sn string) (*repository.DeviceInfo, error) {
	return s.repo.GetDeviceBySN(ctx, sn)
}

// GetLatestFirmware 获取指定型号的最新固件
func (s *OTAService) GetLatestFirmware(ctx context.Context, model string, targetChip string) (*model.Firmware, error) {
	return s.repo.GetLatestFirmware(ctx, model, targetChip)
}

// TriggerSingleDeviceOTA 触发单个设备的OTA升级
func (s *OTAService) TriggerSingleDeviceOTA(ctx context.Context, sn string, firmwareID int64) (*model.OtaTask, error) {
	fw, err := s.repo.GetFirmware(ctx, firmwareID)
	if err != nil || fw == nil {
		return nil, fmt.Errorf("固件不存在")
	}

	// 检查是否有可复用的已有任务（failed/pending 状态）
	existing, _ := s.repo.FindExistingTask(ctx, sn, firmwareID)
	if existing != nil {
		// 复用已有任务：重置状态
		existing.Status = "pending"
		existing.FailCount = 0
		existing.SuccessCount = 0
		existing.CompletedAt = nil
		_ = s.repo.UpdateTask(ctx, existing)

		// 重置设备状态
		_ = s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:     existing.ID,
			DeviceSN:   sn,
			Status:     "pending",
			NewVersion: fw.Version,
		})

		// 立即分发
		go func() {
			s.DispatchTask(context.Background(), existing.ID)
		}()

		return existing, nil
	}

	// 创建新任务
	task := &model.OtaTask{
		ID:              fmt.Sprintf("ota-single-%d-%d", firmwareID, time.Now().UnixMilli()),
		Name:            fmt.Sprintf("单设备升级-%s", sn),
		FirmwareID:      firmwareID,
		FirmwareVersion: fw.Version,
		Model:           fw.Model,
		TargetType:      "device",
		TargetValue:     sn,
		TotalCount:      1,
		Status:          "pending",
		PushStrategy:    "all_at_once",
		PushPercentage:  100,
		BatchSize:       1,
	}

	if err := s.repo.CreateTask(ctx, task); err != nil {
		return nil, err
	}

	// 添加设备到任务
	s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
		TaskID:     task.ID,
		DeviceSN:   sn,
		Status:     "pending",
		NewVersion: fw.Version,
	})

	// 立即分发
	go func() {
		s.DispatchTask(context.Background(), task.ID)
	}()

	return task, nil
}

// GetLatestTaskDevice 获取设备最新的OTA任务设备记录
func (s *OTAService) GetLatestTaskDevice(ctx context.Context, sn string) (*model.OtaTaskDevice, error) {
	return s.repo.GetLatestTaskDevice(ctx, sn)
}

// GetDeviceOTAHistory 获取设备OTA历史
func (s *OTAService) GetDeviceOTAHistory(ctx context.Context, sn string, page, pageSize int) ([]model.OtaTaskDevice, int, error) {
	return s.repo.GetDeviceOTAHistory(ctx, sn, page, pageSize)
}

func (s *OTAService) DispatchTask(ctx context.Context, taskID string) error {
	task, err := s.repo.GetTask(ctx, taskID)
	if err != nil {
		logger.Error("DispatchTask: failed to get task", zap.String("task_id", taskID), zap.Error(err))
		return err
	}

	devices, err := s.repo.ListTaskDevices(ctx, taskID)
	if err != nil {
		logger.Error("DispatchTask: failed to list devices", zap.String("task_id", taskID), zap.Error(err))
		return err
	}

	if err := s.repo.UpdateTaskStatus(ctx, taskID, "running"); err != nil {
		logger.Error("DispatchTask: failed to update task status to running", zap.String("task_id", taskID), zap.Error(err))
	}

	sem := make(chan struct{}, s.concurrency)
	var wg sync.WaitGroup

	for i := range devices {
		d := &devices[i]
		if d.Status != "pending" {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			s.sendOTAMessage(ctx, task, d)
		}()
	}

	wg.Wait()

	logger.Info("OTA task dispatched",
		zap.String("task_id", taskID),
		zap.Int("devices", len(devices)))
	return nil
}

func (s *OTAService) sendOTAMessage(ctx context.Context, task *model.OtaTask, td *model.OtaTaskDevice) {
	fw, err := s.repo.GetFirmware(ctx, task.FirmwareID)
	if err != nil || fw == nil {
		s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:       td.TaskID,
			DeviceSN:     td.DeviceSN,
			Status:       "failed",
			ErrorMessage: fmt.Sprintf("firmware not found: %v", err),
		})
		return
	}

	// 构造完整下载URL（ESP32需要完整URL才能下载固件）
	downloadURL := fw.FileURL
	if s.serverURL != "" && strings.HasPrefix(fw.FileURL, "/") {
		downloadURL = strings.TrimRight(s.serverURL, "/") + fw.FileURL
	}

	cmdBody := map[string]interface{}{
		"command":    "start",
		"target":     fw.TargetChip,
		"url":        downloadURL,
		"version":    fw.Version,
		"file_md5":   fw.FileMD5,
		"file_sha256": fw.FileSHA256,
		"file_size":  fw.FileSize,
		"task_id":    task.ID,
	}
	body, err := json.Marshal(cmdBody)
	if err != nil {
		s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:       td.TaskID,
			DeviceSN:     td.DeviceSN,
			Status:       "failed",
			ErrorMessage: fmt.Sprintf("marshal error: %v", err),
		})
		return
	}

	url := fmt.Sprintf("%s/api/v1/device/%s/command", s.deviceServer, td.DeviceSN)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:       td.TaskID,
			DeviceSN:     td.DeviceSN,
			Status:       "failed",
			ErrorMessage: fmt.Sprintf("create request error: %v", err),
		})
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if s.internalKey != "" {
		req.Header.Set("X-Internal-Key", s.internalKey)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:       td.TaskID,
			DeviceSN:     td.DeviceSN,
			Status:       "failed",
			ErrorMessage: fmt.Sprintf("dispatch error: %v", err),
		})
		logger.Error("OTA dispatch failed",
			zap.String("sn", td.DeviceSN),
			zap.String("task_id", task.ID),
			zap.Error(err))
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		respBody, _ := io.ReadAll(resp.Body)
		s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:       td.TaskID,
			DeviceSN:     td.DeviceSN,
			Status:       "failed",
			ErrorMessage: fmt.Sprintf("device server returned %d: %s", resp.StatusCode, string(respBody)),
		})
		return
	}

	_ = s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
		TaskID:      td.TaskID,
		DeviceSN:    td.DeviceSN,
		Status:      "running",
		OldVersion:  fw.Version,
		NewVersion:  fw.Version,
		Progress:    0,
	})

	logger.Info("OTA command sent to device",
		zap.String("sn", td.DeviceSN),
		zap.String("version", fw.Version))
}

// NotifyDevices 通知设备有新版本可用（不立即执行升级）
func (s *OTAService) NotifyDevices(ctx context.Context, taskID string) error {
	task, err := s.repo.GetTask(ctx, taskID)
	if err != nil {
		return err
	}

	devices, err := s.repo.ListTaskDevices(ctx, taskID)
	if err != nil {
		return err
	}

	fw, err := s.repo.GetFirmware(ctx, task.FirmwareID)
	if err != nil || fw == nil {
		return fmt.Errorf("固件不存在")
	}

	_ = s.repo.UpdateTaskStatus(ctx, taskID, "notifying")

	sem := make(chan struct{}, s.concurrency)
	var wg sync.WaitGroup

	for i := range devices {
		d := &devices[i]
		if d.Status != "pending" {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			s.sendOTANotification(ctx, task, d, fw)
		}()
	}

	wg.Wait()

	_ = s.repo.UpdateTaskStatus(ctx, taskID, "notified")

	logger.Info("OTA notification sent to devices",
		zap.String("task_id", taskID),
		zap.Int("devices", len(devices)))
	return nil
}

// sendOTANotification 发送OTA通知（不执行升级）
func (s *OTAService) sendOTANotification(ctx context.Context, task *model.OtaTask, td *model.OtaTaskDevice, fw *model.Firmware) {
	// 构造完整下载URL
	downloadURL := fw.FileURL
	if s.serverURL != "" && strings.HasPrefix(fw.FileURL, "/") {
		downloadURL = strings.TrimRight(s.serverURL, "/") + fw.FileURL
	}

	cmdBody := map[string]interface{}{
		"command":   "ota_notify",
		"target":    fw.TargetChip,
		"url":       downloadURL,
		"version":   fw.Version,
		"file_size": fw.FileSize,
		"task_id":   task.ID,
		"changelog": fw.Changelog,
		"is_force":  fw.IsForce,
	}
	body, err := json.Marshal(cmdBody)
	if err != nil {
		return
	}

	url := fmt.Sprintf("%s/api/v1/device/%s/command", s.deviceServer, td.DeviceSN)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if s.internalKey != "" {
		req.Header.Set("X-Internal-Key", s.internalKey)
	}
	resp, err := s.httpClient.Do(req)
	if err != nil {
		logger.Error("OTA notification failed",
			zap.String("sn", td.DeviceSN),
			zap.String("task_id", task.ID),
			zap.Error(err))
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusBadRequest {
		_ = s.repo.UpsertTaskDevice(ctx, &model.OtaTaskDevice{
			TaskID:      td.TaskID,
			DeviceSN:    td.DeviceSN,
			Status:      "notified",
			OldVersion:  "",
			NewVersion:  fw.Version,
			Progress:    0,
		})
		logger.Info("OTA notification sent",
			zap.String("sn", td.DeviceSN),
			zap.String("version", fw.Version))
	}
}

// GetPendingOTAForDevice 获取设备待处理的OTA任务
func (s *OTAService) GetPendingOTAForDevice(ctx context.Context, sn string) (*model.OtaTask, *model.Firmware, error) {
	return s.repo.GetPendingOTATaskForDevice(ctx, sn)
}
