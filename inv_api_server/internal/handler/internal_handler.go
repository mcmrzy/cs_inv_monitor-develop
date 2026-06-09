package handler

import (
	"context"
	"encoding/json"
	"time"

	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

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
	SN           string                 `json:"sn"`
	Topic        string                 `json:"topic"`
	Data         map[string]interface{} `json:"data"`
	DailyPV      float64                `json:"daily_pv"`
	RuntimeHours float64                `json:"runtime_hours"`
	StationID    int64                  `json:"station_id"`
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err := h.db.Exec(ctx, `
		UPDATE devices SET
			status = $2::smallint,
			last_online_at = CASE WHEN $2::smallint = 1 THEN NOW() ELSE last_online_at END,
			updated_at = NOW()
		WHERE sn = $1
	`, req.SN, req.Status)
	if err != nil {
		logger.Error("InternalDeviceStatus failed", zap.String("sn", req.SN), zap.Error(err))
		response.InternalError(c, "update device status failed")
		return
	}

	_, _ = h.db.Exec(ctx, `
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
	_, _ = pipe.Exec(ctx)

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
			status = 1,
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

	_, err = h.db.Exec(ctx, `
		INSERT INTO device_telemetry (device_sn, topic, data, time, created_at)
		VALUES ($1, $2, $3::jsonb, NOW(), NOW())
	`, req.SN, req.Topic, string(rawJSON))
	if err != nil {
		logger.Error("InternalDeviceData failed", zap.String("sn", req.SN), zap.Error(err))
		response.InternalError(c, "insert telemetry failed")
		return
	}

	if req.Topic == "data/energy" {
		runMinutes := int(req.RuntimeHours * 60)
		_, err = h.db.Exec(ctx, `
			INSERT INTO device_day_data (device_sn, data_date, energy_produce, run_minutes, created_at)
			VALUES ($1, CURRENT_DATE, $2, $3, NOW())
			ON CONFLICT (device_sn, data_date) DO UPDATE SET
				energy_produce = EXCLUDED.energy_produce,
				run_minutes = EXCLUDED.run_minutes
		`, req.SN, req.DailyPV, runMinutes)
		if err != nil {
			logger.Error("InternalDeviceData upsert day data failed", zap.String("sn", req.SN), zap.Error(err))
			response.InternalError(c, "upsert device day data failed")
			return
		}

		if req.StationID > 0 && req.DailyPV > 0 {
			_, err = h.db.Exec(ctx, `
				INSERT INTO station_day_data (station_id, data_date, energy_produce, income, device_count, online_count, fault_count, created_at)
				VALUES ($1, CURRENT_DATE, $2, 0, 0, 0, 0, NOW())
				ON CONFLICT (station_id, data_date) DO UPDATE SET
					energy_produce = (
						SELECT COALESCE(SUM(energy_produce), 0)
						FROM device_day_data
						WHERE device_sn IN (
							SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL
						) AND data_date = CURRENT_DATE
					),
					income = station_day_data.income + EXCLUDED.income
			`, req.StationID, req.DailyPV)
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

	triggerJSON, err := json.Marshal(req.Trigger)
	if err != nil {
		response.BadRequest(c, "invalid trigger payload")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	_, err = h.db.Exec(ctx, `
		INSERT INTO device_alarms (device_sn, event_type, source, fault_code, fault_desc, alarm_code, trigger_info, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW())
	`, req.SN, req.Event, req.Source, req.FaultCode, req.FaultDesc, req.AlarmCode, string(triggerJSON))
	if err != nil {
		logger.Error("InternalDeviceAlarm failed", zap.String("sn", req.SN), zap.Error(err))
		response.InternalError(c, "insert alarm failed")
		return
	}

	response.Success(c, gin.H{"status": "ok"})
}