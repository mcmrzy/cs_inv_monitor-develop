package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
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

// HandleCmdResult 处理设备上报的命令执行结果 (cs_inv/{sn}/cmd_result)
func (s *DataService) HandleCmdResult(sn string, payload []byte) {
	if s.apiServer == "" {
		return
	}

	// 直接转发原始 JSON 给 API Server，由 API Server 更新 command_logs 和插入通知
	url := s.apiServer + "/api/v1/internal/device-cmd-result"

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(1<<uint(attempt-1)*100) * time.Millisecond)
		}
		req, err := http.NewRequest("POST", url, bytes.NewReader(payload))
		if err != nil {
			logger.Error("Failed to create cmd result request", zap.String("sn", sn), zap.Error(err))
			continue
		}
		req.Header.Set("Content-Type", "application/json")
		if s.internalKey != "" {
			req.Header.Set("X-Internal-Key", s.internalKey)
		}
		// 附加 sn 到请求体（设备上报的 payload 可能不包含 sn）
		var payloadMap map[string]interface{}
		if err := json.Unmarshal(payload, &payloadMap); err == nil {
			if _, ok := payloadMap["sn"]; !ok {
				payloadMap["sn"] = sn
				if newPayload, err := json.Marshal(payloadMap); err == nil {
					req.Body = io.NopCloser(bytes.NewReader(newPayload))
					req.ContentLength = int64(len(newPayload))
				}
			}
		}

		resp, err := s.httpClient.Do(req)
		if err != nil {
			logger.Warn("notify cmd result failed, retrying",
				zap.String("sn", sn), zap.Int("attempt", attempt+1), zap.Error(err))
			continue
		}
		_, _ = io.ReadAll(resp.Body)
		resp.Body.Close()

		logger.Info("Command result forwarded",
			zap.String("sn", sn), zap.String("payload_size", fmt.Sprintf("%d", len(payload))))
		return
	}
	logger.Error("notify cmd result failed after retries", zap.String("sn", sn))
}

// FlushPendingCommands 设备上线时，检查并下发离线命令队列中的积压命令
func (s *DataService) FlushPendingCommands(ctx context.Context, sn string) {
	if s.rdb == nil {
		return
	}

	queueKey := "device:cmd:queue:" + sn
	for {
		// 从队列中取出一个命令
		result, err := s.rdb.LPop(ctx, queueKey).Result()
		if err != nil {
			// 队列为空或出错
			if err.Error() != "redis: nil" {
				logger.Warn("Failed to pop pending command", zap.String("sn", sn), zap.Error(err))
			}
			return
		}

		var cmdData struct {
			Command string                 `json:"command"`
			Params  map[string]interface{} `json:"params"`
		}
		if err := json.Unmarshal([]byte(result), &cmdData); err != nil {
			logger.Warn("Failed to unmarshal pending command", zap.String("sn", sn), zap.Error(err))
			continue
		}

		// 下发命令
		cmd := &mqtt.DeviceCommand{
			DeviceSN: sn,
			CmdType:  cmdData.Command,
			Params:   cmdData.Params,
		}
		s.hub.GetCmdChan() <- cmd

		logger.Info("Flushed pending command for online device",
			zap.String("sn", sn), zap.String("cmd", cmdData.Command))

		// 小延迟避免瞬间发送太多命令
		time.Sleep(100 * time.Millisecond)
	}
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
	// Check if the heartbeat key exists (TTL handles expiry automatically)
	return s.rdb.Exists(ctx, "device:heartbeat:"+sn).Val() > 0
}

func (s *DataService) HandleOTACmdAck(sn string, payload []byte) {
	if s.apiServer == "" {
		return
	}

	// 解析设备上报的 ACK 消息
	// 设备格式: {"ack": true, "task_id": "xxx", "message": "开始升级", "timestamp": 1782703114}
	var devicePayload struct {
		Ack       bool   `json:"ack"`
		TaskID    string `json:"task_id"`
		Message   string `json:"message"`
		Timestamp int64  `json:"timestamp"`
	}

	if err := json.Unmarshal(payload, &devicePayload); err != nil {
		logger.Error("Failed to parse OTA cmd_ack payload", zap.String("sn", sn), zap.Error(err))
		return
	}

	// 构建 API Server 期望的格式
	apiPayload := map[string]interface{}{
		"device_sn": sn,
		"ack":       devicePayload.Ack,
		"task_id":   devicePayload.TaskID,
		"message":   devicePayload.Message,
		"timestamp": devicePayload.Timestamp,
	}

	transformed, err := json.Marshal(apiPayload)
	if err != nil {
		logger.Error("Failed to marshal OTA cmd_ack", zap.String("sn", sn), zap.Error(err))
		return
	}

	// 转发给 API Server
	url := s.apiServer + "/api/v1/internal/ota-cmd-ack"

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(1<<uint(attempt-1)*100) * time.Millisecond)
		}
		req, err := http.NewRequest("POST", url, bytes.NewReader(transformed))
		if err != nil {
			logger.Error("Failed to create OTA cmd_ack request", zap.String("sn", sn), zap.Error(err))
			return
		}
		req.Header.Set("Content-Type", "application/json")
		if s.internalKey != "" {
			req.Header.Set("X-Internal-Key", s.internalKey)
		}
		resp, err := s.httpClient.Do(req)
		if err != nil {
			logger.Warn("notify OTA cmd_ack failed, retrying",
				zap.String("sn", sn), zap.Int("attempt", attempt+1), zap.Error(err))
			continue
		}
		_, _ = io.ReadAll(resp.Body)
		resp.Body.Close()
		logger.Info("OTA cmd_ack forwarded",
			zap.String("sn", sn),
			zap.Bool("ack", devicePayload.Ack),
			zap.String("task_id", devicePayload.TaskID))
		return
	}
	logger.Error("notify OTA cmd_ack failed after retries", zap.String("sn", sn))
}

func (s *DataService) HandleOTAStatus(sn string, payload []byte) {
	if s.apiServer == "" {
		return
	}

	// 调试日志：打印原始 payload
	logger.Info("Raw OTA status payload",
		zap.String("sn", sn),
		zap.String("payload", string(payload)))

	// 解析设备上报的 OTA 状态，转换为 API Server 期望的格式
	// 设备可能发送嵌套格式: {"data": {...}, "timestamp": ...}
	// 或者扁平格式: {"device_id":"...", "state":"upgrading", "progress":45, ...}
	
	// 先尝试解析嵌套格式
	var envelope struct {
		Data      json.RawMessage `json:"data"`
		Timestamp int64           `json:"timestamp"`
	}
	
	var actualPayload []byte
	if err := json.Unmarshal(payload, &envelope); err == nil && envelope.Data != nil {
		// 嵌套格式，使用 data 字段的内容
		actualPayload = envelope.Data
	} else {
		// 扁平格式，直接使用原始 payload
		actualPayload = payload
	}

	var devicePayload struct {
		Ack            bool   `json:"ack"`
		TaskID         string `json:"task_id"`
		DeviceID       string `json:"device_id"`
		FirmwareID     *int64 `json:"firmware_id"`
		CurrentVersion string `json:"current_version"`
		State          string `json:"state"`
		Progress       int    `json:"progress"`
		StatusMessage  string `json:"status_message"`
		ErrorMessage   string `json:"error_message"`
		Message        string `json:"message"`
		Timestamp      int64  `json:"timestamp"`
	}

	if err := json.Unmarshal(actualPayload, &devicePayload); err != nil {
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

	// 传递 firmware_id（如果设备上报了）
	if devicePayload.FirmwareID != nil {
		apiPayload["firmware_id"] = *devicePayload.FirmwareID
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
	var sns []string
	var cursor uint64
	for {
		keys, nextCursor, err := s.rdb.Scan(ctx, cursor, "device:heartbeat:*", 1000).Result()
		if err != nil {
			break
		}
		for _, key := range keys {
			sns = append(sns, strings.TrimPrefix(key, "device:heartbeat:"))
		}
		cursor = nextCursor
		if cursor == 0 {
			break
		}
	}
	return sns
}
