package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

type OTAService struct {
	repo         *repository.OTARepository
	deviceServer string
	httpClient   *http.Client
}

func NewOTAService(repo *repository.OTARepository, deviceServer string) *OTAService {
	return &OTAService{
		repo:         repo,
		deviceServer: deviceServer,
		httpClient:   &http.Client{},
	}
}

type CreateFirmwareReq struct {
	Model      string
	Version    string
	FileURL    string
	FileSize   int64
	FileMD5    string
	FileSHA256 string
	Changelog  string
	IsForce    bool
}

func (s *OTAService) CreateFirmware(ctx context.Context, req *CreateFirmwareReq) error {
	fw := &model.Firmware{
		Model:      req.Model,
		Version:    req.Version,
		FileURL:    req.FileURL,
		FileSize:   req.FileSize,
		FileMD5:    req.FileMD5,
		FileSHA256: req.FileSHA256,
		Changelog:  req.Changelog,
		IsForce:    req.IsForce,
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
		ID: fmt.Sprintf("ota-%d", req.FirmwareID),
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
			TaskID:   task.ID,
			DeviceSN: sn,
			Status:   "pending",
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

func (s *OTAService) ListTaskDevices(ctx context.Context, taskID string) ([]model.OtaTaskDevice, error) {
	return s.repo.ListTaskDevices(ctx, taskID)
}

func (s *OTAService) DispatchTask(ctx context.Context, taskID string) error {
	task, err := s.repo.GetTask(ctx, taskID)
	if err != nil {
		return err
	}

	devices, err := s.repo.ListTaskDevices(ctx, taskID)
	if err != nil {
		return err
	}

	_ = s.repo.UpdateTaskStatus(ctx, taskID, "running")

	for _, d := range devices {
		if d.Status != "pending" {
			continue
		}
		s.sendOTAMessage(task, &d)
	}

	logger.Info("OTA task dispatched",
		zap.String("task_id", taskID),
		zap.Int("devices", len(devices)))
	return nil
}

func (s *OTAService) sendOTAMessage(task *model.OtaTask, td *model.OtaTaskDevice) {
	ctx := context.Background()
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

	msg := map[string]interface{}{
		"sn":          td.DeviceSN,
		"command":     "ota_upgrade",
		"version":     fw.Version,
		"file_url":    fw.FileURL,
		"file_md5":    fw.FileMD5,
		"file_sha256": fw.FileSHA256,
		"file_size":   fw.FileSize,
		"task_id":     task.ID,
	}
	body, _ := json.Marshal(msg)

	url := fmt.Sprintf("%s/api/v1/internal/device-cmd-status", s.deviceServer)
	resp, err := s.httpClient.Post(url, "application/json", bytes.NewReader(body))
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
	resp.Body.Close()

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
