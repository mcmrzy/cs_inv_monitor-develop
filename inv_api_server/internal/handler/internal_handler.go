package handler

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"time"

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
	SN        string                 `json:"sn"`
	Event     string                 `json:"event"`
	Source    string                 `json:"source"`
	FaultCode int                    `json:"fault_code"`
	FaultDesc string                 `json:"fault_desc"`
	AlarmCode int                    `json:"alarm_code"`
	Trigger   map[string]interface{} `json:"trigger"`
}

type InternalHandler struct {
	db  *pgxpool.Pool
	rdb *redis.Client
}

func NewInternalHandler(db *pgxpool.Pool, rdb *redis.Client) *InternalHandler {
	return &InternalHandler{db: db, rdb: rdb}
}

func (h *InternalHandler) DeviceStatus(c *gin.Context) {
	var req internalDeviceStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}
	if req.SN == "" {
		response.BadRequest(c, "sn is required")
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
			`SELECT COUNT(*) FROM alarms WHERE device_sn = $1 AND alarm_level = 1 AND status = 0`, req.SN,
		).Scan(&activeAlarmCount)
		if activeAlarmCount > 0 {
			newStatus = 2 // 仍有未处理的严重告警，保持故障状态
		}
	}

	// 离线(status=0)来自 MQTT LWT 遗嘱消息
	// 但设备数据可能仍通过 Kafka 路径正常上报（MQTT连接抖动不影响数据流）
	// 通过 Redis device:online 检查实际数据活动：如果 Kafka 路径有近期数据，忽略 LWT 离线
	if req.Status == 0 && h.rdb != nil {
		tsStr, err := h.rdb.HGet(ctx, "device:online", req.SN).Result()
		if err == nil {
			var ts int64
			if _, parseErr := fmt.Sscanf(tsStr, "%d", &ts); parseErr == nil {
				if time.Now().Unix()-ts < 120 {
					logger.Info("Ignoring LWT offline - device has recent data via Kafka",
						zap.String("sn", req.SN), zap.Int64("redis_age_sec", time.Now().Unix()-ts))
					response.Success(c, gin.H{"status": "ok", "ignored": true, "reason": "data_active"})
					return
				}
			}
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
		response.InternalError(c, "update device status failed")
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
		response.BadRequest(c, "invalid request")
		return
	}
	if req.SN == "" {
		response.BadRequest(c, "sn is required")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err := h.db.Exec(ctx, `
		INSERT INTO devices (
			sn, model, manufacturer, firmware_arm, firmware_esp, device_type,
			rated_power, rated_voltage, rated_freq, battery_voltage, battery_type, cell_count,
			status, last_online_at, created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 1, NOW(), NOW(), NOW())
		ON CONFLICT (sn) DO UPDATE SET
			model = EXCLUDED.model,
			manufacturer = EXCLUDED.manufacturer,
			firmware_arm = EXCLUDED.firmware_arm,
			firmware_esp = EXCLUDED.firmware_esp,
			device_type = EXCLUDED.device_type,
			rated_power = EXCLUDED.rated_power,
			rated_voltage = EXCLUDED.rated_voltage,
			rated_freq = EXCLUDED.rated_freq,
			battery_voltage = EXCLUDED.battery_voltage,
			battery_type = EXCLUDED.battery_type,
			cell_count = EXCLUDED.cell_count,
			status = CASE WHEN devices.status = 2 AND EXISTS (
				SELECT 1 FROM alarms WHERE alarms.device_sn = $1 AND alarms.alarm_level = 1 AND alarms.status = 0
			) THEN 2 ELSE 1 END,
			last_online_at = NOW(),
			updated_at = NOW()
	`, req.SN, req.Model, req.Manufacturer, req.FirmwareARM, req.FirmwareESP, req.Type,
		req.RatedPower, req.RatedVoltage, req.RatedFreq, req.BatteryVoltage, req.BatteryType, req.CellCount)
	if err != nil {
		logger.Error("InternalDeviceInfo failed", zap.String("sn", req.SN), zap.Error(err))
		response.InternalError(c, "upsert device info failed")
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
		response.BadRequest(c, "invalid request")
		return
	}
	if req.SN == "" || req.Topic == "" || req.Data == nil {
		response.BadRequest(c, "sn, topic and data are required")
		return
	}

	rawJSON, err := json.Marshal(req.Data)
	if err != nil {
		response.BadRequest(c, "invalid data payload")
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
		response.InternalError(c, "insert telemetry failed")
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
			response.InternalError(c, "upsert device day data failed")
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
				response.InternalError(c, "upsert station day data failed")
				return
			}
		}
	}

	response.Success(c, gin.H{"status": "ok"})
}

func (h *InternalHandler) DeviceCmdStatus(c *gin.Context) {
	var req internalDeviceCmdStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}
	if req.SN == "" {
		response.BadRequest(c, "sn is required")
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
		response.InternalError(c, "insert command log failed")
		return
	}

	response.Success(c, gin.H{"status": "ok"})
}

type internalOTAStatusRequest struct {
	DeviceSN  string `json:"device_sn"`
	Status    string `json:"status"`
	Progress  int    `json:"progress"`
	Message   string `json:"message"`
	ErrCode   int    `json:"err_code"`
	UpdatedAt string `json:"updated_at"`
}

func (h *InternalHandler) OTAStatus(c *gin.Context) {
	var req internalOTAStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}
	if req.DeviceSN == "" {
		response.BadRequest(c, "device_sn is required")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// 将设备上报的状态映射为数据库状态
	dbStatus := req.Status
	switch req.Status {
	case "downloading", "transferring", "verifying", "upgrading":
		dbStatus = "upgrading"
	case "completed":
		dbStatus = "success"
	case "failed":
		dbStatus = "failed"
	}

	// 查找该设备最新的进行中 OTA 任务
	tag, err := h.db.Exec(ctx, `
		UPDATE ota_task_devices SET
			status = $3::varchar,
			progress = $4,
			error_message = CASE WHEN $3::varchar = 'failed' THEN $5 ELSE error_message END,
			started_at = CASE WHEN started_at IS NULL AND $3::varchar = 'upgrading' THEN NOW() ELSE started_at END,
			completed_at = CASE WHEN $3::varchar IN ('success', 'failed') THEN NOW() ELSE NULL END
		WHERE device_sn = $1
		AND status NOT IN ('success', 'failed', 'cancelled')
		AND task_id = (
			SELECT task_id FROM ota_task_devices
			WHERE device_sn = $1 AND status NOT IN ('success', 'failed', 'cancelled')
			ORDER BY id DESC LIMIT 1
		)
	`, req.DeviceSN, req.DeviceSN, dbStatus, req.Progress, req.Message)
	if err != nil {
		logger.Error("InternalOTAStatus failed", zap.String("sn", req.DeviceSN), zap.Error(err))
		response.InternalError(c, "update OTA status failed")
		return
	}

	logger.Info("OTA status updated",
		zap.String("sn", req.DeviceSN),
		zap.String("status", dbStatus),
		zap.Int("progress", req.Progress),
		zap.Int64("rows_affected", tag.RowsAffected()))

	// 当设备升级完成或失败时，检查是否所有设备都已完成，更新任务总体状态
	if dbStatus == "success" || dbStatus == "failed" {
		var taskID string
		err = h.db.QueryRow(ctx, `
			SELECT task_id FROM ota_task_devices
			WHERE device_sn = $1
			ORDER BY id DESC LIMIT 1
		`, req.DeviceSN).Scan(&taskID)
		if err == nil && taskID != "" {
			var pendingCount int
			h.db.QueryRow(ctx, `
				SELECT COUNT(*) FROM ota_task_devices
				WHERE task_id = $1 AND status NOT IN ('success', 'failed', 'cancelled')
			`, taskID).Scan(&pendingCount)

			if pendingCount == 0 {
				// 所有设备已完成，根据失败数决定任务最终状态
				var failCount int
				h.db.QueryRow(ctx, `
					SELECT COUNT(*) FROM ota_task_devices
					WHERE task_id = $1 AND status = 'failed'
				`, taskID).Scan(&failCount)

				taskStatus := "completed"
				if failCount > 0 {
					taskStatus = "failed"
				}
				h.db.Exec(ctx, `
					UPDATE ota_tasks SET status = $1, completed_at = NOW(), updated_at = NOW()
					WHERE id = $2
				`, taskStatus, taskID)
				logger.Info("OTA task finished",
					zap.String("task_id", taskID),
					zap.String("status", taskStatus))
			}
		}
	}

	response.Success(c, gin.H{"status": "ok"})
}

func (h *InternalHandler) DeviceAlarm(c *gin.Context) {
	var req internalDeviceAlarmRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}
	if req.SN == "" {
		response.BadRequest(c, "sn is required")
		return
	}

	// 空 payload 表示无告警，清除设备故障状态，直接返回成功
	if req.Trigger == nil || len(req.Trigger) == 0 {
		logger.Info("Device alarm cleared (empty payload)", zap.String("sn", req.SN))
		// 告警清除时，将设备状态恢复为在线
		h.db.Exec(c.Request.Context(), `
			UPDATE devices SET status = 1, last_online_at = NOW(), updated_at = NOW() WHERE sn = $1 AND status = 2
		`, req.SN)
		// 同步更新电站状态
		h.db.Exec(c.Request.Context(), `
			UPDATE stations SET
				status = CASE
					WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status = 1 AND devices.deleted_at IS NULL) THEN 1
					ELSE 0
				END,
				updated_at = NOW()
			WHERE deleted_at IS NULL
			AND id IN (SELECT station_id FROM devices WHERE sn = $1 AND station_id IS NOT NULL)
		`, req.SN)
		response.Success(c, gin.H{"status": "ok"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

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

	// 故障码到严重级别的映射
	faultCodeSeverityMap := map[int]int{
		1:  1, // 逆变器故障 → 严重
		2:  1, // 电池过压保护 → 严重
		3:  1, // 电池欠压保护 → 严重
		4:  1, // 电池过流保护 → 严重
		5:  1, // 逆变器过温保护 → 严重
		6:  1, // 逆变器过载保护 → 严重
		7:  2, // 绝缘阻抗异常 → 警告
		8:  2, // PV输入异常 → 警告
		9:  2, // 电芯压差过大 → 警告
		10: 3, // 系统启动完成 → 提示
		11: 3, // 进入待机模式 → 提示
		12: 1, // 交流过压保护 → 严重
		13: 1, // 交流欠压保护 → 严重
		14: 1, // 交流过频保护 → 严重
		15: 1, // 交流欠频保护 → 严重
		16: 2, // 电池温度过高 → 警告
		17: 2, // 电池温度过低 → 警告
		18: 1, // 逆变器硬件故障 → 严重
		19: 2, // 通信故障 → 警告
		20: 2, // 未知告警 → 警告
	}

	// 优先使用设备上报的 level 字段，其次使用故障码映射
	alarmLevel := 3
	if lv, ok := req.Trigger["level"]; ok {
		if lvStr, ok := lv.(string); ok {
			switch lvStr {
			case "fault":
				alarmLevel = 1
			case "warning":
				alarmLevel = 2
			case "info":
				alarmLevel = 3
			}
		}
	}
	// 如果设备没有上报 level 或者上报的是 info，使用故障码映射
	if alarmLevel == 3 {
		if mappedLevel, ok := faultCodeSeverityMap[req.FaultCode]; ok {
			alarmLevel = mappedLevel
		}
	}

	faultCode := fmt.Sprintf("%d", req.FaultCode)
	faultMessage := req.FaultDesc
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

	triggerJSON, _ := json.Marshal(req.Trigger)
	faultDetail := string(triggerJSON)

	_, err := h.db.Exec(ctx, `
		INSERT INTO alarms (device_sn, type, level, alarm_level, station_id, user_id, fault_code, fault_message, fault_detail, status, occurred_at, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 0, NOW(), NOW())
	`, req.SN, req.Event, alarmLevel, alarmLevel, stationID, userID, faultCode, faultMessage, faultDetail)
	if err != nil {
		logger.Error("InternalDeviceAlarm insert failed", zap.String("sn", req.SN), zap.Error(err))
		response.InternalError(c, "insert alarm failed")
		return
	}

	// 告警级别为严重(fault)时，更新设备状态为故障
	if alarmLevel == 1 {
		h.db.Exec(ctx, `
			UPDATE devices SET status = 2, updated_at = NOW() WHERE sn = $1 AND status != 2
		`, req.SN)
		// 同步更新电站状态
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

	logger.Info("Device alarm recorded",
		zap.String("sn", req.SN),
		zap.Int("fault_code", req.FaultCode),
		zap.String("fault_desc", req.FaultDesc),
		zap.Int("alarm_level", alarmLevel))

	response.Success(c, gin.H{"status": "ok"})
}
