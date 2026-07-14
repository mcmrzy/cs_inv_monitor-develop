package handler

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type internalDeviceStatusRequest struct {
	SN     string `json:"sn"`
	Status int    `json:"status"`
}

type internalDeviceInfoRequest struct {
	SN              string  `json:"sn"`
	Model           string  `json:"model"`
	Manufacturer    string  `json:"manufacturer"`
	FirmwareARM     string  `json:"firmware_arm"`
	FirmwareESP     string  `json:"firmware_esp"`
	FirmwareDSP     string  `json:"firmware_dsp"`
	FirmwareBMS     string  `json:"firmware_bms"`
	Type            string  `json:"device_type"`
	RatedPower      int     `json:"rated_power"`
	RatedVoltage    int     `json:"rated_voltage"`
	RatedFreq       float64 `json:"rated_frequency"`
	BatteryVoltage  float64 `json:"battery_nominal_voltage"`
	BatteryType     string  `json:"battery_type"`
	CellCount       int     `json:"cell_count"`
	TempSensorCount int     `json:"temp_sensor_count"`
}

type internalDeviceDataRequest struct {
	SN             string                 `json:"sn"`
	Topic          string                 `json:"topic"`
	Data           map[string]interface{} `json:"data"`
	DailyPV        float64                `json:"daily_pv"`
	TotalPV        float64                `json:"total_pv"`
	DailyCharge    float64                `json:"daily_charge"`
	TotalCharge    float64                `json:"total_charge"`
	DailyDischarge float64                `json:"daily_discharge"`
	TotalDischarge float64                `json:"total_discharge"`
	DailyLoad      float64                `json:"daily_load"`
	TotalLoad      float64                `json:"total_load"`
	RuntimeHours   float64                `json:"runtime_hours"`
	StationID      int64                  `json:"station_id"`
	Timestamp      int64                  `json:"timestamp"`
}

type internalDeviceCmdStatusRequest struct {
	SN        string `json:"sn"`
	Result    string `json:"result"`
	Cmd       string `json:"cmd"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type internalDeviceAlarmRequest struct {
	SN        string          `json:"sn"`
	Code      int             `json:"code"`
	Level     string          `json:"level"`
	Source    int             `json:"source"`
	State     *int            `json:"state"`
	Message   string          `json:"message"`
	Count     int             `json:"count"`
	Timestamp int64           `json:"timestamp"`
	Trigger   json.RawMessage `json:"trigger"`
}

// NotificationService 通知服务接口，由 service 层实现。
// 在真实实现就绪前可传入 nil 以禁用通知回填和已读追踪。
type NotificationService interface {
	ListUnread(ctx context.Context, userID int64, limit int) ([]map[string]interface{}, error)
	MarkRead(ctx context.Context, userID int64, notificationID int64) error
}

// NotificationConfig SSE 推送配置
type NotificationConfig struct {
	SSEBufferSize     int // 每个客户端 channel 缓冲区大小
	MaxClientsPerUser int // 每用户最大连接数，超出时踢掉最早的
	CatchupLimit      int // 历史通知回填条数
}

func extractFloat(m map[string]interface{}, keys ...string) float64 {
	for _, k := range keys {
		if v, ok := m[k]; ok {
			switch val := v.(type) {
			case float64:
				return val
			case float32:
				return float64(val)
			case int:
				return float64(val)
			case int64:
				return float64(val)
			case json.Number:
				f, _ := val.Float64()
				return f
			}
		}
	}
	return 0
}

func extractString(m map[string]interface{}, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k]; ok {
			if s, ok := v.(string); ok {
				return s
			}
		}
	}
	return ""
}

// defaultNotificationConfig 默认配置
func defaultNotificationConfig() *NotificationConfig {
	return &NotificationConfig{
		SSEBufferSize:     32,
		MaxClientsPerUser: 10,
		CatchupLimit:      20,
	}
}

// sseHubEvent SSE Hub 内部事件
type sseHubEvent struct {
	subscribe bool
	userID    int64
	clientID  string
	ch        chan<- string
}

// sseClientEntry SSE 客户端条目
type sseClientEntry struct {
	id string
	ch chan<- string
}

// sseNotification SSE 通知载荷
type sseNotification struct {
	ID        int64                  `json:"id,omitempty"`
	Type      string                 `json:"type"`
	Title     string                 `json:"title"`
	Content   string                 `json:"content"`
	DeviceSN  string                 `json:"deviceSn,omitempty"`
	CreatedAt string                 `json:"createdAt"`
	Data      map[string]interface{} `json:"data,omitempty"`
}

type InternalHandler struct {
	db           *pgxpool.Pool
	rdb          *redis.Client
	otaService   *service.OTAService
	jpushService *service.JPushService
	// SSE multi-client broadcast: map[user_id][]sseClientEntry
	sseClientsByUser map[int64][]sseClientEntry
	sseClientsMu     sync.RWMutex
	sseHub           chan sseHubEvent
	notifySvc        NotificationService
	notifyCfg        *NotificationConfig
}

func NewInternalHandler(db *pgxpool.Pool, rdb *redis.Client, otaService *service.OTAService, jpushService *service.JPushService, notifySvc NotificationService, notifyCfg *NotificationConfig) *InternalHandler {
	if notifyCfg == nil {
		notifyCfg = defaultNotificationConfig()
	}
	h := &InternalHandler{
		db:               db,
		rdb:              rdb,
		otaService:       otaService,
		jpushService:     jpushService,
		sseClientsByUser: make(map[int64][]sseClientEntry),
		sseHub:           make(chan sseHubEvent, 256),
		notifySvc:        notifySvc,
		notifyCfg:        notifyCfg,
	}
	go h.runSSEHub()
	return h
}

// runSSEHub SSE Hub 主循环，单 goroutine 串行处理订阅/退订，避免 map 并发竞争
func (h *InternalHandler) runSSEHub() {
	for event := range h.sseHub {
		h.sseClientsMu.Lock()
		if event.subscribe {
			clients := h.sseClientsByUser[event.userID]

			// 踢掉最早的同类型客户端（防止僵尸连接堆积）
			if len(clients) >= h.notifyCfg.MaxClientsPerUser {
				evicted := clients[0]
				clients = clients[1:]
				// 向被踢掉的客户端发送断开信号（非阻塞）
				select {
				case evicted.ch <- "event: disconnect\ndata: {\"reason\":\"too_many_connections\"}\n\n":
				default:
				}
			}

			h.sseClientsByUser[event.userID] = append(clients, sseClientEntry{
				id: event.clientID,
				ch: event.ch,
			})
		} else {
			clients := h.sseClientsByUser[event.userID]
			for i, c := range clients {
				if c.id == event.clientID {
					clients[i] = clients[len(clients)-1]
					h.sseClientsByUser[event.userID] = clients[:len(clients)-1]
					break
				}
			}
			if len(h.sseClientsByUser[event.userID]) == 0 {
				delete(h.sseClientsByUser, event.userID)
			}
		}
		h.sseClientsMu.Unlock()
	}
}

// subscribeSSE 向 Hub 注册客户端（非阻塞）
func (h *InternalHandler) subscribeSSE(userID int64, clientID string, ch chan<- string) {
	select {
	case h.sseHub <- sseHubEvent{subscribe: true, userID: userID, clientID: clientID, ch: ch}:
	default:
		log.Printf("[SSE] Hub channel full, dropping subscribe for user %d", userID)
	}
}

// unsubscribeSSE 从 Hub 移除客户端（非阻塞）
func (h *InternalHandler) unsubscribeSSE(userID int64, clientID string) {
	select {
	case h.sseHub <- sseHubEvent{subscribe: false, userID: userID, clientID: clientID}:
	default:
		log.Printf("[SSE] Hub channel full, dropping unsubscribe for user %d", userID)
	}
}

func (h *InternalHandler) DeviceStatus(c *gin.Context) {
	var req internalDeviceStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" {
		response.HandleError(c, apperr.BadRequest("sn is required"))
		return
	}

	logger.Info("DeviceStatus called",
		zap.String("sn", req.SN),
		zap.Int("status", req.Status),
		zap.String("source", c.GetHeader("X-Internal-Key")),
		zap.String("ua", c.GetHeader("User-Agent")))

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 查询设备当前状态，判断是否发生状态变化
	var oldStatus int
	var userID int64
	var stationID sql.NullInt64
	_ = h.db.QueryRow(ctx,
		`SELECT COALESCE(status, 0), user_id, station_id FROM devices WHERE sn = $1`, req.SN,
	).Scan(&oldStatus, &userID, &stationID)

	// 状态转换决策已由 inv_device_server 的 DeviceStateManager 处理
	// 此处直接使用请求中的状态值
	newStatus := req.Status

	_, err := h.db.Exec(ctx, `
		UPDATE devices SET
			status = $2::smallint,
			last_online_at = CASE WHEN $2::smallint = 1 THEN NOW() ELSE last_online_at END,
			updated_at = NOW()
		WHERE sn = $1
	`, req.SN, newStatus)
	if err != nil {
		logger.Error("InternalDeviceStatus failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("update device status failed", err))
		return
	}

	_, _ = h.db.Exec(ctx, `
		UPDATE stations SET
			status = CASE
				WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status IN (1, 2) AND devices.deleted_at IS NULL) THEN 1
				ELSE 0
			END,
			updated_at = NOW()
		WHERE deleted_at IS NULL
		AND id IN (SELECT station_id FROM devices WHERE sn = $1 AND station_id IS NOT NULL)
	`, req.SN)

	// 设备状态变化时，插入通知记录（带 120 秒冷却期，防止状态抖动产生大量重复通知）
	if oldStatus != newStatus && userID > 0 {
		notifyType := "device_online"
		title := "设备重新上线"
		content := "设备 " + req.SN + " 已上线"
		if newStatus == 0 {
			notifyType = "device_offline"
			title = "设备离线"
			content = "设备 " + req.SN + " 已离线"
		} else if newStatus == 2 || (newStatus == 1 && oldStatus == 2) {
			// 故障和故障恢复通知由 DeviceAlarm 路径统一生成（通过 alarms 表 + SSE 广播）
			// 此处只更新设备状态，不插入 notifications 表，避免与 DeviceAlarm 路径重复
			notifyType = ""
		}

		// notifyType 为空时表示不生成通知（如故障恢复由 DeviceAlarm 路径统一处理）
		if notifyType != "" {
			// 冷却期检查：120 秒内同一设备同类型通知不重复写入
			var exists bool
			_ = h.db.QueryRow(ctx,
				`SELECT EXISTS(SELECT 1 FROM notifications WHERE device_sn=$1 AND notify_type=$2 AND created_at > NOW() - INTERVAL '120 seconds')`,
				req.SN, notifyType,
			).Scan(&exists)
			if exists {
				response.Success(c, gin.H{"status": "ok", "notify_dedup": true})
				return
			}

			var sid int64
			if stationID.Valid {
				sid = stationID.Int64
			}
			_, _ = h.db.Exec(ctx, `
				INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
				VALUES ($1, $2, $3, $4, $5, $6, NOW())
			`, req.SN, sid, userID, notifyType, title, content)

			// 通过 SSE 实时推送通知给前端
			h.broadcastNotification(userID, notifyType, title, content, req.SN)

			// JPush 推送通知给 APP 端
			if h.jpushService != nil {
				if userIDs, err := h.getNotificationUsers(ctx, req.SN); err == nil && len(userIDs) > 0 {
					jpushTitle := "设备上线"
					jpushContent := fmt.Sprintf("设备 %s 已上线", req.SN)
					if notifyType == "device_offline" {
						jpushTitle = "设备离线"
						jpushContent = fmt.Sprintf("设备 %s 已离线", req.SN)
					}
					h.jpushService.SendNotificationAsync(ctx, userIDs, notifyType, req.SN, jpushTitle, jpushContent)
				}
			}
		}
	}

	response.Success(c, gin.H{"status": "ok"})
}

func (h *InternalHandler) pushRealtimeData(ctx context.Context, sn string, data map[string]interface{}) {
	if h.rdb == nil {
		return
	}

	data["_sn"] = sn
	data["_updated_at"] = time.Now().UTC().Format(time.RFC3339)

	payload, err := json.Marshal(data)
	if err != nil {
		return
	}

	cacheKey := "realtime:latest:" + sn
	hashKey := "realtime:fields:" + sn
	pipe := h.rdb.Pipeline()
	pipe.Set(ctx, cacheKey, payload, 10*time.Minute)

	// Field-level cache: use HSET for O(1) retrieval via HGETALL (replaces per-field SET keys)
	fieldValues := make([]interface{}, 0, len(data)*2)
	now := time.Now().UTC().Unix()
	for k, v := range data {
		if k == "_sn" || k == "_updated_at" {
			continue
		}
		fieldBytes, _ := json.Marshal(map[string]interface{}{"v": v, "ts": now})
		fieldValues = append(fieldValues, k, string(fieldBytes))
	}
	if len(fieldValues) > 0 {
		pipe.HSet(ctx, hashKey, fieldValues...)
		pipe.Expire(ctx, hashKey, 10*time.Minute)
	}

	if _, err := pipe.Exec(ctx); err != nil {
		log.Printf("ERROR: Redis pipeline failed: %v", err)
	}

	pubChannel := "realtime:channel:" + sn
	_ = h.rdb.Publish(ctx, pubChannel, string(payload)).Err()
}

func (h *InternalHandler) DeviceInfo(c *gin.Context) {
	var req internalDeviceInfoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" {
		response.HandleError(c, apperr.BadRequest("sn is required"))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err := h.db.Exec(ctx, `
		INSERT INTO devices (
			sn, model, manufacturer, firmware_arm, firmware_esp, firmware_dsp, firmware_bms, device_type,
			rated_power, rated_voltage, rated_freq, battery_voltage, battery_type, cell_count, temp_sensor_count,
			user_id, status, last_online_at, created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, 0, 1, NOW(), NOW(), NOW())
		ON CONFLICT (sn) DO UPDATE SET
			model = COALESCE(NULLIF(EXCLUDED.model, ''), devices.model),
			manufacturer = COALESCE(NULLIF(EXCLUDED.manufacturer, ''), devices.manufacturer),
			firmware_arm = COALESCE(NULLIF(EXCLUDED.firmware_arm, ''), devices.firmware_arm),
			firmware_esp = COALESCE(NULLIF(EXCLUDED.firmware_esp, ''), devices.firmware_esp),
			firmware_dsp = COALESCE(NULLIF(EXCLUDED.firmware_dsp, ''), devices.firmware_dsp),
			firmware_bms = COALESCE(NULLIF(EXCLUDED.firmware_bms, ''), devices.firmware_bms),
			device_type = COALESCE(NULLIF(EXCLUDED.device_type, ''), devices.device_type),
			rated_power = CASE WHEN EXCLUDED.rated_power > 0 THEN EXCLUDED.rated_power ELSE devices.rated_power END,
			rated_voltage = CASE WHEN EXCLUDED.rated_voltage > 0 THEN EXCLUDED.rated_voltage ELSE devices.rated_voltage END,
			rated_freq = CASE WHEN EXCLUDED.rated_freq > 0 THEN EXCLUDED.rated_freq ELSE devices.rated_freq END,
			battery_voltage = CASE WHEN EXCLUDED.battery_voltage > 0 THEN EXCLUDED.battery_voltage ELSE devices.battery_voltage END,
			battery_type = COALESCE(NULLIF(EXCLUDED.battery_type, ''), devices.battery_type),
			cell_count = CASE WHEN EXCLUDED.cell_count > 0 THEN EXCLUDED.cell_count ELSE devices.cell_count END,
			temp_sensor_count = CASE WHEN EXCLUDED.temp_sensor_count > 0 THEN EXCLUDED.temp_sensor_count ELSE devices.temp_sensor_count END,
			status = CASE WHEN devices.status = 2 AND EXISTS (
				SELECT 1 FROM alarms WHERE alarms.device_sn = $1 AND alarms.alarm_level = 3 AND alarms.status = 0
			) THEN 2 ELSE 1 END,
			last_online_at = NOW(),
			updated_at = NOW()
	`, req.SN, req.Model, req.Manufacturer, req.FirmwareARM, req.FirmwareESP, req.FirmwareDSP, req.FirmwareBMS, req.Type,
		req.RatedPower, req.RatedVoltage, req.RatedFreq, req.BatteryVoltage, req.BatteryType, req.CellCount, req.TempSensorCount)
	if err != nil {
		logger.Error("InternalDeviceInfo failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("upsert device info failed", err))
		return
	}

	_, _ = h.db.Exec(ctx, `
		UPDATE devices SET model_id = dm.id
		FROM device_models dm
		WHERE devices.sn = $1 AND dm.model_code = $2 AND devices.model_id IS NULL
	`, req.SN, req.Model)

	// OTA 升级状态校验：设备上报新固件版本后，检查是否有进行中的升级
	h.reconcileOTAStatus(ctx, req.SN, req.FirmwareARM, req.FirmwareESP, req.FirmwareDSP, req.FirmwareBMS)

	response.Success(c, gin.H{"status": "ok"})
}

// reconcileOTAStatus 设备上线时自动校验 OTA 升级状态（best-effort，不阻塞正常响应）
func (h *InternalHandler) reconcileOTAStatus(ctx context.Context, sn string, fwARM, fwESP, fwDSP, fwBMS string) {
	// 先读取 devices 表中更新前的旧版本，用于判断版本是否发生变化
	var oldARM, oldESP, oldDSP, oldBMS string
	err := h.db.QueryRow(ctx,
		`SELECT COALESCE(firmware_arm,''), COALESCE(firmware_esp,''), COALESCE(firmware_dsp,''), COALESCE(firmware_bms,'')
		FROM devices WHERE sn = $1`, sn,
	).Scan(&oldARM, &oldESP, &oldDSP, &oldBMS)
	if err != nil {
		logger.Warn("reconcileOTAStatus: failed to query old firmware versions",
			zap.String("sn", sn), zap.Error(err))
		return
	}

	// 查询该设备所有 status='upgrading' 的升级记录
	rows, err := h.db.Query(ctx, `
		SELECT du.id, du.target_chip, COALESCE(fw.version, ''), du.started_at, COALESCE(du.upgrade_package_id, 0)
		FROM device_upgrades du
		LEFT JOIN firmware_versions fw ON du.firmware_id = fw.id
		WHERE du.device_sn = $1 AND du.status = 'upgrading'
	`, sn)
	if err != nil {
		logger.Warn("reconcileOTAStatus: query upgrading records failed",
			zap.String("sn", sn), zap.Error(err))
		return
	}
	defer rows.Close()

	type upgradeRecord struct {
		id         int64
		targetChip string
		version    string
		startedAt  time.Time
		packageID  int64
	}

	var records []upgradeRecord
	for rows.Next() {
		var r upgradeRecord
		if err := rows.Scan(&r.id, &r.targetChip, &r.version, &r.startedAt, &r.packageID); err != nil {
			continue
		}
		records = append(records, r)
	}

	if len(records) == 0 {
		return
	}

	for _, rec := range records {
		reported := chipVersion(rec.targetChip, fwARM, fwESP, fwDSP, fwBMS)
		oldVersion := chipVersion(rec.targetChip, oldARM, oldESP, oldDSP, oldBMS)

		var result string // "success", "failed", or "" (uncertain)

		if reported != "" && rec.version != "" && matchFirmwareVersion(reported, rec.version) {
			result = "success"
		} else if reported != "" && oldVersion != "" && reported != oldVersion {
			// 版本发生变化但无法精确匹配目标版本 → 大概率升级成功
			result = "success"
		} else if (reported == oldVersion || reported == "") && time.Since(rec.startedAt) > 5*time.Minute {
			// 版本未变化且已超过 5 分钟 → 升级可能失败
			result = "failed"
		}

		switch result {
		case "success":
			_, err := h.db.Exec(ctx, `
				UPDATE device_upgrades SET
					status = 'success', progress = 100, completed_at = NOW(), updated_at = NOW()
				WHERE id = $1 AND status = 'upgrading'
			`, rec.id)
			if err != nil {
				logger.Warn("reconcileOTAStatus: update to success failed",
					zap.String("sn", sn), zap.Int64("id", rec.id), zap.Error(err))
				continue
			}
			logger.Info("reconcileOTAStatus: upgrade marked as success",
				zap.String("sn", sn), zap.String("chip", rec.targetChip),
				zap.String("reported", reported), zap.String("target", rec.version))

			// 更新设备对应芯片的固件版本
			h.updateDeviceFirmwareVersion(ctx, sn, rec.targetChip, reported)

			// 升级包模式：触发下一个芯片的级联升级
			if h.otaService != nil && rec.packageID > 0 {
				go func(pkgID int64) {
					bgCtx := context.Background()
					h.otaService.OnChipUpgradeComplete(bgCtx, sn, pkgID)
				}(rec.packageID)
			}

		case "failed":
			_, err := h.db.Exec(ctx, `
				UPDATE device_upgrades SET
					status = 'failed', error_message = $2, updated_at = NOW()
				WHERE id = $1 AND status = 'upgrading'
			`, rec.id, "固件版本未更新，升级可能失败")
			if err != nil {
				logger.Warn("reconcileOTAStatus: update to failed failed",
					zap.String("sn", sn), zap.Int64("id", rec.id), zap.Error(err))
				continue
			}
			logger.Info("reconcileOTAStatus: upgrade marked as failed",
				zap.String("sn", sn), zap.String("chip", rec.targetChip),
				zap.String("reported", reported), zap.String("old", oldVersion))

		default:
			logger.Warn("reconcileOTAStatus: unable to determine upgrade status",
				zap.String("sn", sn), zap.String("chip", rec.targetChip),
				zap.String("reported", reported), zap.String("target", rec.version),
				zap.String("old", oldVersion))
		}
	}
}

// chipVersion 根据芯片类型返回对应的上报固件版本
func chipVersion(chip, arm, esp, dsp, bms string) string {
	switch chip {
	case "arm":
		return arm
	case "esp":
		return esp
	case "dsp":
		return dsp
	case "bms":
		return bms
	default:
		return ""
	}
}

// matchFirmwareVersion 检查设备上报的固件版本是否与目标版本匹配
// 支持多种格式：V1.3.0.20260701、3.1.3、V3.1.3 等
func matchFirmwareVersion(reported, target string) bool {
	if reported == target {
		return true
	}
	reportedNum := extractVersionNumbers(reported)
	targetNum := extractVersionNumbers(target)
	if reportedNum != "" && targetNum != "" {
		if reportedNum == targetNum {
			return true
		}
		// 检查上报版本号中是否包含目标版本号
		if strings.Contains(reportedNum, targetNum) {
			return true
		}
	}
	return false
}

// extractVersionNumbers 从固件版本字符串中提取数字和点号部分
// 例如 "V1.3.0.20260701" → "1.3.0.20260701"
func extractVersionNumbers(s string) string {
	var b strings.Builder
	for _, c := range s {
		if (c >= '0' && c <= '9') || c == '.' {
			b.WriteRune(c)
		}
	}
	result := strings.Trim(b.String(), ".")
	// 至少包含一个数字才算有效
	if result == "" || !strings.ContainsAny(result, "0123456789") {
		return ""
	}
	return result
}

// updateDeviceFirmwareVersion 更新设备对应芯片的固件版本
func (h *InternalHandler) updateDeviceFirmwareVersion(ctx context.Context, sn, chip, version string) {
	var col string
	switch chip {
	case "arm":
		col = "firmware_arm"
	case "esp":
		col = "firmware_esp"
	case "dsp":
		col = "firmware_dsp"
	case "bms":
		col = "firmware_bms"
	default:
		return
	}
	_, _ = h.db.Exec(ctx, fmt.Sprintf(
		"UPDATE devices SET %s = $2, updated_at = NOW() WHERE sn = $1", col,
	), sn, version)
}

func (h *InternalHandler) DeviceData(c *gin.Context) {
	var req internalDeviceDataRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" || req.Topic == "" || req.Data == nil {
		response.HandleError(c, apperr.BadRequest("sn, topic and data are required"))
		return
	}

	rawJSON, err := json.Marshal(req.Data)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid data payload"))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	var telemetryTime time.Time
	if req.Timestamp > 0 {
		telemetryTime = time.Unix(req.Timestamp, 0).UTC()
	} else {
		telemetryTime = time.Now().UTC()
	}

	// 设备服务器发送的数据是嵌套结构: {"data": {...实际字段...}, "timestamp": ...}
	// 先解包内层 data 用于字段提取
	dataMap := req.Data
	if nested, ok := req.Data["data"].(map[string]interface{}); ok {
		dataMap = nested
	}

	// 从 JSONB data 中提取常用索引字段
	var totalActivePower, dailyEnergy, internalTemp float64
	var gridFreq, battSOC, battPower, pvPower float64
	var workState, faultCode string

	switch req.Topic {
	case "data/ac":
		totalActivePower = extractFloat(dataMap, "power", "total_active_power")
		gridFreq = extractFloat(dataMap, "grid_freq", "grid_frequency", "freq")
		pvPower = extractFloat(dataMap, "pv_power")
	case "data/status":
		workState = extractString(dataMap, "state", "work_state")
		faultCode = extractString(dataMap, "fault_code")
		internalTemp = extractFloat(dataMap, "temp_inv", "internal_temperature")
		gridFreq = extractFloat(dataMap, "grid_freq", "grid_frequency", "freq")
		battSOC = extractFloat(dataMap, "battery_soc", "batt_soc")
		battPower = extractFloat(dataMap, "battery_power")
		pvPower = extractFloat(dataMap, "pv_power")
	case "data/energy":
		dailyEnergy = extractFloat(dataMap, "daily_pv", "daily_energy")
	}

	// 检查是否禁用旧表写入（双写消除阶段A）
	disableLegacyWrite := os.Getenv("DISABLE_LEGACY_TELEMETRY_WRITE") == "true"
	if !disableLegacyWrite {
		_, err = h.db.Exec(ctx, `
			INSERT INTO device_telemetry (device_sn, topic, data, total_active_power, daily_energy, work_state, fault_code, internal_temperature, grid_frequency, battery_soc, battery_power, pv_power, time, created_at)
			VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW())
		`, req.SN, req.Topic, string(rawJSON), totalActivePower, dailyEnergy, workState, faultCode, internalTemp, gridFreq, battSOC, battPower, pvPower, telemetryTime)
		if err != nil {
			logger.Error("InternalDeviceData failed", zap.String("sn", req.SN), zap.Error(err))
			response.HandleError(c, apperr.Internal("insert telemetry failed", err))
			return
		}
	} else {
		logger.Info("Legacy telemetry write disabled by env var", zap.String("sn", req.SN))
	}

	// 遥测数据入库即视为设备在线，刷新 last_online_at（30 秒节流避免高频更新）
	_, _ = h.db.Exec(ctx, `
		UPDATE devices SET last_online_at = NOW(), updated_at = NOW()
		WHERE sn = $1 AND (last_online_at IS NULL OR last_online_at < NOW() - INTERVAL '30 seconds')
	`, req.SN)

	if req.Topic == "data/energy" {
		// 根据设备时区和上报时间戳推算实际数据日期，支持离线补报历史数据
		var deviceTZ string
		err = h.db.QueryRow(ctx, `SELECT COALESCE(timezone, '') FROM devices WHERE sn = $1`, req.SN).Scan(&deviceTZ)
		if err != nil || deviceTZ == "" {
			deviceTZ = timezone.AsiaShanghai // 默认 Asia/Shanghai
		}
		dataDate := timezone.InTimezone(telemetryTime, deviceTZ).Format("2006-01-02")

		runMinutes := int(req.RuntimeHours * 60)

		dayDataJSON, _ := json.Marshal(map[string]interface{}{
			"energy_produce":  req.DailyPV,
			"daily_charge":    req.DailyCharge,
			"daily_discharge": req.DailyDischarge,
			"daily_load":      req.DailyLoad,
			"run_minutes":     runMinutes,
		})

		_, err = h.db.Exec(ctx, `
			INSERT INTO device_day_data (device_sn, data_date, data, created_at)
			VALUES ($1, $2::date, $3::jsonb, NOW())
			ON CONFLICT (device_sn, data_date) DO UPDATE SET
				data = EXCLUDED.data
		`, req.SN, dataDate, string(dayDataJSON))
		if err != nil {
			logger.Error("InternalDeviceData upsert day data failed", zap.String("sn", req.SN), zap.Error(err))
			response.HandleError(c, apperr.Internal("upsert device day data failed", err))
			return
		}

		if req.StationID > 0 && req.DailyPV > 0 {
			_, err = h.db.Exec(ctx, `
				INSERT INTO station_day_data (station_id, data_date, energy_produce, income, device_count, online_count, fault_count, created_at)
				VALUES ($1, $2::date, $3, 0, 0, 0, 0, NOW())
				ON CONFLICT (station_id, data_date) DO UPDATE SET
					energy_produce = (
						SELECT COALESCE(SUM((data->>'energy_produce')::numeric), 0)
						FROM device_day_data
						WHERE device_sn IN (
							SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL
						) AND data_date = $2::date
					),
					income = station_day_data.income + EXCLUDED.income
			`, req.StationID, dataDate, req.DailyPV)
			if err != nil {
				logger.Error("InternalDeviceData upsert station data failed", zap.Int64("station_id", req.StationID), zap.Error(err))
				response.HandleError(c, apperr.Internal("upsert station day data failed", err))
				return
			}
		}
	}

	response.Success(c, gin.H{"status": "ok"})
}

// DeviceDataBatch 批量写入遥测数据接口，使用 multi-row INSERT 提高写入效率
func (h *InternalHandler) DeviceDataBatch(c *gin.Context) {
	var requests []internalDeviceDataRequest
	if err := c.ShouldBindJSON(&requests); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}
	if len(requests) == 0 {
		response.Success(c, gin.H{"count": 0, "success": 0, "failed": 0})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 30*time.Second)
	defer cancel()

	disableLegacyWrite := os.Getenv("DISABLE_LEGACY_TELEMETRY_WRITE") == "true"

	successCount := 0
	failedCount := 0
	snSet := make(map[string]bool)
	var energyReqs []internalDeviceDataRequest

	if !disableLegacyWrite {
		// 构建 multi-row INSERT
		var (
			values       []interface{}
			placeholders []string
		)
		validIdx := 0
		for _, req := range requests {
			if req.SN == "" || req.Topic == "" || req.Data == nil {
				failedCount++
				continue
			}
			rawJSON, err := json.Marshal(req.Data)
			if err != nil {
				failedCount++
				continue
			}

			telemetryTime := time.Now().UTC()
			if req.Timestamp > 0 {
				telemetryTime = time.Unix(req.Timestamp, 0).UTC()
			}

			dataMap := req.Data
			if nested, ok := req.Data["data"].(map[string]interface{}); ok {
				dataMap = nested
			}

			var totalActivePower, dailyEnergy, internalTemp float64
			var gridFreq, battSOC, battPower, pvPower float64
			var workState, faultCode string

			switch req.Topic {
			case "data/ac":
				totalActivePower = extractFloat(dataMap, "power", "total_active_power")
				gridFreq = extractFloat(dataMap, "grid_freq", "grid_frequency", "freq")
				pvPower = extractFloat(dataMap, "pv_power")
			case "data/status":
				workState = extractString(dataMap, "state", "work_state")
				faultCode = extractString(dataMap, "fault_code")
				internalTemp = extractFloat(dataMap, "temp_inv", "internal_temperature")
				gridFreq = extractFloat(dataMap, "grid_freq", "grid_frequency", "freq")
				battSOC = extractFloat(dataMap, "battery_soc", "batt_soc")
				battPower = extractFloat(dataMap, "battery_power")
				pvPower = extractFloat(dataMap, "pv_power")
			case "data/energy":
				dailyEnergy = extractFloat(dataMap, "daily_pv", "daily_energy")
			}

			base := validIdx * 13
			placeholders = append(placeholders, fmt.Sprintf(
				"($%d, $%d, $%d::jsonb, $%d, $%d, $%d, $%d, $%d, $%d, $%d, $%d, $%d, $%d, NOW())",
				base+1, base+2, base+3, base+4, base+5, base+6, base+7, base+8, base+9, base+10, base+11, base+12, base+13,
			))
			values = append(values, req.SN, req.Topic, string(rawJSON), totalActivePower, dailyEnergy, workState, faultCode, internalTemp, gridFreq, battSOC, battPower, pvPower, telemetryTime)

			snSet[req.SN] = true
			if req.Topic == "data/energy" {
				energyReqs = append(energyReqs, req)
			}
			validIdx++
		}

		if validIdx > 0 {
			query := fmt.Sprintf(`
				INSERT INTO device_telemetry (device_sn, topic, data, total_active_power, daily_energy, work_state, fault_code, internal_temperature, grid_frequency, battery_soc, battery_power, pv_power, time, created_at)
				VALUES %s
			`, strings.Join(placeholders, ", "))

			_, err := h.db.Exec(ctx, query, values...)
			if err != nil {
				logger.Error("DeviceDataBatch insert failed", zap.Error(err))
				failedCount += validIdx
			} else {
				successCount = validIdx
			}
		}
	} else {
		logger.Info("Legacy telemetry write disabled by env var", zap.Int("batch_count", len(requests)))
		for _, req := range requests {
			if req.SN == "" || req.Topic == "" || req.Data == nil {
				failedCount++
				continue
			}
			snSet[req.SN] = true
			if req.Topic == "data/energy" {
				energyReqs = append(energyReqs, req)
			}
			successCount++
		}
	}

	// 批量更新 last_online_at（30 秒节流）
	if len(snSet) > 0 {
		sns := make([]string, 0, len(snSet))
		for sn := range snSet {
			sns = append(sns, sn)
		}
		_, _ = h.db.Exec(ctx, `
			UPDATE devices SET last_online_at = NOW(), updated_at = NOW()
			WHERE sn = ANY($1) AND (last_online_at IS NULL OR last_online_at < NOW() - INTERVAL '30 seconds')
		`, sns)
	}

	// 处理 energy 记录的 device_day_data 和 station_day_data
	for _, req := range energyReqs {
		h.handleBatchEnergyData(ctx, req)
	}

	response.Success(c, gin.H{
		"count":   len(requests),
		"success": successCount,
		"failed":  failedCount,
	})
}

// handleBatchEnergyData 处理批量接口中 energy 记录的 device_day_data 和 station_day_data 写入
func (h *InternalHandler) handleBatchEnergyData(ctx context.Context, req internalDeviceDataRequest) {
	var telemetryTime time.Time
	if req.Timestamp > 0 {
		telemetryTime = time.Unix(req.Timestamp, 0).UTC()
	} else {
		telemetryTime = time.Now().UTC()
	}

	var deviceTZ string
	err := h.db.QueryRow(ctx, `SELECT COALESCE(timezone, '') FROM devices WHERE sn = $1`, req.SN).Scan(&deviceTZ)
	if err != nil || deviceTZ == "" {
		deviceTZ = timezone.AsiaShanghai
	}
	dataDate := timezone.InTimezone(telemetryTime, deviceTZ).Format("2006-01-02")

	runMinutes := int(req.RuntimeHours * 60)
	dayDataJSON, _ := json.Marshal(map[string]interface{}{
		"energy_produce":  req.DailyPV,
		"daily_charge":    req.DailyCharge,
		"daily_discharge": req.DailyDischarge,
		"daily_load":      req.DailyLoad,
		"run_minutes":     runMinutes,
	})

	_, err = h.db.Exec(ctx, `
		INSERT INTO device_day_data (device_sn, data_date, data, created_at)
		VALUES ($1, $2::date, $3::jsonb, NOW())
		ON CONFLICT (device_sn, data_date) DO UPDATE SET
			data = EXCLUDED.data
	`, req.SN, dataDate, string(dayDataJSON))
	if err != nil {
		logger.Error("DeviceDataBatch upsert day data failed", zap.String("sn", req.SN), zap.Error(err))
		return
	}

	if req.StationID > 0 && req.DailyPV > 0 {
		_, err = h.db.Exec(ctx, `
			INSERT INTO station_day_data (station_id, data_date, energy_produce, income, device_count, online_count, fault_count, created_at)
			VALUES ($1, $2::date, $3, 0, 0, 0, 0, NOW())
			ON CONFLICT (station_id, data_date) DO UPDATE SET
				energy_produce = (
					SELECT COALESCE(SUM((data->>'energy_produce')::numeric), 0)
					FROM device_day_data
					WHERE device_sn IN (
						SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL
					) AND data_date = $2::date
				),
				income = station_day_data.income + EXCLUDED.income
		`, req.StationID, dataDate, req.DailyPV)
		if err != nil {
			logger.Error("DeviceDataBatch upsert station data failed", zap.Int64("station_id", req.StationID), zap.Error(err))
		}
	}
}

func (h *InternalHandler) DeviceCmdStatus(c *gin.Context) {
	var req internalDeviceCmdStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" {
		response.HandleError(c, apperr.BadRequest("sn is required"))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err := h.db.Exec(ctx, `
		INSERT INTO device_cmd_logs (device_sn, cmd, result, message, sent_at)
		VALUES ($1, $2, $3, $4,
			CASE WHEN $5 > 0 THEN TO_TIMESTAMP($5) ELSE NOW() END
		)
	`, req.SN, req.Cmd, req.Result, req.Message, req.Timestamp)
	if err != nil {
		logger.Error("InternalDeviceCmdStatus failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("insert command log failed", err))
		return
	}

	response.Success(c, gin.H{"status": "ok"})
}

// DeviceCmdResult 处理设备上报的命令执行结果 (cs_inv/{sn}/cmd_result)
type internalDeviceCmdResultRequest struct {
	SN        string          `json:"sn"`
	TaskID    string          `json:"task_id"`
	Cmd       string          `json:"cmd"`
	Result    string          `json:"result"`
	Success   bool            `json:"success"`
	Stage     string          `json:"stage"`
	Code      string          `json:"code"`
	Message   string          `json:"message"`
	Data      json.RawMessage `json:"data"`
	Timestamp int64           `json:"timestamp"`
}

func (h *InternalHandler) DeviceCmdResult(c *gin.Context) {
	var req internalDeviceCmdResultRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" {
		response.HandleError(c, apperr.BadRequest("sn is required"))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 确定状态
	status := "success"
	switch req.Stage {
	case "acknowledged":
		status = "acknowledged"
	case "executing":
		status = "executing"
	}
	if req.Stage != "acknowledged" && req.Stage != "executing" && !req.Success && req.Result != "ok" && req.Result != "success" {
		status = "failed"
	}

	// 更新命令日志（通过 task_id 匹配）
	if req.TaskID != "" {
		_, err := h.db.Exec(ctx, `
			UPDATE device_cmd_logs
			SET status = $2, result = $3, message = $4, data = $5::jsonb
			WHERE task_id = $1
		`, req.TaskID, status, req.Result, req.Message, req.Data)
		if err != nil {
			logger.Error("DeviceCmdResult update failed",
				zap.String("sn", req.SN), zap.String("task_id", req.TaskID), zap.Error(err))
		}
		_, err = h.db.Exec(ctx, `
			UPDATE device_commands SET status=$2,result_code=COALESCE(NULLIF($3,''),result_code),
				result_message=$4,response_data=COALESCE($5::jsonb,'[]'::jsonb),
				acknowledged_at=CASE WHEN $2='acknowledged' THEN NOW() ELSE acknowledged_at END,
				completed_at=CASE WHEN $2 IN ('success','failed') THEN NOW() ELSE completed_at END
			WHERE task_id::text=$1
		`, req.TaskID, status, req.Code, req.Message, req.Data)
		if err != nil {
			logger.Error("Device command lifecycle update failed", zap.String("task_id", req.TaskID), zap.Error(err))
		}
	} else {
		// 兼容旧格式：没有 task_id，插入新记录
		_, _ = h.db.Exec(ctx, `
			INSERT INTO device_cmd_logs (device_sn, cmd, result, message, status, sent_at)
			VALUES ($1, $2, $3, $4, $5,
				CASE WHEN $6 > 0 THEN TO_TIMESTAMP($6) ELSE NOW() END
			)
		`, req.SN, req.Cmd, req.Result, req.Message, status, req.Timestamp)
	}

	// 插入命令结果通知
	userID, stationID := h.getDeviceOwner(ctx, req.SN)
	if userID > 0 {
		notifyTitle := "控制指令执行成功"
		notifyContent := fmt.Sprintf("设备 %s 执行「%s」指令成功", req.SN, req.Cmd)
		if status == "failed" {
			notifyTitle = "控制指令执行失败"
			notifyContent = fmt.Sprintf("设备 %s 执行「%s」指令失败: %s", req.SN, req.Cmd, req.Message)
		}
		_ = h.insertNotification(ctx, req.SN, stationID, userID, "cmd_result", notifyTitle, notifyContent)
	}

	response.Success(c, gin.H{"status": "ok"})
}

// getDeviceOwner 查询设备所属用户和电站
func (h *InternalHandler) getDeviceOwner(ctx context.Context, sn string) (int64, int64) {
	var userID, stationID int64
	_ = h.db.QueryRow(ctx,
		`SELECT COALESCE(user_id, 0), COALESCE(station_id, 0) FROM devices WHERE sn = $1 AND deleted_at IS NULL`,
		sn,
	).Scan(&userID, &stationID)
	return userID, stationID
}

// insertNotification 插入通知（带冷却期）
func (h *InternalHandler) insertNotification(ctx context.Context, sn string, stationID, userID int64, notifyType, title, content string) error {
	var exists bool
	_ = h.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM notifications WHERE device_sn=$1 AND notify_type=$2 AND created_at > NOW() - INTERVAL '60 seconds')`,
		sn, notifyType,
	).Scan(&exists)
	if exists {
		return nil
	}
	_, err := h.db.Exec(ctx, `
		INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`, sn, stationID, userID, notifyType, title, content)
	return err
}

type internalOTAStatusRequest struct {
	DeviceSN   string `json:"device_sn"`
	TaskID     string `json:"task_id"`     // device_upgrades.id echoed by the device
	FirmwareID *int64 `json:"firmware_id"` // 可选，设备上报时可能携带
	Status     string `json:"status"`
	Progress   int    `json:"progress"`
	Message    string `json:"message"`
	ErrCode    int    `json:"err_code"`
}

// OTACmdAck 处理设备上报的 OTA 命令确认 (cs_inv/{sn}/ota/cmd_ack)
type internalOTACmdAckRequest struct {
	DeviceSN  string `json:"device_sn"`
	Ack       bool   `json:"ack"`
	TaskID    string `json:"task_id"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

func (h *InternalHandler) OTACmdAck(c *gin.Context) {
	var req internalOTACmdAckRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.DeviceSN == "" {
		response.HandleError(c, apperr.BadRequest("device_sn is required"))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 记录 ACK 日志
	logger.Info("OTA cmd_ack received",
		zap.String("sn", req.DeviceSN),
		zap.Bool("ack", req.Ack),
		zap.String("task_id", req.TaskID),
		zap.String("message", req.Message))

	// 更新唯一一条 device_upgrades 记录。旧设备没有 task_id 时只更新最近
	// 一条 pending 记录，绝不能把同一设备的多个芯片任务全部推进。
	if req.Ack {
		upgradeID, _ := strconv.ParseInt(req.TaskID, 10, 64)
		tag, err := h.db.Exec(ctx, `
			UPDATE device_upgrades SET
				status = 'upgrading',
				started_at = CASE WHEN started_at IS NULL THEN NOW() ELSE started_at END,
				updated_at = NOW()
			WHERE id = COALESCE(
				(SELECT id FROM device_upgrades
				 WHERE id = NULLIF($2, 0) AND device_sn = $1 AND status = 'pending'),
				(SELECT id FROM device_upgrades
				 WHERE device_sn = $1 AND status = 'pending'
				 ORDER BY updated_at DESC, id DESC LIMIT 1)
			)
		`, req.DeviceSN, upgradeID)
		if err != nil {
			logger.Error("OTACmdAck update failed", zap.String("sn", req.DeviceSN), zap.Error(err))
			response.HandleError(c, apperr.Internal("update OTA cmd ack failed", err))
			return
		}
		logger.Info("OTA cmd_ack applied", zap.String("sn", req.DeviceSN), zap.Int64("rows_affected", tag.RowsAffected()))
	}

	response.Success(c, gin.H{"status": "ok"})
}

func (h *InternalHandler) OTAStatus(c *gin.Context) {
	var req internalOTAStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.DeviceSN == "" {
		response.HandleError(c, apperr.BadRequest("device_sn is required"))
		return
	}
	if req.Progress < 0 || req.Progress > 100 {
		response.HandleError(c, apperr.BadRequest("progress must be between 0 and 100"))
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 将设备上报的状态映射为数据库状态
	dbStatus := req.Status
	switch req.Status {
	case "preparing", "downloading", "transferring", "writing", "verifying", "upgrading":
		dbStatus = "upgrading"
	case "done", "completed":
		dbStatus = "success"
	case "failed":
		dbStatus = "failed"
	default:
		// 无法识别的状态，不更新数据库，避免覆盖 pending 等有效状态
		logger.Warn("Unknown OTA status from device, skipping update",
			zap.String("sn", req.DeviceSN), zap.String("status", req.Status))
		response.Success(c, gin.H{"status": "ignored"})
		return
	}

	// 精确更新设备回传的升级记录。兼容旧固件：task_id 缺失时先按
	// firmware_id 定位，再退化到最近一条活跃记录，但始终只更新一条。
	upgradeID, _ := strconv.ParseInt(req.TaskID, 10, 64)
	tag, err := h.db.Exec(ctx, `
		UPDATE device_upgrades SET
			status = $2::varchar,
			progress = $3,
			error_message = CASE WHEN $2::varchar = 'failed' THEN $4 ELSE error_message END,
			started_at = CASE WHEN started_at IS NULL AND $2::varchar IN ('downloading','upgrading') THEN NOW() ELSE started_at END,
			completed_at = CASE WHEN $2::varchar IN ('success', 'failed') THEN NOW() ELSE completed_at END,
			updated_at = NOW()
		WHERE id = COALESCE(
			(SELECT id FROM device_upgrades
			 WHERE id = NULLIF($5, 0) AND device_sn = $1
			   AND status NOT IN ('success', 'failed', 'cancelled')),
			(SELECT id FROM device_upgrades
			 WHERE firmware_id = $6 AND device_sn = $1
			   AND status NOT IN ('success', 'failed', 'cancelled')
			 ORDER BY updated_at DESC, id DESC LIMIT 1),
			(SELECT id FROM device_upgrades
			 WHERE device_sn = $1 AND status NOT IN ('success', 'failed', 'cancelled')
			 ORDER BY updated_at DESC, id DESC LIMIT 1)
		)
	`, req.DeviceSN, dbStatus, req.Progress, req.Message, upgradeID, req.FirmwareID)
	if err != nil {
		logger.Error("InternalOTAStatus failed", zap.String("sn", req.DeviceSN), zap.Error(err))
		response.HandleError(c, apperr.Internal("update OTA status failed", err))
		return
	}

	logger.Info("OTA status updated",
		zap.String("sn", req.DeviceSN),
		zap.String("status", dbStatus),
		zap.Int("progress", req.Progress),
		zap.Int64("rows_affected", tag.RowsAffected()))

	// 更新关联升级任务的统计（best-effort，不阻塞主流程）
	if tag.RowsAffected() > 0 && (dbStatus == "success" || dbStatus == "failed" || dbStatus == "upgrading") {
		go func() {
			bgCtx := context.Background()

			// ── 超时检测：将卡住超过 15 分钟的 upgrading 记录标记为 failed ──
			timeoutRows, err := h.db.Query(bgCtx, `
				SELECT id, COALESCE(task_id, 0), started_at
				FROM device_upgrades
				WHERE device_sn = $1 AND status = 'upgrading' AND started_at IS NOT NULL
			`, req.DeviceSN)
			if err == nil {
				var timedOutTaskIDs []int64
				for timeoutRows.Next() {
					var id, taskID int64
					var startedAt time.Time
					if err := timeoutRows.Scan(&id, &taskID, &startedAt); err != nil {
						continue
					}
					if time.Since(startedAt) > 15*time.Minute {
						h.db.Exec(bgCtx, `
							UPDATE device_upgrades SET status = 'failed', error_message = '升级超时，设备可能已断连', updated_at = NOW()
							WHERE id = $1`, id)
						logger.Info("OTA upgrade timed out",
							zap.String("sn", req.DeviceSN),
							zap.Int64("upgrade_id", id),
							zap.Time("started_at", startedAt))
						if taskID > 0 {
							timedOutTaskIDs = append(timedOutTaskIDs, taskID)
						}
					}
				}
				timeoutRows.Close()

				// 更新因超时受影响的关联任务统计
				seen := map[int64]bool{}
				for _, tid := range timedOutTaskIDs {
					if seen[tid] {
						continue
					}
					seen[tid] = true
					h.db.Exec(bgCtx, `
						UPDATE upgrade_tasks SET
							success_count = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'success'),
							failed_count  = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'failed'),
							updated_at = NOW()
						WHERE id = $1`, tid)

					var totalDevices, successCount, failedCount int
					if err := h.db.QueryRow(bgCtx, `
						SELECT total_devices, success_count, failed_count FROM upgrade_tasks WHERE id = $1
					`, tid).Scan(&totalDevices, &successCount, &failedCount); err == nil && totalDevices > 0 {
						if successCount+failedCount >= totalDevices {
							var newStatus string
							if successCount == totalDevices {
								newStatus = "completed"
							} else if failedCount == totalDevices {
								newStatus = "failed"
							} else {
								newStatus = "partial_success"
							}
							h.db.Exec(bgCtx, `
								UPDATE upgrade_tasks SET status = $2, completed_at = NOW(), updated_at = NOW()
								WHERE id = $1`, tid, newStatus)
							logger.Info("Upgrade task auto-completed after timeout",
								zap.Int64("task_id", tid), zap.String("status", newStatus))
						}
					}
				}
			} else {
				timeoutRows.Close()
			}

			var taskID int64
			err = h.db.QueryRow(bgCtx, `
				SELECT COALESCE(task_id, 0)
				FROM device_upgrades
				WHERE device_sn = $1
				ORDER BY updated_at DESC LIMIT 1
			`, req.DeviceSN).Scan(&taskID)
			if err != nil || taskID <= 0 {
				return
			}

			// 自动将 pending/scheduled/draft 任务转为 running
			var taskStatus string
			if err := h.db.QueryRow(bgCtx, `SELECT status FROM upgrade_tasks WHERE id = $1`, taskID).Scan(&taskStatus); err != nil {
				return
			}
			if taskStatus == "pending" || taskStatus == "scheduled" || taskStatus == "draft" {
				h.db.Exec(bgCtx, `
					UPDATE upgrade_tasks SET status = 'running', executed_at = NOW(), updated_at = NOW()
					WHERE id = $1`, taskID)
				taskStatus = "running"
			}

			// 设备升级完成时，更新任务统计计数
			if dbStatus == "success" || dbStatus == "failed" {
				h.db.Exec(bgCtx, `
					UPDATE upgrade_tasks SET
						success_count = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'success'),
						failed_count  = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'failed'),
						updated_at = NOW()
					WHERE id = $1`, taskID)

				// 检查是否所有设备都已完成
				var totalDevices, successCount, failedCount int
				if err := h.db.QueryRow(bgCtx, `
					SELECT total_devices, success_count, failed_count FROM upgrade_tasks WHERE id = $1
				`, taskID).Scan(&totalDevices, &successCount, &failedCount); err == nil && totalDevices > 0 {
					if successCount+failedCount >= totalDevices {
						var newStatus string
						if successCount == totalDevices {
							newStatus = "completed"
						} else if failedCount == totalDevices {
							newStatus = "failed"
						} else {
							newStatus = "partial_success"
						}
						h.db.Exec(bgCtx, `
							UPDATE upgrade_tasks SET status = $2, completed_at = NOW(), updated_at = NOW()
							WHERE id = $1`, taskID, newStatus)
						logger.Info("Upgrade task status auto-updated",
							zap.Int64("task_id", taskID), zap.String("status", newStatus))
					}
				}
			}
		}()
	}

	// 单芯片升级成功时，更新设备固件版本并触发下一个芯片
	if dbStatus == "success" && tag.RowsAffected() > 0 {
		// 查询升级记录的目标芯片和固件版本
		var targetChip, firmwareVersion string
		h.db.QueryRow(ctx, `
			SELECT COALESCE(target_chip,''), COALESCE(firmware_version,'')
			FROM device_upgrades
			WHERE device_sn = $1 AND status = 'success'
			ORDER BY updated_at DESC LIMIT 1
		`, req.DeviceSN).Scan(&targetChip, &firmwareVersion)

		if targetChip != "" && firmwareVersion != "" {
			// 更新设备对应芯片的固件版本
			var updateCol string
			switch targetChip {
			case "arm":
				updateCol = "firmware_arm"
			case "esp":
				updateCol = "firmware_esp"
			case "dsp":
				updateCol = "firmware_dsp"
			case "bms":
				updateCol = "firmware_bms"
			}
			if updateCol != "" {
				h.db.Exec(ctx, fmt.Sprintf(
					"UPDATE devices SET %s = $2, updated_at = NOW() WHERE sn = $1",
					updateCol,
				), req.DeviceSN, firmwareVersion)
				logger.Info("Device firmware version updated",
					zap.String("sn", req.DeviceSN),
					zap.String("chip", targetChip),
					zap.String("version", firmwareVersion))
			}
		}

		// 升级包模式：自动触发下一个芯片
		if h.otaService != nil {
			go func() {
				bgCtx := context.Background()
				var pkgID int64
				err := h.db.QueryRow(bgCtx, `
					SELECT COALESCE(upgrade_package_id, 0)
					FROM device_upgrades
					WHERE device_sn = $1 AND status = 'success' AND upgrade_package_id IS NOT NULL
					ORDER BY updated_at DESC LIMIT 1
				`, req.DeviceSN).Scan(&pkgID)
				if err == nil && pkgID > 0 {
					h.otaService.OnChipUpgradeComplete(bgCtx, req.DeviceSN, pkgID)
				}
			}()
		}
	}

	response.Success(c, gin.H{"status": "ok"})
}

func (h *InternalHandler) DeviceAlarm(c *gin.Context) {
	var req internalDeviceAlarmRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" {
		response.HandleError(c, apperr.BadRequest("sn is required"))
		return
	}
	if len(req.Trigger) > 0 {
		trimmed := bytes.TrimLeft(req.Trigger, " \t\r\n")
		if len(trimmed) == 0 || trimmed[0] != '{' {
			response.HandleError(c, apperr.BadRequest("invalid trigger type"))
			return
		}
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 告警码到默认描述的映射
	alarmCodeMessageMap := map[int]string{
		0:  "设备故障恢复",
		1:  "逆变器过温保护",
		2:  "电池过压保护",
		3:  "电池欠压保护",
		4:  "输出过载保护",
		5:  "直流母线过压",
		6:  "逆变器温度过高",
		7:  "电池SOC过低",
		8:  "PV输入异常",
		9:  "电芯压差过大",
		10: "系统启动完成",
		11: "进入待机模式",
		12: "恢复并网运行",
	}

	// 告警码到数据库 alarm_level 的映射
	// DB: 1=提示(info) 2=警告(warning) 3=严重(fault)
	alarmCodeLevelMap := map[int]int{
		0:  1, // normal → 提示
		1:  3, // 逆变器过温保护 → 严重
		2:  3, // 电池过压保护 → 严重
		3:  3, // 电池欠压保护 → 严重
		4:  3, // 输出过载保护 → 严重
		5:  3, // 直流母线过压 → 严重
		6:  2, // 逆变器温度过高 → 警告
		7:  2, // 电池SOC过低 → 警告
		8:  2, // PV输入异常 → 警告
		9:  2, // 电芯压差过大 → 警告
		10: 1, // 系统启动完成 → 提示
		11: 1, // 进入待机模式 → 提示
		12: 1, // 恢复并网运行 → 提示
	}

	// V1 state=0 recovers only the matching (source, code) alarm. Legacy
	// code=0/normal remains a device-wide clear during the migration window.
	isV1Recovery := req.State != nil && *req.State == 0
	if isV1Recovery || req.Code == 0 || req.Level == "normal" {
		logger.Info("Device alarm cleared", zap.String("sn", req.SN))

		// 将该设备的未处理严重告警标记为已恢复（status=2）
		if isV1Recovery {
			h.db.Exec(ctx, `UPDATE alarms SET status=2,recovered_at=NOW(),event_state='recovered'
				WHERE device_sn=$1 AND alarm_source=$2 AND fault_code=$3 AND status=0`,
				req.SN, req.Source, fmt.Sprintf("%d", req.Code))
		} else {
			h.db.Exec(ctx, `UPDATE alarms SET status=2,recovered_at=NOW(),event_state='recovered'
				WHERE device_sn=$1 AND alarm_level=3 AND status=0`, req.SN)
		}

		// 写入告警恢复事件日志 (best-effort)
		var recoverStationID sql.NullInt64
		_ = h.db.QueryRow(ctx, `SELECT station_id FROM devices WHERE sn = $1`, req.SN).Scan(&recoverStationID)
		now := time.Now().UTC()
		h.writeAlarmEvent(ctx, req.SN, recoverStationID, req.Source, fmt.Sprintf("%d", req.Code),
			0, "recovered", nil, &now, nil)

		// 延迟检查：等待3秒确认没有新的告警到达，防止告警和恢复通知同时出现
		if !isV1Recovery {
			time.Sleep(3 * time.Second)
		}

		// 检查是否还有未恢复的严重告警（包括延迟期间新到达的告警）
		var activeAlarmCount int
		_ = h.db.QueryRow(ctx,
			`SELECT COUNT(*) FROM alarms WHERE device_sn = $1 AND alarm_level = 3 AND status = 0`,
			req.SN,
		).Scan(&activeAlarmCount)
		if activeAlarmCount > 0 {
			logger.Info("Skipping alarm_cleared - device still has active alarms",
				zap.String("sn", req.SN), zap.Int("active_alarms", activeAlarmCount))
			response.Success(c, gin.H{"status": "ok", "skipped": true, "reason": "active_alarms"})
			return
		}

		// 确认没有未处理的严重告警后，才更新设备状态为在线
		h.db.Exec(ctx, `
			UPDATE devices SET status = 1, last_online_at = NOW(), updated_at = NOW() WHERE sn = $1 AND status = 2
		`, req.SN)
		h.db.Exec(ctx, `
			UPDATE stations SET
				status = CASE
					WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status = 1 AND devices.deleted_at IS NULL) THEN 1
					ELSE 0
				END,
				updated_at = NOW()
			WHERE deleted_at IS NULL
			AND id IN (SELECT station_id FROM devices WHERE sn = $1 AND station_id IS NOT NULL)
		`, req.SN)

		// 插入故障恢复通知（带 60 秒冷却期）
		var clearUserID int64
		var clearStationID sql.NullInt64
		if err := h.db.QueryRow(ctx,
			`SELECT user_id, station_id FROM devices WHERE sn = $1`, req.SN,
		).Scan(&clearUserID, &clearStationID); err == nil && clearUserID > 0 {
			// 冷却期检查：60 秒内同一设备同类型通知不重复写入
			var notifyExists bool
			_ = h.db.QueryRow(ctx,
				`SELECT EXISTS(SELECT 1 FROM notifications WHERE device_sn=$1 AND notify_type='alarm_cleared' AND created_at > NOW() - INTERVAL '60 seconds')`,
				req.SN,
			).Scan(&notifyExists)
			if !notifyExists {
				var csid int64
				if clearStationID.Valid {
					csid = clearStationID.Int64
				}
				var lastFaultMsg string
				_ = h.db.QueryRow(ctx,
					`SELECT fault_message FROM alarms WHERE device_sn=$1 AND status=2 ORDER BY recovered_at DESC LIMIT 1`,
					req.SN,
				).Scan(&lastFaultMsg)
				if lastFaultMsg == "" {
					lastFaultMsg = "故障"
				}
				clearContent := fmt.Sprintf("设备 %s %s 已恢复", req.SN, lastFaultMsg)
				_, _ = h.db.Exec(ctx, `
					INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
					VALUES ($1, $2, $3, $4, $5, $6, NOW())
				`, req.SN, csid, clearUserID, "alarm_cleared", "故障已恢复", clearContent)
				h.broadcastNotification(clearUserID, "alarm_cleared", "故障已恢复", clearContent, req.SN)

				// JPush 推送故障恢复通知给 APP 端
				if h.jpushService != nil {
					if userIDs, err := h.getNotificationUsers(ctx, req.SN); err == nil && len(userIDs) > 0 {
						h.jpushService.SendNotificationAsync(ctx, userIDs, "alarm_cleared", req.SN,
							"故障已恢复", fmt.Sprintf("设备 %s 故障已恢复", req.SN))
					}
				}
			}
		}

		response.Success(c, gin.H{"status": "ok"})
		return
	}

	// 查找设备所属用户和电站
	var userID int64
	var stationID sql.NullInt64
	if err := h.db.QueryRow(ctx,
		`SELECT user_id, station_id FROM devices WHERE sn = $1`, req.SN,
	).Scan(&userID, &stationID); err != nil {
		logger.Warn("DeviceAlarm device lookup failed, using user_id=0",
			zap.String("sn", req.SN), zap.Error(err))
		userID = 0
	}

	// 确定告警级别：优先使用设备上报的 level，其次使用告警码映射
	alarmLevel := 0
	switch req.Level {
	case "fault":
		alarmLevel = 3
	case "warning":
		alarmLevel = 2
	case "info":
		alarmLevel = 1
	default:
		// 设备未上报 level，使用告警码映射
		if mappedLevel, ok := alarmCodeLevelMap[req.Code]; ok {
			alarmLevel = mappedLevel
		} else {
			alarmLevel = 2 // 默认警告
		}
	}

	faultCode := fmt.Sprintf("%d", req.Code)
	faultMessage := req.Message
	if faultMessage == "" {
		if defaultMsg, ok := alarmCodeMessageMap[req.Code]; ok {
			faultMessage = defaultMsg
		} else {
			faultMessage = fmt.Sprintf("未知告警(code=%d)", req.Code)
		}
	}
	if len(faultMessage) > 200 {
		faultMessage = faultMessage[:200]
	}

	// 去重：同一设备+告警级别在 10 秒内不重复写入
	var exists bool
	h.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM alarms WHERE device_sn=$1 AND alarm_source=$2 AND fault_code=$3 AND status=0)`,
		req.SN, req.Source, fmt.Sprintf("%d", req.Code),
	).Scan(&exists)
	if exists {
		logger.Info("Alarm dedup: same device+level within 10s",
			zap.String("sn", req.SN),
			zap.Int("alarm_level", alarmLevel))
		response.Success(c, gin.H{"status": "ok", "dedup": true})
		return
	}

	// 构建 fault_detail JSON
	detailJSON, _ := json.Marshal(map[string]interface{}{
		"code":      req.Code,
		"source":    req.Source,
		"state":     req.State,
		"level":     req.Level,
		"message":   req.Message,
		"count":     req.Count,
		"timestamp": req.Timestamp,
	})

	// type 字段映射
	alarmType := "device_fault"
	if req.Code == 0 {
		alarmType = "alarm_cleared"
	}

	_, err := h.db.Exec(ctx, `
		INSERT INTO alarms (device_sn, type, level, alarm_level, alarm_source, event_state, station_id, user_id, fault_code, fault_message, fault_detail, message, status, occurred_at, created_at)
		VALUES ($1, $2, $3, $4, $5, 'active', $6, $7, $8, $9, $10, $11, 0, NOW(), NOW())
	`, req.SN, alarmType, alarmLevel, alarmLevel, req.Source, stationID, userID, faultCode, faultMessage, string(detailJSON), faultMessage)
	if err != nil {
		logger.Error("InternalDeviceAlarm insert failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("insert alarm failed", err))
		return
	}

	// 写入告警事件日志 (best-effort，失败不影响主流程)
	activeAt := time.Now().UTC()
	h.writeAlarmEvent(ctx, req.SN, stationID, req.Source, faultCode,
		alarmLevel, "active", &activeAt, nil, detailJSON)

	// 告警级别为严重(fault, alarmLevel=3)时，更新设备状态为故障
	if alarmLevel == 3 {
		h.db.Exec(ctx, `
			UPDATE devices SET status = 2, updated_at = NOW() WHERE sn = $1 AND status != 2
		`, req.SN)
		h.db.Exec(ctx, `
			UPDATE stations SET
				status = CASE
					WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status IN (1, 2) AND devices.deleted_at IS NULL) THEN 1
					ELSE 0
				END,
				updated_at = NOW()
			WHERE deleted_at IS NULL
			AND id IN (SELECT station_id FROM devices WHERE sn = $1 AND station_id IS NOT NULL)
		`, req.SN)
	}

	// 写入 notifications 表，确保所有级别告警在管理后台通知列表中可见
	if userID > 0 {
		levelPrefix := "告警"
		switch alarmLevel {
		case 3:
			levelPrefix = "严重"
		case 2:
			levelPrefix = "警告"
		case 1:
			levelPrefix = "提示"
		}
		notifyTitle := fmt.Sprintf("%s%s", levelPrefix, faultMessage)
		notifyContent := fmt.Sprintf("设备 %s: %s", req.SN, faultMessage)
		var notifyStationID int64
		if stationID.Valid {
			notifyStationID = stationID.Int64
		}
		_, _ = h.db.Exec(ctx, `
			INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, NOW())
		`, req.SN, notifyStationID, userID, "device_alarm", notifyTitle, notifyContent)
	}

	// 通过 SSE 实时推送告警信息给前端
	if userID > 0 {
		h.broadcastNotification(userID, "alarm", faultMessage, fmt.Sprintf("设备 %s: %s", req.SN, faultMessage), req.SN)
	}

	// JPush 推送告警通知给 APP 端
	if h.jpushService != nil {
		if userIDs, err := h.getNotificationUsers(ctx, req.SN); err == nil && len(userIDs) > 0 {
			h.jpushService.SendNotificationAsync(ctx, userIDs, "device_alarm", req.SN,
				"设备告警", fmt.Sprintf("设备 %s: %s", req.SN, faultMessage))
		}
	}

	logger.Info("Device alarm recorded",
		zap.String("sn", req.SN),
		zap.Int("code", req.Code),
		zap.String("level", req.Level),
		zap.String("message", req.Message),
		zap.Int("alarm_level", alarmLevel))

	response.Success(c, gin.H{"status": "ok"})
}

// NotificationStream SSE endpoint for real-time notifications
// 支持同一用户多客户端（多浏览器标签）并行推送
func (h *InternalHandler) NotificationStream(c *gin.Context) {
	userID := c.GetInt64("user_id")
	if userID == 0 {
		c.JSON(401, gin.H{"error": "unauthorized"})
		return
	}

	// Set headers for SSE
	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("X-Accel-Buffering", "no") // Disable nginx buffering

	clientID := c.GetHeader("X-Client-ID") // 客户端生成唯一标识
	if clientID == "" {
		clientID = fmt.Sprintf("auto-%d", time.Now().UnixNano())
	}

	// Create channel for this client
	clientChan := make(chan string, h.notifyCfg.SSEBufferSize)

	// 向 Hub 注册（非阻塞）
	h.subscribeSSE(userID, clientID, clientChan)
	// 连接退出时向 Hub 退订（非阻塞）
	defer func() {
		h.unsubscribeSSE(userID, clientID)
		close(clientChan)
	}()

	log.Printf("[SSE] Client connected: userID=%d, clientID=%s", userID, clientID)

	// Send initial connected event
	c.SSEvent("connected", map[string]interface{}{
		"userID":   userID,
		"clientID": clientID,
		"time":     time.Now().UTC().Unix(),
	})
	c.Writer.Flush()

	// 历史通知回填（从 NotificationService 获取未读通知）
	if h.notifySvc != nil {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
		defer cancel()
		if notifications, err := h.notifySvc.ListUnread(ctx, userID, h.notifyCfg.CatchupLimit); err == nil && len(notifications) > 0 {
			for _, n := range notifications {
				data, _ := json.Marshal(n)
				_, _ = c.Writer.WriteString(fmt.Sprintf("event: notification\ndata: %s\n\n", string(data)))
			}
			c.Writer.Flush()
			log.Printf("[SSE] Sent %d catchup notifications to user %d", len(notifications), userID)
		}
	}

	// Keep connection alive with periodic ping and send events
	pingTicker := time.NewTicker(15 * time.Second)
	defer pingTicker.Stop()
	for {
		select {
		case msg, ok := <-clientChan:
			if !ok {
				return // channel closed by hub (e.g. kicked)
			}
			_, _ = c.Writer.WriteString(msg)
			c.Writer.Flush()
		case <-pingTicker.C:
			// SSE 心跳：发送注释行保持连接
			_, _ = c.Writer.WriteString(": ping\n\n")
			c.Writer.Flush()
		case <-c.Request.Context().Done():
			log.Printf("[SSE] Client disconnected: userID=%d, clientID=%s", userID, clientID)
			return
		}
	}
}

// broadcastNotification 向指定用户的所有已连接 SSE 客户端广播通知
// 使用读锁遍历 + 非阻塞写入，单客户端 channel 满时丢弃不影响其他客户端
func (h *InternalHandler) broadcastNotification(userID int64, notifyType, title, content, deviceSn string) {
	h.sseClientsMu.RLock()
	clients := h.sseClientsByUser[userID]
	// 复制 slice 头部，避免在锁外遍历时数据竞争
	clientsCopy := make([]sseClientEntry, len(clients))
	copy(clientsCopy, clients)
	h.sseClientsMu.RUnlock()

	if len(clientsCopy) == 0 {
		log.Printf("[SSE] No connected client for user %d, notification not sent: %s - %s", userID, notifyType, title)
		return
	}

	log.Printf("[SSE] Broadcasting notification to user %d (%d clients): %s - %s", userID, len(clientsCopy), notifyType, title)

	notification := sseNotification{
		Type:      notifyType,
		Title:     title,
		Content:   content,
		DeviceSN:  deviceSn,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}

	data, _ := json.Marshal(notification)
	sseMessage := fmt.Sprintf("event: notification\ndata: %s\n\n", string(data))

	// safeSend 非阻塞写入，带 recover 防止客户端断开后 channel 被关闭导致 panic
	safeSend := func(ch chan<- string, msg string) (ok bool) {
		defer func() {
			if recover() != nil {
				ok = false
			}
		}()
		select {
		case ch <- msg:
			return true
		default:
			return false
		}
	}

	sentCount := 0
	for _, client := range clientsCopy {
		if safeSend(client.ch, sseMessage) {
			sentCount++
		} else {
			log.Printf("[SSE] Channel full or closed for user %d client %s, dropping notification", userID, client.id)
		}
	}
	log.Printf("[SSE] Notification sent to %d/%d clients for user %d", sentCount, len(clientsCopy), userID)
}

// getNotificationUsers 获取对该设备有权限的所有用户ID
func (h *InternalHandler) getNotificationUsers(ctx context.Context, deviceSN string) ([]int64, error) {
	rows, err := h.db.Query(ctx, `
		SELECT DISTINCT user_id FROM devices
		WHERE sn = $1 AND user_id > 0 AND deleted_at IS NULL`, deviceSN)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var userIDs []int64
	for rows.Next() {
		var uid int64
		if err := rows.Scan(&uid); err != nil {
			continue
		}
		userIDs = append(userIDs, uid)
	}
	return userIDs, nil
}

// =====================================================
// 并机状态 / 三相数据 / 告警事件端点
// =====================================================

// internalParallelStateRequest 并机状态上报请求
type internalParallelStateRequest struct {
	MasterSN         string          `json:"master_sn"`
	StationID        int64           `json:"station_id"`
	Mode             string          `json:"mode"`
	Count            int             `json:"count"`
	TotalRatedPower  int             `json:"total_rated_power"`
	TotalActivePower float64         `json:"total_active_power"`
	SyncState        string          `json:"sync_state"`
	Machines         json.RawMessage `json:"machines"`
	ReportedAt       time.Time       `json:"reported_at"`
}

// ParallelState 接收并机状态上报 (POST /api/v1/internal/parallel-state)
// UPSERT 到 device_parallel_state 表，检测拓扑变化并写入 device_parallel_events
func (h *InternalHandler) ParallelState(c *gin.Context) {
	var req internalParallelStateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.StationID == 0 {
		response.HandleError(c, apperr.BadRequest("station_id is required"))
		return
	}
	if req.MasterSN == "" {
		response.HandleError(c, apperr.BadRequest("master_sn is required"))
		return
	}
	if len(req.Machines) == 0 {
		req.Machines = json.RawMessage("[]")
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 查询当前状态（用于拓扑变化检测）
	var oldMasterSN, oldMode, oldSyncState string
	var oldCount, oldTotalRatedPower int
	var oldTotalActivePower float64
	var oldMachines []byte
	err := h.db.QueryRow(ctx, `
		SELECT COALESCE(master_sn,''), COALESCE(mode,''), COALESCE(count,0),
		       COALESCE(total_rated_power,0), COALESCE(total_active_power,0),
		       COALESCE(sync_state,''), COALESCE(machines,'[]')
		FROM device_parallel_state WHERE station_id = $1
	`, req.StationID).Scan(&oldMasterSN, &oldMode, &oldCount, &oldTotalRatedPower,
		&oldTotalActivePower, &oldSyncState, &oldMachines)

	// UPSERT 新状态
	_, err = h.db.Exec(ctx, `
		INSERT INTO device_parallel_state (station_id, master_sn, mode, count, total_rated_power, total_active_power, sync_state, machines, reported_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
		ON CONFLICT (station_id) DO UPDATE SET
			master_sn = EXCLUDED.master_sn,
			mode = EXCLUDED.mode,
			count = EXCLUDED.count,
			total_rated_power = EXCLUDED.total_rated_power,
			total_active_power = EXCLUDED.total_active_power,
			sync_state = EXCLUDED.sync_state,
			machines = EXCLUDED.machines,
			reported_at = EXCLUDED.reported_at,
			updated_at = NOW()
	`, req.StationID, req.MasterSN, req.Mode, req.Count, req.TotalRatedPower,
		req.TotalActivePower, req.SyncState, []byte(req.Machines), req.ReportedAt)
	if err != nil {
		logger.Error("ParallelState upsert failed", zap.Int64("station_id", req.StationID), zap.Error(err))
		response.HandleError(c, apperr.Internal("upsert parallel state failed", err))
		return
	}

	// 检测拓扑变化并写入事件日志 (best-effort)
	topologyChanged := oldMasterSN != req.MasterSN ||
		oldMode != req.Mode ||
		oldCount != req.Count ||
		oldTotalRatedPower != req.TotalRatedPower ||
		string(oldMachines) != string(req.Machines)

	if topologyChanged {
		eventType := "topology_changed"
		if oldMasterSN == "" {
			eventType = "parallel_created"
		} else if oldMasterSN != req.MasterSN {
			eventType = "master_switched"
		}

		oldStateJSON := json.RawMessage("null")
		if oldMasterSN != "" {
			oldStateJSON = oldMachines
		}

		_, _ = h.db.Exec(ctx, `
			INSERT INTO device_parallel_events (station_id, master_sn, event_type, old_state, new_state, occurred_at)
			VALUES ($1, $2, $3, $4, $5, $6)
		`, req.StationID, req.MasterSN, eventType, []byte(oldStateJSON), []byte(req.Machines), req.ReportedAt)

		logger.Info("Parallel topology changed",
			zap.Int64("station_id", req.StationID),
			zap.String("old_master", oldMasterSN),
			zap.String("new_master", req.MasterSN),
			zap.String("event_type", eventType))
	}

	response.Success(c, gin.H{"status": "ok"})
}

// internalThreePhaseDataRequest 三相数据上报请求
type internalThreePhaseDataRequest struct {
	SN               string    `json:"sn"`
	EventTime        time.Time `json:"event_time"`
	VoltageL1        float64   `json:"voltage_l1"`
	VoltageL2        float64   `json:"voltage_l2"`
	VoltageL3        float64   `json:"voltage_l3"`
	CurrentL1        float64   `json:"current_l1"`
	CurrentL2        float64   `json:"current_l2"`
	CurrentL3        float64   `json:"current_l3"`
	ActivePowerL1    float64   `json:"active_power_l1"`
	ActivePowerL2    float64   `json:"active_power_l2"`
	ActivePowerL3    float64   `json:"active_power_l3"`
	TotalActivePower float64   `json:"total_active_power"`
	LineVoltageL1L2  float64   `json:"line_voltage_l1l2"`
	LineVoltageL2L3  float64   `json:"line_voltage_l2l3"`
	LineVoltageL3L1  float64   `json:"line_voltage_l3l1"`
	Frequency        float64   `json:"frequency"`
	VoltageUnbalance float64   `json:"voltage_unbalance"`
	CurrentUnbalance float64   `json:"current_unbalance"`
	RawEnvelope      string    `json:"raw_envelope"`
}

// ThreePhaseData 接收三相数据上报 (POST /api/v1/internal/three-phase)
// 写入 device_three_phase_3min 超表，使用 ON CONFLICT DO NOTHING 防止重复
func (h *InternalHandler) ThreePhaseData(c *gin.Context) {
	var req internalThreePhaseDataRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if req.SN == "" {
		response.HandleError(c, apperr.BadRequest("sn is required"))
		return
	}
	if req.EventTime.IsZero() {
		req.EventTime = time.Now().UTC()
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	var rawEnvelope interface{}
	if req.RawEnvelope != "" {
		rawEnvelope = req.RawEnvelope
	}

	_, err := h.db.Exec(ctx, `
		INSERT INTO device_three_phase_3min (
			device_sn, event_time, voltage_l1, voltage_l2, voltage_l3,
			current_l1, current_l2, current_l3, active_power_l1, active_power_l2, active_power_l3,
			total_active_power, line_voltage_l1l2, line_voltage_l2l3, line_voltage_l3l1,
			frequency, voltage_unbalance, current_unbalance, raw_envelope
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19::jsonb)
		ON CONFLICT (device_sn, event_time, data_hash) DO NOTHING
	`, req.SN, req.EventTime,
		req.VoltageL1, req.VoltageL2, req.VoltageL3,
		req.CurrentL1, req.CurrentL2, req.CurrentL3,
		req.ActivePowerL1, req.ActivePowerL2, req.ActivePowerL3,
		req.TotalActivePower, req.LineVoltageL1L2, req.LineVoltageL2L3, req.LineVoltageL3L1,
		req.Frequency, req.VoltageUnbalance, req.CurrentUnbalance, rawEnvelope)
	if err != nil {
		logger.Error("ThreePhaseData insert failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("insert three phase data failed", err))
		return
	}

	response.Success(c, gin.H{"status": "ok"})
}

// GetParallelState 查询设备并机状态 (GET /api/v1/devices/:sn/parallel-state)
func (h *InternalHandler) GetParallelState(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.BadRequest(c, "sn is required")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 先查询设备的 station_id，再查并机状态
	var stationID int64
	err := h.db.QueryRow(ctx,
		`SELECT COALESCE(station_id, 0) FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn,
	).Scan(&stationID)
	if err != nil {
		response.NotFound(c, "device not found")
		return
	}
	if stationID == 0 {
		response.Success(c, gin.H{"has_parallel": false})
		return
	}

	var result = make(map[string]interface{})
	var masterSN, mode, syncState string
	var count, totalRatedPower int
	var totalActivePower float64
	var machines []byte
	var reportedAt time.Time

	err = h.db.QueryRow(ctx, `
		SELECT master_sn, COALESCE(mode,''), count, total_rated_power, total_active_power,
		       sync_state, machines, reported_at
		FROM device_parallel_state WHERE station_id = $1
	`, stationID).Scan(&masterSN, &mode, &count, &totalRatedPower, &totalActivePower,
		&syncState, &machines, &reportedAt)
	if err != nil {
		response.Success(c, gin.H{"has_parallel": false})
		return
	}

	var machinesData interface{}
	if err := json.Unmarshal(machines, &machinesData); err != nil {
		machinesData = []interface{}{}
	}

	result["has_parallel"] = true
	result["station_id"] = stationID
	result["master_sn"] = masterSN
	result["mode"] = mode
	result["count"] = count
	result["total_rated_power"] = totalRatedPower
	result["total_active_power"] = totalActivePower
	result["sync_state"] = syncState
	result["machines"] = machinesData
	result["reported_at"] = reportedAt

	response.Success(c, result)
}

// GetThreePhaseHistory 查询设备三相历史数据 (GET /api/v1/devices/:sn/three-phase)
func (h *InternalHandler) GetThreePhaseHistory(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.BadRequest(c, "sn is required")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 500 {
		pageSize = 50
	}
	startTime := c.Query("start_time")
	endTime := c.Query("end_time")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	var total int64
	countQuery := `SELECT COUNT(*) FROM device_three_phase_3min WHERE device_sn = $1`
	countArgs := []interface{}{sn}
	argIdx := 2
	if startTime != "" {
		countQuery += fmt.Sprintf(` AND event_time >= $%d`, argIdx)
		countArgs = append(countArgs, startTime)
		argIdx++
	}
	if endTime != "" {
		countQuery += fmt.Sprintf(` AND event_time <= $%d`, argIdx)
		countArgs = append(countArgs, endTime)
		argIdx++
	}
	_ = h.db.QueryRow(ctx, countQuery, countArgs...).Scan(&total)

	offset := (page - 1) * pageSize
	dataQuery := `
		SELECT event_time, voltage_l1, voltage_l2, voltage_l3,
		       current_l1, current_l2, current_l3,
		       active_power_l1, active_power_l2, active_power_l3,
		       total_active_power, line_voltage_l1l2, line_voltage_l2l3, line_voltage_l3l1,
		       frequency, voltage_unbalance, current_unbalance
		FROM device_three_phase_3min WHERE device_sn = $1`
	dataArgs := []interface{}{sn}
	argIdx = 2
	if startTime != "" {
		dataQuery += fmt.Sprintf(` AND event_time >= $%d`, argIdx)
		dataArgs = append(dataArgs, startTime)
		argIdx++
	}
	if endTime != "" {
		dataQuery += fmt.Sprintf(` AND event_time <= $%d`, argIdx)
		dataArgs = append(dataArgs, endTime)
		argIdx++
	}
	dataQuery += fmt.Sprintf(` ORDER BY event_time DESC LIMIT $%d OFFSET $%d`, argIdx, argIdx+1)
	dataArgs = append(dataArgs, pageSize, offset)

	rows, err := h.db.Query(ctx, dataQuery, dataArgs...)
	if err != nil {
		logger.Error("GetThreePhaseHistory query failed", zap.String("sn", sn), zap.Error(err))
		response.HandleError(c, apperr.Internal("query three phase history failed", err))
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var eventTime time.Time
		var vL1, vL2, vL3, cL1, cL2, cL3, pL1, pL2, pL3, totalP, lv12, lv23, lv31, freq, vUnb, cUnb float64
		if err := rows.Scan(&eventTime, &vL1, &vL2, &vL3, &cL1, &cL2, &cL3, &pL1, &pL2, &pL3,
			&totalP, &lv12, &lv23, &lv31, &freq, &vUnb, &cUnb); err != nil {
			continue
		}
		items = append(items, map[string]interface{}{
			"event_time":         eventTime,
			"voltage_l1":         vL1,
			"voltage_l2":         vL2,
			"voltage_l3":         vL3,
			"current_l1":         cL1,
			"current_l2":         cL2,
			"current_l3":         cL3,
			"active_power_l1":    pL1,
			"active_power_l2":    pL2,
			"active_power_l3":    pL3,
			"total_active_power": totalP,
			"line_voltage_l1l2":  lv12,
			"line_voltage_l2l3":  lv23,
			"line_voltage_l3l1":  lv31,
			"frequency":          freq,
			"voltage_unbalance":  vUnb,
			"current_unbalance":  cUnb,
		})
	}

	response.Page(c, items, total, page, pageSize)
}

// GetAlarmEvents 查询设备告警事件历史 (GET /api/v1/devices/:sn/alarm-events)
func (h *InternalHandler) GetAlarmEvents(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.BadRequest(c, "sn is required")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 500 {
		pageSize = 50
	}
	startTime := c.Query("start_time")
	endTime := c.Query("end_time")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	var total int64
	countQuery := `SELECT COUNT(*) FROM device_alarm_events WHERE device_sn = $1`
	countArgs := []interface{}{sn}
	argIdx := 2
	if startTime != "" {
		countQuery += fmt.Sprintf(` AND created_at >= $%d`, argIdx)
		countArgs = append(countArgs, startTime)
		argIdx++
	}
	if endTime != "" {
		countQuery += fmt.Sprintf(` AND created_at <= $%d`, argIdx)
		countArgs = append(countArgs, endTime)
		argIdx++
	}
	_ = h.db.QueryRow(ctx, countQuery, countArgs...).Scan(&total)

	offset := (page - 1) * pageSize
	dataQuery := `
		SELECT id, device_sn, station_id, source, code, level, state, active_at, recovered_at, raw_data, created_at
		FROM device_alarm_events WHERE device_sn = $1`
	dataArgs := []interface{}{sn}
	argIdx = 2
	if startTime != "" {
		dataQuery += fmt.Sprintf(` AND created_at >= $%d`, argIdx)
		dataArgs = append(dataArgs, startTime)
		argIdx++
	}
	if endTime != "" {
		dataQuery += fmt.Sprintf(` AND created_at <= $%d`, argIdx)
		dataArgs = append(dataArgs, endTime)
		argIdx++
	}
	dataQuery += fmt.Sprintf(` ORDER BY created_at DESC LIMIT $%d OFFSET $%d`, argIdx, argIdx+1)
	dataArgs = append(dataArgs, pageSize, offset)

	rows, err := h.db.Query(ctx, dataQuery, dataArgs...)
	if err != nil {
		logger.Error("GetAlarmEvents query failed", zap.String("sn", sn), zap.Error(err))
		response.HandleError(c, apperr.Internal("query alarm events failed", err))
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var id, stationID int64
		var source int
		var deviceSN, code, state string
		var level int16
		var activeAt, recoveredAt sql.NullTime
		var rawData []byte
		var createdAt time.Time
		if err := rows.Scan(&id, &deviceSN, &stationID, &source, &code, &level, &state,
			&activeAt, &recoveredAt, &rawData, &createdAt); err != nil {
			continue
		}
		var rawDataVal interface{}
		if len(rawData) > 0 {
			_ = json.Unmarshal(rawData, &rawDataVal)
		}
		item := map[string]interface{}{
			"id":          id,
			"device_sn":   deviceSN,
			"station_id":  stationID,
			"source":      source,
			"code":        code,
			"level":       level,
			"state":       state,
			"created_at":  createdAt,
			"raw_data":    rawDataVal,
		}
		if activeAt.Valid {
			item["active_at"] = activeAt.Time
		}
		if recoveredAt.Valid {
			item["recovered_at"] = recoveredAt.Time
		}
		items = append(items, item)
	}

	response.Page(c, items, total, page, pageSize)
}

// writeAlarmEvent 写入告警事件日志 (best-effort，失败不影响主流程)
func (h *InternalHandler) writeAlarmEvent(ctx context.Context, sn string, stationID sql.NullInt64,
	source int, code string, level int, state string, activeAt, recoveredAt *time.Time, rawData []byte) {
	var activeAtVal, recoveredAtVal interface{}
	if activeAt != nil {
		activeAtVal = *activeAt
	}
	if recoveredAt != nil {
		recoveredAtVal = *recoveredAt
	}
	var sid interface{}
	if stationID.Valid {
		sid = stationID.Int64
	}
	var rawDataVal interface{}
	if len(rawData) > 0 {
		rawDataVal = rawData
	}
	_, err := h.db.Exec(ctx, `
		INSERT INTO device_alarm_events (device_sn, station_id, source, code, level, state, active_at, recovered_at, raw_data)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
	`, sn, sid, source, code, level, state, activeAtVal, recoveredAtVal, rawDataVal)
	if err != nil {
		logger.Warn("writeAlarmEvent failed (best-effort)",
			zap.String("sn", sn), zap.String("code", code), zap.Error(err))
	}
}
