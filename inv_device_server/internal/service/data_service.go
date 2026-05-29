package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/internal/mqtt"
	"inv-device-server/internal/repository"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type DataService struct {
	repo     *repository.DeviceRepository
	metaRepo *repository.MetadataRepository
	hub      *mqtt.Hub
	rdb      *redis.Client
}

func NewDataService(repo *repository.DeviceRepository, metaRepo *repository.MetadataRepository, hub *mqtt.Hub, rdb *redis.Client) *DataService {
	return &DataService{
		repo:     repo,
		metaRepo: metaRepo,
		hub:      hub,
		rdb:      rdb,
	}
}

func (s *DataService) StartMetadataRefresh(ctx context.Context) {
	if s.metaRepo != nil {
		go s.metaRepo.StartAutoRefresh(ctx, 5*time.Minute)
	}
}

func (s *DataService) IsDeviceOnline(sn string) bool {
	return s.hub.IsDeviceOnline(sn)
}

func (s *DataService) GetMQTTStats() mqtt.MQTTStats {
	return s.hub.GetStats()
}

func (s *DataService) SendCommand(sn string, cmdType string, params map[string]interface{}, reqID string) error {
	cmd := &mqtt.DeviceCommand{
		DeviceSN: sn,
		CmdType:  cmdType,
		Params:   params,
	}
	s.hub.GetCmdChan() <- cmd
	return nil
}

func (s *DataService) GetRealtimeFromRedis(ctx context.Context, sn string) (*model.DeviceRealtime, error) {
	if s.rdb == nil {
		return nil, fmt.Errorf("redis not available")
	}
	cacheKey := "realtime:latest:" + sn
	data, err := s.rdb.Get(ctx, cacheKey).Bytes()
	if err != nil {
		return nil, err
	}
	var rt model.DeviceRealtime
	if err := json.Unmarshal(data, &rt); err != nil {
		return nil, err
	}
	return &rt, nil
}

func (s *DataService) GetRealtimeFromDB(ctx context.Context, sn string) (*model.DeviceRealtime, error) {
	return s.repo.GetLatestRealtimeData(ctx, sn)
}

func (s *DataService) SyncDeviceStatus(ctx context.Context, sn string, status int) {
	if err := s.repo.UpdateDeviceStatus(ctx, sn, status); err != nil {
		logger.Error("Failed to update device status in DB",
			zap.String("sn", sn),
			zap.Error(err))
	} else {
		logger.Info("Device status updated in DB",
			zap.String("sn", sn),
			zap.Int("status", status))
	}

	s.notifyAPIServerStatus(sn, status)
}

func (s *DataService) notifyAPIServerStatus(sn string, status int) {
	bodyData := map[string]interface{}{
		"sn":     sn,
		"status": status,
	}
	body, _ := json.Marshal(bodyData)
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
}

func (s *DataService) notifyAPIServerInfo(info *model.DeviceInfo) {
	bodyData := map[string]interface{}{
		"sn":               info.SN,
		"model":            info.Model,
		"firmware_version": info.FirmwareARM,
		"hardware_version": info.FirmwareESP,
		"rated_power":      info.RatedPower,
	}
	body, _ := json.Marshal(bodyData)
	req, _ := http.NewRequest("POST", "http://localhost:8080/api/v1/internal/device-info", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		logger.Error("Failed to call API server for device info",
			zap.String("sn", info.SN),
			zap.Error(err))
		return
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	var result map[string]interface{}
	json.Unmarshal(respBody, &result)
	if result["status"] != "ok" {
		logger.Error("API server returned error for device info",
			zap.String("sn", info.SN),
			zap.Any("response", result))
	}
}

func (s *DataService) GetOnlineDeviceSNs() []string {
	return s.hub.GetOnlineDeviceSNs()
}

func (s *DataService) IsOnlineViaRedis(ctx context.Context, sn string) bool {
	if s.rdb == nil {
		return false
	}
	tsStr, err := s.rdb.HGet(ctx, "device:online", sn).Result()
	if err != nil || tsStr == "" {
		return false
	}
	ts, err := strconv.ParseInt(tsStr, 10, 64)
	if err != nil {
		return false
	}
	return time.Now().Unix()-ts < 120
}

func (s *DataService) GetOnlineSNsFromRedis(ctx context.Context) []string {
	if s.rdb == nil {
		return nil
	}
	cutoff := time.Now().Unix() - 120
	all, err := s.rdb.HGetAll(ctx, "device:online").Result()
	if err != nil {
		return nil
	}
	var sns []string
	for sn, tsStr := range all {
		ts, err := strconv.ParseInt(tsStr, 10, 64)
		if err != nil {
			continue
		}
		if ts > cutoff {
			sns = append(sns, sn)
		}
	}
	return sns
}
