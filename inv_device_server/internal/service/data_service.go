package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/internal/mqtt"
	"inv-device-server/internal/repository"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type DataService struct {
	repo        *repository.DeviceRepository
	metaRepo    *repository.MetadataRepository
	hub         *mqtt.Hub
	rdb         *redis.Client
	apiServer   string
	internalKey string
	httpClient  *http.Client
}

func NewDataService(repo *repository.DeviceRepository, metaRepo *repository.MetadataRepository, hub *mqtt.Hub, rdb *redis.Client, apiServer string, internalKey string) *DataService {
	return &DataService{
		repo:        repo,
		metaRepo:    metaRepo,
		hub:         hub,
		rdb:         rdb,
		apiServer:   strings.TrimRight(apiServer, "/"),
		internalKey: internalKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 50,
				IdleConnTimeout:     90 * time.Second,
			},
		},
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

func (s *DataService) SendCommand(sn string, cmdType string, params map[string]interface{}, rawPayload []byte) error {
	cmd := &mqtt.DeviceCommand{
		DeviceSN:   sn,
		CmdType:    cmdType,
		Params:     params,
		RawPayload: rawPayload,
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

func (s *DataService) SyncDeviceStatus(ctx context.Context, sn string, status int) {
	s.notifyAPIServerStatus(sn, status)
}

func (s *DataService) notifyAPIServerStatus(sn string, status int) {
	if s.apiServer == "" {
		return
	}

	// 如果设备处于故障状态，不发送 status=1 覆盖故障
	if status == 1 && s.rdb != nil {
		ctx := context.Background()
		faultKey := "fault_report:" + sn
		if faultVal, err := s.rdb.Get(ctx, faultKey).Result(); err == nil && faultVal == "2" {
			return
		}
	}

	bodyData := map[string]interface{}{
		"sn":     sn,
		"status": status,
	}
	body, err := json.Marshal(bodyData)
	if err != nil {
		logger.Error("Failed to marshal status body", zap.String("sn", sn), zap.Error(err))
		return
	}
	url := s.apiServer + "/api/v1/internal/device-status"

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(1<<uint(attempt-1)*100) * time.Millisecond)
		}
		req, _ := http.NewRequest("POST", url, bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		if s.internalKey != "" {
			req.Header.Set("X-Internal-Key", s.internalKey)
		}
		resp, err := s.httpClient.Do(req)
		if err != nil {
			logger.Warn("notify device status failed, retrying",
				zap.String("sn", sn), zap.Int("attempt", attempt+1), zap.Error(err))
			continue
		}
		_, _ = io.ReadAll(resp.Body)
		resp.Body.Close()
		return
	}
	logger.Error("notify device status failed after retries", zap.String("sn", sn))
}

func (s *DataService) notifyAPIServerInfo(info *model.DeviceInfo) {
	if s.apiServer == "" {
		return
	}

	bodyData := map[string]interface{}{
		"sn":           info.SN,
		"model":        info.Model,
		"firmware_arm": info.FirmwareARM,
		"firmware_esp": info.FirmwareESP,
		"rated_power":  info.RatedPower,
	}
	body, err := json.Marshal(bodyData)
	if err != nil {
		logger.Error("Failed to marshal info body", zap.String("sn", info.SN), zap.Error(err))
		return
	}
	url := s.apiServer + "/api/v1/internal/device-info"

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(1<<uint(attempt-1)*100) * time.Millisecond)
		}
		req, _ := http.NewRequest("POST", url, bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		if s.internalKey != "" {
			req.Header.Set("X-Internal-Key", s.internalKey)
		}
		resp, err := s.httpClient.Do(req)
		if err != nil {
			logger.Warn("notify device info failed, retrying",
				zap.String("sn", info.SN), zap.Int("attempt", attempt+1), zap.Error(err))
			continue
		}
		_, _ = io.ReadAll(resp.Body)
		resp.Body.Close()
		return
	}
	logger.Error("notify device info failed after retries", zap.String("sn", info.SN))
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

func (s *DataService) HandleOTAStatus(sn string, payload []byte) {
	if s.apiServer == "" {
		return
	}

	// 解析设备上报的 OTA 状态，转换为 API Server 期望的格式
	// 设备格式: {"device_id":"...", "state":"upgrading", "progress":45, "status_message":"..."}
	// API格式:  {"device_sn":"...", "status":"upgrading", "progress":45, "message":"..."}
	var devicePayload struct {
		Ack           bool   `json:"ack"`
		TaskID        string `json:"task_id"`
		DeviceID      string `json:"device_id"`
		CurrentVersion string `json:"current_version"`
		State         string `json:"state"`
		Progress      int    `json:"progress"`
		StatusMessage string `json:"status_message"`
		ErrorMessage  string `json:"error_message"`
		Message       string `json:"message"`
		Timestamp     int64  `json:"timestamp"`
	}

	if err := json.Unmarshal(payload, &devicePayload); err != nil {
		logger.Error("Failed to parse OTA status payload", zap.String("sn", sn), zap.Error(err))
		return
	}

	// ACK 确认消息，不需要转发
	if devicePayload.Ack {
		logger.Info("OTA ACK received", zap.String("sn", sn), zap.String("task_id", devicePayload.TaskID))
		return
	}

	// 构建 API Server 期望的格式
	apiPayload := map[string]interface{}{
		"device_sn": sn,
		"status":    devicePayload.State,
		"progress":  devicePayload.Progress,
	}

	// 优先使用 status_message，其次使用 error_message
	if devicePayload.StatusMessage != "" {
		apiPayload["message"] = devicePayload.StatusMessage
	} else if devicePayload.ErrorMessage != "" {
		apiPayload["message"] = devicePayload.ErrorMessage
	} else if devicePayload.Message != "" {
		apiPayload["message"] = devicePayload.Message
	}

	// 失败时包含错误码
	if devicePayload.State == "failed" && devicePayload.ErrorMessage != "" {
		apiPayload["err_code"] = 1
	}

	transformed, err := json.Marshal(apiPayload)
	if err != nil {
		logger.Error("Failed to marshal transformed OTA status", zap.String("sn", sn), zap.Error(err))
		return
	}

	// 转发给 API Server
	url := s.apiServer + "/api/v1/internal/ota-status"

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(1<<uint(attempt-1)*100) * time.Millisecond)
		}
		req, err := http.NewRequest("POST", url, bytes.NewReader(transformed))
		if err != nil {
			logger.Error("Failed to create OTA status request", zap.String("sn", sn), zap.Error(err))
			return
		}
		req.Header.Set("Content-Type", "application/json")
		if s.internalKey != "" {
			req.Header.Set("X-Internal-Key", s.internalKey)
		}
		resp, err := s.httpClient.Do(req)
		if err != nil {
			logger.Warn("notify OTA status failed, retrying",
				zap.String("sn", sn), zap.Int("attempt", attempt+1), zap.Error(err))
			continue
		}
		_, _ = io.ReadAll(resp.Body)
		resp.Body.Close()
		logger.Info("OTA status forwarded",
			zap.String("sn", sn),
			zap.String("state", devicePayload.State),
			zap.Int("progress", devicePayload.Progress))
		return
	}
	logger.Error("notify OTA status failed after retries", zap.String("sn", sn))
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
