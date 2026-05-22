package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/internal/mqtt"
	"inv-device-server/internal/repository"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type DataService struct {
	repo  *repository.DeviceRepository
	hub   *mqtt.Hub
	rdb   *redis.Client
}

func NewDataService(repo *repository.DeviceRepository, hub *mqtt.Hub, rdb *redis.Client) *DataService {
	return &DataService{
		repo: repo,
		hub:  hub,
		rdb:  rdb,
	}
}

func (s *DataService) Start(ctx context.Context) {
	go s.processData(ctx)
	go s.processInfo(ctx)
	go s.processAlarm(ctx)
	go s.processCmdResponse(ctx)
	go s.detectOffline(ctx)
}

// ==================== 数据处理 ====================
func (s *DataService) processData(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case rt := <-s.hub.GetDataChan():
			if err := s.handleRealtime(ctx, rt); err != nil {
				logger.Error("Failed to handle realtime data",
					zap.String("sn", rt.DeviceSN),
					zap.Error(err))
			}
		}
	}
}

func (s *DataService) handleRealtime(ctx context.Context, rt *model.DeviceRealtime) error {
	if rt.DeviceSN == "" {
		return nil
	}

	rawBytes, _ := json.Marshal(rt)
	rawJSON := string(rawBytes)

	if err := s.repo.UpsertRealtime(ctx, rt); err != nil {
		logger.Error("Failed to upsert realtime data",
			zap.String("sn", rt.DeviceSN),
			zap.Error(err))
	} else {
		logger.Debug("Realtime data upserted",
			zap.String("sn", rt.DeviceSN))
	}

	if rt.Energy != nil {
		totalPower := 0.0
		if rt.AC != nil {
			totalPower = rt.AC.Power
		}

		if err := s.repo.UpsertRealtimeStructured(ctx, rt.DeviceSN, rt.Energy, totalPower); err != nil {
			logger.Error("Failed to upsert realtime structured",
				zap.String("sn", rt.DeviceSN),
				zap.Error(err))
		}

		if err := s.repo.UpsertDayData(ctx, rt.DeviceSN, rt.Energy); err != nil {
			logger.Error("Failed to upsert day data",
				zap.String("sn", rt.DeviceSN),
				zap.Error(err))
		}

		stationID, _ := s.repo.GetStationIDBySN(ctx, rt.DeviceSN)
		if stationID > 0 {
			if err := s.repo.UpsertStationDayData(ctx, stationID, rt.Energy.DailyPV, 0); err != nil {
				logger.Error("Failed to upsert station day data",
					zap.String("sn", rt.DeviceSN),
					zap.Error(err))
			}
		}
	}

	if s.rdb != nil {
		cacheKey := "realtime:latest:" + rt.DeviceSN
		if err := s.rdb.Set(ctx, cacheKey, rawJSON, 120*time.Second).Err(); err != nil {
			logger.Warn("Redis cache set failed",
				zap.String("sn", rt.DeviceSN),
				zap.Error(err))
		}
	}

	s.syncDeviceStatus(rt.DeviceSN)

	return nil
}

func (s *DataService) syncDeviceStatus(sn string) {
	rt := s.hub.GetRealtime(sn)
	newStatus := 0
	if rt != nil && rt.OnlineStatus != nil && rt.OnlineStatus.Online {
		newStatus = 1
	}

	if rt != nil && rt.SysStatus != nil && rt.SysStatus.FaultCode != 0 {
		newStatus = 2
	}

	s.notifyAPIServerStatus(sn, newStatus, rt)
}

func (s *DataService) notifyAPIServerStatus(sn string, status int, rt *model.DeviceRealtime) {
	body, _ := json.Marshal(map[string]interface{}{
		"sn":     sn,
		"status": status,
	})
	req, _ := http.NewRequest("POST", "http://localhost:8080/api/v1/internal/device-status", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		logger.Error("Failed to call API server for device status",
			zap.String("sn", sn),
			zap.Error(err))
		return
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	var result map[string]interface{}
	json.Unmarshal(respBody, &result)
	if result["status"] != "ok" {
		logger.Error("API server returned error for device status",
			zap.String("sn", sn),
			zap.Any("response", result))
	}

	logger.Info("Device status synced to API server",
		zap.String("sn", sn),
		zap.Int("status", status))
}

// ==================== 设备信息处理 ====================
func (s *DataService) processInfo(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case info := <-s.hub.GetInfoChan():
			if err := s.handleInfo(ctx, info); err != nil {
				logger.Error("Failed to handle device info",
					zap.String("sn", info.SN),
					zap.Error(err))
			}
		}
	}
}

func (s *DataService) handleInfo(ctx context.Context, info *model.DeviceInfo) error {
	if info.SN == "" {
		return nil
	}

	if err := s.repo.UpsertDeviceInfo(ctx, info); err != nil {
		return fmt.Errorf("upsert device info: %w", err)
	}

	logger.Info("Device info registered",
		zap.String("sn", info.SN),
		zap.String("model", info.Model),
		zap.String("type", info.Type))

	return nil
}

// ==================== 告警处理 ====================
func (s *DataService) processAlarm(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case alarm := <-s.hub.GetAlarmChan():
			if err := s.handleAlarm(ctx, alarm); err != nil {
				logger.Error("Failed to handle alarm",
					zap.String("sn", alarm.SN),
					zap.Error(err))
			}
		}
	}
}

func (s *DataService) handleAlarm(ctx context.Context, alarm *model.AlarmData) error {
	if alarm.SN == "" {
		return nil
	}

	if err := s.repo.InsertAlarm(ctx, alarm); err != nil {
		return fmt.Errorf("insert alarm: %w", err)
	}

	logger.Warn("Alarm recorded",
		zap.String("sn", alarm.SN),
		zap.String("source", alarm.Source),
		zap.String("desc", alarm.FaultDesc))

	return nil
}

// ==================== 命令响应处理 ====================
func (s *DataService) processCmdResponse(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case resp := <-s.hub.GetCmdRespChan():
			if err := s.handleCmdResponse(ctx, resp); err != nil {
				logger.Error("Failed to handle command response",
					zap.String("sn", resp.SN),
					zap.Error(err))
			}
		}
	}
}

func (s *DataService) handleCmdResponse(ctx context.Context, resp *model.CommandResponse) error {
	logger.Info("Command response received",
		zap.String("sn", resp.SN),
		zap.String("result", resp.Result),
		zap.String("cmd", resp.Cmd),
		zap.String("message", resp.Message))

	s.forwardCmdResponseToAPIServer(resp)

	return nil
}

func (s *DataService) forwardCmdResponseToAPIServer(resp *model.CommandResponse) {
	body, _ := json.Marshal(resp)
	req, _ := http.NewRequest("POST", "http://localhost:8080/api/v1/internal/device-cmd-status", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 5 * time.Second}
	httpResp, err := client.Do(req)
	if err != nil {
		logger.Error("Failed to forward cmd response to API server", zap.Error(err))
		return
	}
	httpResp.Body.Close()
}

// ==================== 离线检测 ====================
func (s *DataService) detectOffline(ctx context.Context) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			onlineSNs := s.hub.GetOnlineDeviceSNs()
			onlineSet := make(map[string]bool)
			for _, sn := range onlineSNs {
				onlineSet[sn] = true
			}

			allSNs := s.hub.GetAllRealtimeSNs()
			for _, sn := range allSNs {
				if !onlineSet[sn] {
					s.notifyAPIServerStatus(sn, 0, nil)
				}
			}
		}
	}
}

// ==================== 命令下发 ====================
func (s *DataService) SendCommand(sn string, cmdType string, params map[string]interface{}, reqID string) error {
	cmd := &model.DeviceCommand{
		DeviceSN: sn,
		CmdType:  cmdType,
		Params:   params,
		ReqID:    reqID,
	}

	s.hub.GetCmdChan() <- cmd
	return nil
}

func (s *DataService) IsDeviceOnline(sn string) bool {
	return s.hub.IsDeviceOnline(sn)
}

func (s *DataService) GetRealtime(sn string) *model.DeviceRealtime {
	return s.hub.GetRealtime(sn)
}

func (s *DataService) GetMQTTStats() mqtt.MQTTStats {
	return s.hub.GetStats()
}
