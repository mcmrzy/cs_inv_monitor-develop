package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"go.uber.org/zap"
)

type alarmEventDetailResponse struct {
	ID          int64           `json:"id"`
	DeviceSN    string          `json:"device_sn"`
	StationID   *int64          `json:"station_id,omitempty"`
	Source      int16           `json:"source"`
	Code        string          `json:"code"`
	Level       int16           `json:"level"`
	State       string          `json:"state"`
	Topic       string          `json:"topic"`
	EventTime   time.Time       `json:"event_time"`
	Timestamp   int64           `json:"t"`
	ActiveAt    *time.Time      `json:"active_at,omitempty"`
	RecoveredAt *time.Time      `json:"recovered_at,omitempty"`
	ReceivedAt  time.Time       `json:"received_at"`
	RawEnvelope json.RawMessage `json:"raw_envelope"`
	DataHash    string          `json:"data_hash"`
	CreatedAt   time.Time       `json:"created_at"`
	Snapshots   json.RawMessage `json:"snapshots"`
}

// GetAlarmEventDetail returns one immutable protocol alarm event together with
// its before/after telemetry snapshots. The event is read first so object-level
// authorization can be performed before any snapshot data is queried.
func (h *InternalHandler) GetAlarmEventDetail(c *gin.Context) {
	eventID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || eventID <= 0 {
		response.BadRequest(c, "invalid alarm event id")
		return
	}

	ctx := c.Request.Context()
	var event alarmEventDetailResponse
	var stationID sql.NullInt64
	var activeAt, recoveredAt sql.NullTime
	var rawEnvelope []byte

	err = h.db.QueryRow(ctx, `
		SELECT id, device_sn, station_id, source, code, level, state, topic,
		       event_time, t, active_at, recovered_at, received_at,
		       raw_envelope, data_hash, created_at
		FROM device_alarm_events
		WHERE id = $1
	`, eventID).Scan(
		&event.ID, &event.DeviceSN, &stationID, &event.Source, &event.Code,
		&event.Level, &event.State, &event.Topic, &event.EventTime,
		&event.Timestamp, &activeAt, &recoveredAt, &event.ReceivedAt,
		&rawEnvelope, &event.DataHash, &event.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		response.NotFound(c, "alarm event not found")
		return
	}
	if err != nil {
		logger.Error("GetAlarmEventDetail: query event failed", zap.Int64("event_id", eventID), zap.Error(err))
		response.InternalError(c, "query alarm event failed")
		return
	}
	if !json.Valid(rawEnvelope) || len(rawEnvelope) == 0 || rawEnvelope[0] != '{' {
		logger.Error("GetAlarmEventDetail: invalid raw envelope", zap.Int64("event_id", eventID))
		response.InternalError(c, "invalid alarm event envelope")
		return
	}

	if !h.ensureDeviceAccess(c, event.DeviceSN) {
		return
	}

	var snapshots []byte
	err = h.db.QueryRow(ctx, `
		SELECT COALESCE(
			jsonb_agg(
				jsonb_build_object(
					'id', id,
					'device_sn', device_sn,
					'alarm_event_id', alarm_event_id,
					'snapshot_type', snapshot_type,
					'ac_voltage', ac_voltage,
					'ac_current', ac_current,
					'ac_active_power', ac_active_power,
					'ac_frequency', ac_frequency,
					'battery_soc', battery_soc,
					'battery_voltage', battery_voltage,
					'battery_current', battery_current,
					'battery_temperature', battery_temperature,
					'internal_temperature', internal_temperature,
					'dc_bus_voltage', dc_bus_voltage,
					'work_state', work_state,
					'fault_code', fault_code,
					'raw_snapshot', raw_snapshot,
					'captured_at', captured_at
				)
				ORDER BY captured_at, id
			),
			'[]'::jsonb
		)
		FROM device_alarm_snapshots
		WHERE alarm_event_id = $1 AND device_sn = $2
	`, event.ID, event.DeviceSN).Scan(&snapshots)
	if err != nil {
		logger.Error("GetAlarmEventDetail: query snapshots failed", zap.Int64("event_id", eventID), zap.Error(err))
		response.InternalError(c, "query alarm snapshots failed")
		return
	}
	if !json.Valid(snapshots) || len(snapshots) == 0 || snapshots[0] != '[' {
		logger.Error("GetAlarmEventDetail: invalid snapshots JSON", zap.Int64("event_id", eventID))
		response.InternalError(c, "invalid alarm snapshots")
		return
	}

	event.RawEnvelope = json.RawMessage(rawEnvelope)
	event.Snapshots = json.RawMessage(snapshots)
	if stationID.Valid {
		event.StationID = &stationID.Int64
	}
	if activeAt.Valid {
		event.ActiveAt = &activeAt.Time
	}
	if recoveredAt.Valid {
		event.RecoveredAt = &recoveredAt.Time
	}

	response.Success(c, event)
}
