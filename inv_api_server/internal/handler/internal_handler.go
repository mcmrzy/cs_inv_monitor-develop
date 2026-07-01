package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
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
	SN             string  `json:"sn"`
	Model          string  `json:"model"`
	Manufacturer   string  `json:"manufacturer"`
	FirmwareARM    string  `json:"firmware_arm"`
	FirmwareESP    string  `json:"firmware_esp"`
	Type           string  `json:"type"`
	RatedPower     int     `json:"rated_power"`
	RatedVoltage   int     `json:"rated_voltage"`
	RatedFreq      float64 `json:"rated_freq"`
	BatteryVoltage float64 `json:"battery_voltage"`
	BatteryType    string  `json:"battery_type"`
	CellCount      int     `json:"cell_count"`
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
	SN        string `json:"sn"`
	Code      int    `json:"code"`
	Level     string `json:"level"`
	Message   string `json:"message"`
	Count     int    `json:"count"`
	Timestamp int64  `json:"timestamp"`
}

type InternalHandler struct {
	db         *pgxpool.Pool
	rdb        *redis.Client
	otaService *service.OTAService
	// SSE broadcast channel: map[user_id]chan<- NotificationEvent
	sseClients map[int64]chan<- string
}

func NewInternalHandler(db *pgxpool.Pool, rdb *redis.Client, otaService *service.OTAService) *InternalHandler {
	return &InternalHandler{
		db:         db,
		rdb:        rdb,
		otaService: otaService,
		sseClients: make(map[int64]chan<- string),
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

	// 当设备上报在线(status=1)且当前状态为故障(status=2)时，检查是否还有未处理的严重告警
	// 如果没有未处理的严重告警，允许故障状态恢复为在线
	newStatus := req.Status
	if req.Status == 1 && oldStatus == 2 {
		var activeAlarmCount int
		_ = h.db.QueryRow(ctx,
			`SELECT COUNT(*) FROM alarms WHERE device_sn = $1 AND alarm_level = 3 AND status = 0`, req.SN,
		).Scan(&activeAlarmCount)
		if activeAlarmCount > 0 {
			newStatus = 2 // 仍有未处理的严重告警，保持故障状态
		}
	}

	// 离线(status=0)来自 MQTT LWT 遗嘱消息
	// 但设备数据可能仍通过 Kafka 路径正常上报（MQTT连接抖动不影响数据流）
	// 通过 Redis device:heartbeat:{sn} key 检查实际数据活动：如果 key 仍存在，忽略 LWT 离线
	if req.Status == 0 && h.rdb != nil {
		if h.rdb.Exists(ctx, "device:heartbeat:"+req.SN).Val() > 0 {
			logger.Info("Ignoring LWT offline - device heartbeat key still exists",
				zap.String("sn", req.SN))
			response.Success(c, gin.H{"status": "ok", "ignored": true, "reason": "data_active"})
			return
		}
	}

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
		title := "设备上线"
		content := "设备 " + req.SN + " 已上线"
		if newStatus == 0 {
			notifyType = "device_offline"
			title = "设备离线"
			content = "设备 " + req.SN + " 已离线"
		} else if newStatus == 2 {
			notifyType = "device_fault"
			title = "设备故障"
			content = "设备 " + req.SN + " 发生故障"
		} else if newStatus == 1 && oldStatus == 2 {
			// 从故障状态恢复到在线状态 → 生成告警清除通知
			notifyType = "alarm_cleared"
			title = "故障恢复"
			content = "设备 " + req.SN + " 已恢复正常"
		}

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
	}

	response.Success(c, gin.H{"status": "ok"})
}

func (h *InternalHandler) pushRealtimeData(ctx context.Context, sn string, data map[string]interface{}) {
	if h.rdb == nil {
		return
	}

	data["_sn"] = sn
	data["_updated_at"] = time.Now().Format(time.RFC3339)

	payload, err := json.Marshal(data)
	if err != nil {
		return
	}

	cacheKey := "realtime:latest:" + sn
	pipe := h.rdb.Pipeline()
	pipe.Set(ctx, cacheKey, payload, 120*time.Second)
	for k, v := range data {
		if k == "_sn" || k == "_updated_at" {
			continue
		}
		fieldBytes, _ := json.Marshal(map[string]interface{}{"v": v, "ts": time.Now().Unix()})
		pipe.Set(ctx, "realtime:latest:"+sn+":"+k, fieldBytes, 120*time.Second)
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
			sn, model, manufacturer, firmware_arm, firmware_esp, device_type,
			rated_power, rated_voltage, rated_freq, battery_voltage, battery_type, cell_count,
			user_id, status, last_online_at, created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 0, 1, NOW(), NOW(), NOW())
		ON CONFLICT (sn) DO UPDATE SET
			model = COALESCE(NULLIF(EXCLUDED.model, ''), devices.model),
			manufacturer = COALESCE(NULLIF(EXCLUDED.manufacturer, ''), devices.manufacturer),
			firmware_arm = COALESCE(NULLIF(EXCLUDED.firmware_arm, ''), devices.firmware_arm),
			firmware_esp = COALESCE(NULLIF(EXCLUDED.firmware_esp, ''), devices.firmware_esp),
			device_type = COALESCE(NULLIF(EXCLUDED.device_type, ''), devices.device_type),
			rated_power = CASE WHEN EXCLUDED.rated_power > 0 THEN EXCLUDED.rated_power ELSE devices.rated_power END,
			rated_voltage = CASE WHEN EXCLUDED.rated_voltage > 0 THEN EXCLUDED.rated_voltage ELSE devices.rated_voltage END,
			rated_freq = CASE WHEN EXCLUDED.rated_freq > 0 THEN EXCLUDED.rated_freq ELSE devices.rated_freq END,
			battery_voltage = CASE WHEN EXCLUDED.battery_voltage > 0 THEN EXCLUDED.battery_voltage ELSE devices.battery_voltage END,
			battery_type = COALESCE(NULLIF(EXCLUDED.battery_type, ''), devices.battery_type),
			cell_count = CASE WHEN EXCLUDED.cell_count > 0 THEN EXCLUDED.cell_count ELSE devices.cell_count END,
			status = CASE WHEN devices.status = 2 AND EXISTS (
				SELECT 1 FROM alarms WHERE alarms.device_sn = $1 AND alarms.alarm_level = 3 AND alarms.status = 0
			) THEN 2 ELSE 1 END,
			last_online_at = NOW(),
			updated_at = NOW()
	`, req.SN, req.Model, req.Manufacturer, req.FirmwareARM, req.FirmwareESP, req.Type,
		req.RatedPower, req.RatedVoltage, req.RatedFreq, req.BatteryVoltage, req.BatteryType, req.CellCount)
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

	response.Success(c, gin.H{"status": "ok"})
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
		telemetryTime = time.Unix(req.Timestamp, 0)
	} else {
		telemetryTime = time.Now()
	}

	_, err = h.db.Exec(ctx, `
		INSERT INTO device_telemetry (device_sn, topic, data, time, created_at)
		VALUES ($1, $2, $3::jsonb, $4, NOW())
	`, req.SN, req.Topic, string(rawJSON), telemetryTime)
	if err != nil {
		logger.Error("InternalDeviceData failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("insert telemetry failed", err))
		return
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
	if !req.Success && req.Result != "ok" && req.Result != "success" {
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

	// 更新 device_upgrades 表：标记为升级中（设备已确认收到命令）
	if req.Ack {
		tag, err := h.db.Exec(ctx, `
			UPDATE device_upgrades SET
				status = 'upgrading',
				started_at = CASE WHEN started_at IS NULL THEN NOW() ELSE started_at END,
				updated_at = NOW()
			WHERE device_sn = $1 AND status = 'pending'
		`, req.DeviceSN)
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

	// 直接更新 device_upgrades 表
	tag, err := h.db.Exec(ctx, `
		UPDATE device_upgrades SET
			status = $2::varchar,
			progress = $3,
			error_message = CASE WHEN $2::varchar = 'failed' THEN $4 ELSE error_message END,
			started_at = CASE WHEN started_at IS NULL AND $2::varchar IN ('downloading','upgrading') THEN NOW() ELSE started_at END,
			completed_at = CASE WHEN $2::varchar IN ('success', 'failed') THEN NOW() ELSE completed_at END,
			updated_at = NOW()
		WHERE device_sn = $1 AND status NOT IN ('success', 'failed', 'cancelled')
	`, req.DeviceSN, dbStatus, req.Progress, req.Message)
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 告警码到默认描述的映射
	alarmCodeMessageMap := map[int]string{
		0:  "故障恢复，系统正常",
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

	// code=0 或 level="normal" → 告警清除，恢复设备状态
	if req.Code == 0 || req.Level == "normal" {
		logger.Info("Device alarm cleared", zap.String("sn", req.SN))
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
				clearContent := "设备 " + req.SN + " 已恢复正常"
				_, _ = h.db.Exec(ctx, `
					INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
					VALUES ($1, $2, $3, $4, $5, $6, NOW())
				`, req.SN, csid, clearUserID, "alarm_cleared", "故障恢复", clearContent)
				h.broadcastNotification(clearUserID, "alarm_cleared", "故障恢复", clearContent, req.SN)
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

	// 去重：同一设备+故障码+描述在 5 秒内不重复写入
	var exists bool
	h.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM alarms WHERE device_sn=$1 AND fault_code=$2 AND fault_message=$3 AND occurred_at > NOW() - INTERVAL '5 seconds')`,
		req.SN, faultCode, faultMessage,
	).Scan(&exists)
	if exists {
		response.Success(c, gin.H{"status": "ok", "dedup": true})
		return
	}

	// 构建 fault_detail JSON
	detailJSON, _ := json.Marshal(map[string]interface{}{
		"code":      req.Code,
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
		INSERT INTO alarms (device_sn, type, level, alarm_level, station_id, user_id, fault_code, fault_message, fault_detail, message, status, occurred_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 0, NOW(), NOW())
	`, req.SN, alarmType, alarmLevel, alarmLevel, stationID, userID, faultCode, faultMessage, string(detailJSON), faultMessage)
	if err != nil {
		logger.Error("InternalDeviceAlarm insert failed", zap.String("sn", req.SN), zap.Error(err))
		response.HandleError(c, apperr.Internal("insert alarm failed", err))
		return
	}

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

	// 通过 SSE 实时推送告警信息给前端
	if userID > 0 {
		h.broadcastNotification(userID, "alarm", faultMessage, fmt.Sprintf("设备 %s: %s", req.SN, faultMessage), req.SN)
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

	// Create channel for this client
	clientChan := make(chan string, 10)
	h.sseClients[userID] = clientChan
	defer func() {
		delete(h.sseClients, userID)
		close(clientChan)
	}()

	// Send initial connection event
	c.SSEvent("connected", map[string]interface{}{
		"user_id": userID,
		"time":    time.Now().Unix(),
	})
	c.Writer.Flush()

	// Keep connection alive with periodic ping and send events
	pingTicker := time.NewTicker(15 * time.Second)
	defer pingTicker.Stop()
	for {
		select {
		case msg := <-clientChan:
			// msg 已经是完整的 SSE 格式，直接写入
			_, _ = c.Writer.WriteString(msg)
			c.Writer.Flush()
		case <-pingTicker.C:
			// SSE 心跳：发送注释行保持连接
			_, _ = c.Writer.WriteString(": ping\n\n")
			c.Writer.Flush()
		case <-c.Request.Context().Done():
			return
		}
	}
}

// broadcastNotification sends notification to all connected clients of a user
func (h *InternalHandler) broadcastNotification(userID int64, notifyType, title, content, deviceSn string) {
	if h.sseClients == nil {
		return
	}

	clientChan, exists := h.sseClients[userID]
	if !exists {
		log.Printf("[SSE] No connected client for user %d, notification not sent: %s - %s", userID, notifyType, title)
		return
	}

	log.Printf("[SSE] Broadcasting notification to user %d: %s - %s", userID, notifyType, title)

	notification := map[string]interface{}{
		"notify_type": notifyType,
		"title":       title,
		"content":     content,
		"device_sn":   deviceSn,
		"created_at":  time.Now().Format(time.RFC3339),
	}

	data, _ := json.Marshal(notification)
	// SSE 格式: event: notification\ndata: {...}\n\n
	sseMessage := fmt.Sprintf("event: notification\ndata: %s\n\n", string(data))
	select {
	case clientChan <- sseMessage:
		log.Printf("[SSE] Notification sent successfully to user %d", userID)
	default:
		// Channel full, skip
		log.Printf("Warning: SSE channel full for user %d, dropping notification", userID)
	}
}
