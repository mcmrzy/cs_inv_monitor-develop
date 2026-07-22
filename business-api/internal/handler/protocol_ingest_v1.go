package handler

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

var (
	errProtocolDeviceNotFound = errors.New("protocol device not found")
	errProtocolNoStation      = errors.New("protocol device is not assigned to a station")
	errProtocolParallelMember = errors.New("parallel members must exist and belong to the reporter station")
	errProtocolNotThreePhase  = errors.New("device is not the active three-phase master")
)

type internalHandlerDB interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

type protocolV1Store interface {
	IngestAlarm(context.Context, protocolV1Record, alarmV1Data) (protocolV1Result, error)
	IngestParallel(context.Context, protocolV1Record, parallelV1Data) (protocolV1Result, error)
	IngestThreePhase(context.Context, protocolV1Record, threePhaseV1Data) (protocolV1Result, error)
	HasDeviceAccess(context.Context, int64, string) (bool, error)
}

type postgresProtocolV1Store struct {
	db *pgxpool.Pool
}

type protocolV1Envelope struct {
	T    int64           `json:"t"`
	V    int             `json:"v"`
	Data json.RawMessage `json:"data"`
}

type protocolV1Request struct {
	SN         string          `json:"sn"`
	Topic      string          `json:"topic"`
	ReceivedAt time.Time       `json:"received_at"`
	Envelope   json.RawMessage `json:"envelope"`
}

type protocolV1Record struct {
	SN          string
	Topic       string
	ReceivedAt  time.Time
	EventTime   time.Time
	Timestamp   int64
	Version     int
	DataHash    string
	RawData     json.RawMessage
	RawEnvelope json.RawMessage
}

type protocolV1Result struct {
	ID         int64
	Duplicate  bool
	OutOfOrder bool
}

var protocolV1SNPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,50}$`)

type alarmV1Data struct {
	Source int `json:"source"`
	Code   int `json:"code"`
	Level  int `json:"level"`
	State  int `json:"state"`
}

type parallelV1Machine struct {
	ID    int     `json:"id"`
	SN    string  `json:"sn"`
	Role  string  `json:"role"`
	Phase *string `json:"phase"`
	Power float64 `json:"power"`
	State int     `json:"state"`
}

type parallelV1Data struct {
	Enabled          bool                `json:"enabled"`
	Mode             string              `json:"mode"`
	Count            int                 `json:"count"`
	TotalRatedPower  int                 `json:"total_rated_power"`
	TotalActivePower float64             `json:"total_active_power"`
	SyncState        string              `json:"sync_state"`
	Machines         []parallelV1Machine `json:"machines"`
}

type threePhaseV1Data struct {
	Voltage          []float64 `json:"voltage"`
	Current          []float64 `json:"current"`
	ActivePower      []float64 `json:"active_power"`
	TotalActivePower float64   `json:"total_active_power"`
	LineVoltage      []float64 `json:"line_voltage"`
	Frequency        float64   `json:"frequency"`
	VoltageUnbalance float64   `json:"voltage_unbalance"`
	CurrentUnbalance float64   `json:"current_unbalance"`
}

func (h *InternalHandler) IngestAlarmV1(c *gin.Context) {
	record, rawData, err := decodeProtocolV1(c.Request, "alarm")
	if err != nil {
		response.HandleError(c, err)
		return
	}
	var data alarmV1Data
	if err := requireObjectFields(rawData, false, "source", "code", "level", "state"); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid alarm data: "+err.Error()))
		return
	}
	if err := decodeStrictJSON(rawData, &data); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid alarm data: "+err.Error()))
		return
	}
	if err := validateAlarmV1(data); err != nil {
		response.HandleError(c, apperr.BadRequest(err.Error()))
		return
	}
	result, storeErr := h.protocolStore().IngestAlarm(c.Request.Context(), record, data)
	h.finishProtocolIngest(c, result, storeErr)
}

func (h *InternalHandler) IngestParallelV1(c *gin.Context) {
	record, rawData, err := decodeProtocolV1(c.Request, "parallel")
	if err != nil {
		response.HandleError(c, err)
		return
	}
	var data parallelV1Data
	if err := requireParallelFields(rawData); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid parallel data: "+err.Error()))
		return
	}
	if err := decodeStrictJSON(rawData, &data); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid parallel data: "+err.Error()))
		return
	}
	if err := validateParallelV1(record.SN, data); err != nil {
		response.HandleError(c, apperr.BadRequest(err.Error()))
		return
	}
	result, storeErr := h.protocolStore().IngestParallel(c.Request.Context(), record, data)
	h.finishProtocolIngest(c, result, storeErr)
}

func (h *InternalHandler) IngestThreePhaseV1(c *gin.Context) {
	record, rawData, err := decodeProtocolV1(c.Request, "three_phase")
	if err != nil {
		response.HandleError(c, err)
		return
	}
	var data threePhaseV1Data
	if err := requireObjectFields(rawData, false, "voltage", "current", "active_power", "total_active_power", "line_voltage", "frequency", "voltage_unbalance", "current_unbalance"); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid three_phase data: "+err.Error()))
		return
	}
	if err := decodeStrictJSON(rawData, &data); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid three_phase data: "+err.Error()))
		return
	}
	if err := validateThreePhaseV1(data); err != nil {
		response.HandleError(c, apperr.BadRequest(err.Error()))
		return
	}
	result, storeErr := h.protocolStore().IngestThreePhase(c.Request.Context(), record, data)
	h.finishProtocolIngest(c, result, storeErr)
}

func (h *InternalHandler) protocolStore() protocolV1Store {
	if h.protocolV1 != nil {
		return h.protocolV1
	}
	return unavailableProtocolV1Store{}
}

func (h *InternalHandler) finishProtocolIngest(c *gin.Context, result protocolV1Result, err error) {
	if err != nil {
		switch {
		case errors.Is(err, errProtocolDeviceNotFound):
			response.HandleError(c, apperr.NotFound("device not found"))
		case errors.Is(err, errProtocolNoStation), errors.Is(err, errProtocolParallelMember), errors.Is(err, errProtocolNotThreePhase):
			response.HandleError(c, apperr.BadRequest(err.Error()))
		default:
			logger.Error("protocol v1 ingest failed", zap.Error(err))
			response.HandleError(c, apperr.Internal("protocol ingest failed", err))
		}
		return
	}
	response.Success(c, gin.H{"id": result.ID, "duplicate": result.Duplicate, "out_of_order": result.OutOfOrder})
}

type unavailableProtocolV1Store struct{}

func (unavailableProtocolV1Store) IngestAlarm(context.Context, protocolV1Record, alarmV1Data) (protocolV1Result, error) {
	return protocolV1Result{}, errors.New("protocol store unavailable")
}
func (unavailableProtocolV1Store) IngestParallel(context.Context, protocolV1Record, parallelV1Data) (protocolV1Result, error) {
	return protocolV1Result{}, errors.New("protocol store unavailable")
}
func (unavailableProtocolV1Store) IngestThreePhase(context.Context, protocolV1Record, threePhaseV1Data) (protocolV1Result, error) {
	return protocolV1Result{}, errors.New("protocol store unavailable")
}
func (unavailableProtocolV1Store) HasDeviceAccess(context.Context, int64, string) (bool, error) {
	return false, errors.New("protocol store unavailable")
}

func decodeProtocolV1(r *http.Request, expectedTopic string) (protocolV1Record, json.RawMessage, *apperr.AppError) {
	var req protocolV1Request
	if err := decodeStrictReader(r.Body, &req); err != nil {
		return protocolV1Record{}, nil, apperr.BadRequest("invalid protocol request: " + err.Error())
	}
	req.SN = strings.TrimSpace(req.SN)
	if req.SN == "" {
		return protocolV1Record{}, nil, apperr.BadRequest("sn is required")
	}
	if !protocolV1SNPattern.MatchString(req.SN) {
		return protocolV1Record{}, nil, apperr.BadRequest("invalid device sn")
	}
	topic, err := normalizeProtocolTopic(req.SN, req.Topic, expectedTopic)
	if err != nil {
		return protocolV1Record{}, nil, apperr.BadRequest(err.Error())
	}
	if req.ReceivedAt.IsZero() {
		return protocolV1Record{}, nil, apperr.BadRequest("received_at is required")
	}
	if len(req.Envelope) == 0 || bytes.Equal(bytes.TrimSpace(req.Envelope), []byte("null")) {
		return protocolV1Record{}, nil, apperr.BadRequest("envelope is required")
	}
	var envelope protocolV1Envelope
	if err := decodeStrictJSON(req.Envelope, &envelope); err != nil {
		return protocolV1Record{}, nil, apperr.BadRequest("invalid envelope: " + err.Error())
	}
	if envelope.T <= 0 {
		return protocolV1Record{}, nil, apperr.BadRequest("envelope.t must be greater than zero")
	}
	if envelope.V != 1 {
		return protocolV1Record{}, nil, apperr.BadRequest("unsupported protocol version")
	}
	if len(envelope.Data) == 0 || bytes.Equal(bytes.TrimSpace(envelope.Data), []byte("null")) {
		return protocolV1Record{}, nil, apperr.BadRequest("envelope.data is required")
	}
	hash, err := canonicalJSONHash(envelope.Data)
	if err != nil {
		return protocolV1Record{}, nil, apperr.BadRequest("invalid envelope.data: " + err.Error())
	}
	return protocolV1Record{
		SN:          req.SN,
		Topic:       topic,
		ReceivedAt:  req.ReceivedAt.UTC(),
		EventTime:   time.Unix(envelope.T, 0).UTC(),
		Timestamp:   envelope.T,
		Version:     envelope.V,
		DataHash:    hash,
		RawData:     append(json.RawMessage(nil), envelope.Data...),
		RawEnvelope: append(json.RawMessage(nil), req.Envelope...),
	}, envelope.Data, nil
}

func requireObjectFields(raw json.RawMessage, allowNull bool, names ...string) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil || fields == nil {
		return errors.New("data must be a JSON object")
	}
	for _, name := range names {
		value, ok := fields[name]
		if !ok || (!allowNull && bytes.Equal(bytes.TrimSpace(value), []byte("null"))) {
			return fmt.Errorf("data field %q is required", name)
		}
	}
	return nil
}

func requireParallelFields(raw json.RawMessage) error {
	if err := requireObjectFields(raw, false, "enabled", "mode", "count", "total_rated_power", "total_active_power", "sync_state", "machines"); err != nil {
		return err
	}
	var object map[string]json.RawMessage
	_ = json.Unmarshal(raw, &object)
	var machines []json.RawMessage
	if err := json.Unmarshal(object["machines"], &machines); err != nil {
		return errors.New("data field \"machines\" must be an array")
	}
	for index, machine := range machines {
		if err := requireObjectFields(machine, false, "id", "sn", "role", "power", "state"); err != nil {
			return fmt.Errorf("machines[%d]: %w", index, err)
		}
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(machine, &fields); err != nil {
			return fmt.Errorf("machines[%d] must be an object", index)
		}
		if _, exists := fields["phase"]; !exists {
			return fmt.Errorf("machines[%d]: data field %q is required", index, "phase")
		}
	}
	return nil
}

func normalizeProtocolTopic(sn, topic, expected string) (string, error) {
	topic = strings.Trim(strings.TrimSpace(topic), "/")
	if topic == expected {
		return expected, nil
	}
	parts := strings.Split(topic, "/")
	if len(parts) == 3 && parts[0] == "cs_inv" && parts[1] == sn && parts[2] == expected {
		return expected, nil
	}
	return "", fmt.Errorf("topic must be %q or %q", expected, "cs_inv/"+sn+"/"+expected)
}

func decodeStrictReader(r io.Reader, dst any) error {
	dec := json.NewDecoder(r)
	dec.DisallowUnknownFields()
	dec.UseNumber()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("multiple JSON values are not allowed")
		}
		return err
	}
	return nil
}

func decodeStrictJSON(raw []byte, dst any) error {
	return decodeStrictReader(bytes.NewReader(raw), dst)
}

func validateAlarmV1(data alarmV1Data) error {
	if data.Source < 0 || data.Source > 3 {
		return errors.New("alarm source must be between 0 and 3")
	}
	if data.Code < 0 {
		return errors.New("alarm code must not be negative")
	}
	if data.Level != 1 && data.Level != 2 {
		return errors.New("alarm level must be 1 or 2")
	}
	if data.State != 0 && data.State != 1 {
		return errors.New("alarm state must be 0 or 1")
	}
	return nil
}

func validateParallelV1(sn string, data parallelV1Data) error {
	if !protocolV1SNPattern.MatchString(sn) {
		return errors.New("invalid topic device SN")
	}
	validModes := map[string]bool{"standalone": true, "single_phase": true, "three_phase": true}
	validSync := map[string]bool{"idle": true, "synced": true, "syncing": true, "fault": true}
	if !validModes[data.Mode] {
		return errors.New("invalid parallel mode")
	}
	if !validSync[data.SyncState] {
		return errors.New("invalid parallel sync_state")
	}
	if data.Count < 0 || data.Count > 8 || data.Count != len(data.Machines) {
		return errors.New("parallel count must match machines length and be between 0 and 8")
	}
	if data.TotalRatedPower < 0 || uint64(data.TotalRatedPower) > math.MaxUint32 || !finite(data.TotalActivePower) || data.TotalActivePower < 0 {
		return errors.New("parallel total power is invalid")
	}
	if !data.Enabled {
		if data.Mode != "standalone" || data.Count != 0 || data.TotalRatedPower != 0 || data.TotalActivePower != 0 || data.SyncState != "idle" {
			return errors.New("disabled parallel state must be standalone, empty, zero-power and idle")
		}
		return nil
	}
	if data.Mode == "standalone" || data.Count == 0 || data.TotalRatedPower == 0 {
		return errors.New("enabled parallel state requires a non-standalone mode, members and rated power")
	}
	ids := make(map[int]bool, len(data.Machines))
	sns := make(map[string]bool, len(data.Machines))
	masterCount := 0
	phases := map[string]int{}
	powers := make([]float64, 0, len(data.Machines))
	previousID := -1
	for index, machine := range data.Machines {
		if machine.ID < 0 || machine.ID > 7 || machine.ID <= previousID || ids[machine.ID] {
			return errors.New("parallel machine ids must be unique, ascending and between 0 and 7")
		}
		previousID = machine.ID
		ids[machine.ID] = true
		machine.SN = strings.TrimSpace(machine.SN)
		if !protocolV1SNPattern.MatchString(machine.SN) || sns[machine.SN] {
			return errors.New("parallel machine SNs must be non-empty and unique")
		}
		sns[machine.SN] = true
		if machine.Role != "master" && machine.Role != "slave" {
			return errors.New("parallel machine role must be master or slave")
		}
		if machine.Role == "master" {
			masterCount++
			if machine.ID != 0 || machine.SN != sn {
				return errors.New("reporting device must be master with machine id 0")
			}
		} else if machine.ID == 0 {
			return errors.New("parallel machine 0 must be the master")
		}
		if machine.State != 0 && machine.State != 2 && machine.State != 3 {
			return fmt.Errorf("invalid parallel machine state %d at index %d", machine.State, index)
		}
		if !finite(machine.Power) || machine.Power < 0 {
			return errors.New("parallel machine power must be finite and non-negative")
		}
		powers = append(powers, machine.Power)
		if data.Mode == "three_phase" {
			if machine.Phase == nil || (*machine.Phase != "L1" && *machine.Phase != "L2" && *machine.Phase != "L3") {
				return errors.New("three-phase machines require phase L1, L2 or L3")
			}
			phases[*machine.Phase]++
		} else if machine.Phase != nil {
			return errors.New("single-phase machines must use null phase")
		}
	}
	if masterCount != 1 {
		return errors.New("parallel group must contain exactly one master")
	}
	if data.Mode == "three_phase" && (phases["L1"] == 0 || phases["L2"] == 0 || phases["L3"] == 0) {
		return errors.New("three-phase group must include L1, L2 and L3")
	}
	if !powerTotalsMatchV1(powers, data.TotalActivePower) {
		return errors.New("parallel total_active_power does not match member power")
	}
	return nil
}

func validateThreePhaseV1(data threePhaseV1Data) error {
	if len(data.Voltage) != 3 || len(data.Current) != 3 || len(data.ActivePower) != 3 || len(data.LineVoltage) != 3 {
		return errors.New("three_phase arrays must contain exactly three values")
	}
	for _, values := range [][]float64{data.Voltage, data.Current, data.ActivePower, data.LineVoltage} {
		for _, value := range values {
			if !finite(value) {
				return errors.New("three_phase values must be finite")
			}
		}
	}
	for _, values := range [][]float64{data.Voltage, data.Current, data.ActivePower, data.LineVoltage} {
		for _, value := range values {
			if value < 0 {
				return errors.New("three_phase voltage, current and power values must not be negative")
			}
		}
	}
	if !finite(data.TotalActivePower) || !finite(data.Frequency) || !finite(data.VoltageUnbalance) || !finite(data.CurrentUnbalance) ||
		data.TotalActivePower < 0 || data.Frequency < 0 || data.VoltageUnbalance < 0 || data.VoltageUnbalance > 100 || data.CurrentUnbalance < 0 || data.CurrentUnbalance > 100 {
		return errors.New("three_phase unbalance must be between 0 and 100 percent")
	}
	if !powerTotalsMatchV1(data.ActivePower, data.TotalActivePower) {
		return errors.New("three_phase total_active_power does not match phase power")
	}
	return nil
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func powerTotalsMatchV1(parts []float64, total float64) bool {
	var sum float64
	for _, part := range parts {
		sum += part
	}
	tolerance := math.Max(1, math.Abs(sum)*0.005)
	return math.Abs(sum-total) <= tolerance
}

func parseProtocolQueryRange(c *gin.Context) (*time.Time, *time.Time, error) {
	var start, end *time.Time
	if raw := strings.TrimSpace(c.Query("start_time")); raw != "" {
		parsed, err := time.Parse(time.RFC3339Nano, raw)
		if err != nil {
			return nil, nil, fmt.Errorf("start_time must be RFC3339: %w", err)
		}
		parsed = parsed.UTC()
		start = &parsed
	}
	if raw := strings.TrimSpace(c.Query("end_time")); raw != "" {
		parsed, err := time.Parse(time.RFC3339Nano, raw)
		if err != nil {
			return nil, nil, fmt.Errorf("end_time must be RFC3339: %w", err)
		}
		parsed = parsed.UTC()
		end = &parsed
	}
	if start != nil && end != nil && start.After(*end) {
		return nil, nil, errors.New("start_time must not be after end_time")
	}
	return start, end, nil
}

func canonicalJSONHash(raw []byte) (string, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var value any
	if err := dec.Decode(&value); err != nil {
		return "", err
	}
	var buf bytes.Buffer
	if err := writeCanonicalJSON(&buf, value); err != nil {
		return "", err
	}
	sum := sha256.Sum256(buf.Bytes())
	return hex.EncodeToString(sum[:]), nil
}

func writeCanonicalJSON(buf *bytes.Buffer, value any) error {
	switch typed := value.(type) {
	case nil:
		buf.WriteString("null")
	case bool:
		buf.WriteString(strconv.FormatBool(typed))
	case string:
		encoded, _ := json.Marshal(typed)
		buf.Write(encoded)
	case json.Number:
		number, err := strconv.ParseFloat(string(typed), 64)
		if err != nil || math.IsNaN(number) || math.IsInf(number, 0) {
			return errors.New("invalid JSON number")
		}
		if number == 0 {
			buf.WriteByte('0')
		} else {
			buf.WriteString(strconv.FormatFloat(number, 'g', -1, 64))
		}
	case []any:
		buf.WriteByte('[')
		for i, item := range typed {
			if i > 0 {
				buf.WriteByte(',')
			}
			if err := writeCanonicalJSON(buf, item); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		buf.WriteByte('{')
		for i, key := range keys {
			if i > 0 {
				buf.WriteByte(',')
			}
			encoded, _ := json.Marshal(key)
			buf.Write(encoded)
			buf.WriteByte(':')
			if err := writeCanonicalJSON(buf, typed[key]); err != nil {
				return err
			}
		}
		buf.WriteByte('}')
	default:
		return fmt.Errorf("unsupported JSON value %T", value)
	}
	return nil
}

func (s *postgresProtocolV1Store) IngestAlarm(ctx context.Context, record protocolV1Record, data alarmV1Data) (protocolV1Result, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return protocolV1Result{}, err
	}
	defer tx.Rollback(ctx)
	var stationID sql.NullInt64
	var userID int64
	if err := tx.QueryRow(ctx, `SELECT station_id, COALESCE(user_id,0) FROM devices WHERE sn=$1 AND deleted_at IS NULL`, record.SN).Scan(&stationID, &userID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return protocolV1Result{}, errProtocolDeviceNotFound
		}
		return protocolV1Result{}, err
	}
	code := strconv.Itoa(data.Code)
	// Namespace the lifecycle lock so telemetry/cell writes for the same SN do
	// not serialize behind alarm processing. Source and code retain independent
	// alarm lifecycles on one device.
	lockKey := "alarm-lifecycle:v1:" + record.SN + ":" + strconv.Itoa(data.Source) + ":" + code
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, lockKey); err != nil {
		return protocolV1Result{}, err
	}
	stateName := "active"
	var activeAt, recoveredAt any = record.EventTime, nil
	if data.State == 0 {
		stateName = "recovered"
		activeAt = nil
		recoveredAt = record.EventTime
	}

	// The immutable event is the idempotency barrier. Never mutate the current
	// alarm lifecycle until this insert proves the event is new.
	var eventID int64
	err = tx.QueryRow(ctx, `INSERT INTO device_alarm_events(device_sn,station_id,source,code,level,state,topic,event_time,t,active_at,recovered_at,raw_data,raw_envelope,data_hash,received_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13::jsonb,$14,$15) ON CONFLICT(device_sn,source,code,state,event_time) DO NOTHING RETURNING id`, record.SN, nullableInt64(stationID), data.Source, code, data.Level, stateName, record.Topic, record.EventTime, record.Timestamp, activeAt, recoveredAt, record.RawData, record.RawEnvelope, record.DataHash, record.ReceivedAt).Scan(&eventID)
	duplicate := errors.Is(err, pgx.ErrNoRows)
	if err != nil && !duplicate {
		return protocolV1Result{}, err
	}
	if duplicate {
		if err := tx.QueryRow(ctx, `SELECT id FROM device_alarm_events WHERE device_sn=$1 AND source=$2 AND code=$3 AND state=$4 AND event_time=$5`, record.SN, data.Source, code, stateName, record.EventTime).Scan(&eventID); err != nil {
			return protocolV1Result{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return protocolV1Result{}, err
		}
		return protocolV1Result{ID: eventID, Duplicate: true}, nil
	}
	if err := insertAlarmSnapshot(ctx, tx, record.SN, eventID, data.State); err != nil {
		return protocolV1Result{}, err
	}

	// 始终更新 alarms 投影表，移除乱序跳过逻辑
	// UPSERT 模式（UPDATE + INSERT fallback）和 recovery 的 occurred_at 条件
	// 已足够保证幂等性和正确性

	alarmLevel := 2
	if data.Level == 2 {
		alarmLevel = 3
	}
	if data.State == 1 {
		tag, err := tx.Exec(ctx, `UPDATE alarms SET type='device_fault',level=$4,alarm_level=$4,alarm_source=$2,event_state='active',station_id=$5,user_id=$6,fault_message=$7::text,message=$7::text,recovered_at=NULL,updated_at=NOW() WHERE device_sn=$1 AND alarm_source=$2 AND fault_code=$3 AND event_state='active'`, record.SN, data.Source, code, alarmLevel, nullableInt64(stationID), userID, "alarm code "+code)
		if err != nil {
			return protocolV1Result{}, err
		}
		if tag.RowsAffected() == 0 {
			if _, err := tx.Exec(ctx, `INSERT INTO alarms(device_sn,type,level,alarm_level,alarm_source,event_state,station_id,user_id,fault_code,fault_message,message,status,occurred_at,created_at,updated_at) VALUES($1,'device_fault',$4,$4,$2,'active',$5,$6,$3,$7::text,$7::text,0,$8,NOW(),NOW())`, record.SN, data.Source, code, alarmLevel, nullableInt64(stationID), userID, "alarm code "+code, record.EventTime); err != nil {
				return protocolV1Result{}, err
			}
		}
	} else if _, err := tx.Exec(ctx, `UPDATE alarms SET event_state='recovered',recovered_at=$4,updated_at=NOW() WHERE device_sn=$1 AND alarm_source=$2 AND fault_code=$3 AND event_state='active' AND occurred_at<=$4`, record.SN, data.Source, code, record.EventTime); err != nil {
		return protocolV1Result{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return protocolV1Result{}, err
	}
	return protocolV1Result{ID: eventID}, nil
}

func (s *postgresProtocolV1Store) IngestParallel(ctx context.Context, record protocolV1Record, data parallelV1Data) (protocolV1Result, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return protocolV1Result{}, err
	}
	defer tx.Rollback(ctx)
	var stationID int64
	if err := tx.QueryRow(ctx, `SELECT COALESCE(station_id,0) FROM devices WHERE sn=$1 AND deleted_at IS NULL`, record.SN).Scan(&stationID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return protocolV1Result{}, errProtocolDeviceNotFound
		}
		return protocolV1Result{}, err
	}
	if stationID == 0 {
		return protocolV1Result{}, errProtocolNoStation
	}
	if data.Enabled {
		memberSNs := make([]string, 0, len(data.Machines))
		for _, machine := range data.Machines {
			memberSNs = append(memberSNs, machine.SN)
		}
		var memberCount int
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM devices WHERE sn=ANY($1) AND station_id=$2 AND deleted_at IS NULL`, memberSNs, stationID).Scan(&memberCount); err != nil {
			return protocolV1Result{}, err
		}
		if memberCount != len(memberSNs) {
			return protocolV1Result{}, errProtocolParallelMember
		}
	}
	oldState := json.RawMessage("null")
	oldHash := ""
	var oldEventTime time.Time
	err = tx.QueryRow(ctx, `SELECT event_time,data_hash,jsonb_build_object('station_id',station_id,'master_sn',master_sn,'enabled',enabled,'mode',mode,'count',count,'total_rated_power',total_rated_power,'total_active_power',total_active_power,'sync_state',sync_state,'machines',machines,'event_time',event_time,'t',t,'data_hash',data_hash) FROM device_parallel_state WHERE station_id=$1 FOR UPDATE`, stationID).Scan(&oldEventTime, &oldHash, &oldState)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return protocolV1Result{}, err
	}
	hasCurrent := err == nil
	if hasCurrent && oldEventTime.Equal(record.EventTime) && oldHash == record.DataHash {
		if err := tx.Commit(ctx); err != nil {
			return protocolV1Result{}, err
		}
		return protocolV1Result{Duplicate: true}, nil
	}
	outOfOrder := hasCurrent && !record.EventTime.After(oldEventTime)
	changed := !hasCurrent || oldHash != record.DataHash
	var eventID int64
	if changed {
		eventType := "topology_changed"
		if !hasCurrent {
			eventType = "parallel_created"
		} else if outOfOrder {
			eventType = "out_of_order"
		} else if !data.Enabled {
			eventType = "disabled"
		}
		err = tx.QueryRow(ctx, `INSERT INTO device_parallel_events(station_id,master_sn,event_type,old_state,new_state,topic,event_time,t,raw_envelope,data_hash,occurred_at) VALUES($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7,$8,$9::jsonb,$10,$11) ON CONFLICT(master_sn,event_time,data_hash) DO NOTHING RETURNING id`, stationID, record.SN, eventType, oldState, record.RawData, record.Topic, record.EventTime, record.Timestamp, record.RawEnvelope, record.DataHash, record.EventTime).Scan(&eventID)
		if errors.Is(err, pgx.ErrNoRows) {
			if err := tx.QueryRow(ctx, `SELECT id FROM device_parallel_events WHERE master_sn=$1 AND event_time=$2 AND data_hash=$3`, record.SN, record.EventTime, record.DataHash).Scan(&eventID); err != nil {
				return protocolV1Result{}, err
			}
			if err := tx.Commit(ctx); err != nil {
				return protocolV1Result{}, err
			}
			return protocolV1Result{ID: eventID, Duplicate: true}, nil
		}
		if err != nil {
			return protocolV1Result{}, err
		}
	}
	if outOfOrder {
		if err := tx.Commit(ctx); err != nil {
			return protocolV1Result{}, err
		}
		return protocolV1Result{ID: eventID, OutOfOrder: true}, nil
	}
	_, err = tx.Exec(ctx, `INSERT INTO device_parallel_state(station_id,master_sn,enabled,mode,count,total_rated_power,total_active_power,sync_state,machines,topic,event_time,t,raw_envelope,data_hash,reported_at,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10,$11,$12,$13::jsonb,$14,$15,NOW(),NOW()) ON CONFLICT(station_id) DO UPDATE SET master_sn=EXCLUDED.master_sn,enabled=EXCLUDED.enabled,mode=EXCLUDED.mode,count=EXCLUDED.count,total_rated_power=EXCLUDED.total_rated_power,total_active_power=EXCLUDED.total_active_power,sync_state=EXCLUDED.sync_state,machines=EXCLUDED.machines,topic=EXCLUDED.topic,event_time=EXCLUDED.event_time,t=EXCLUDED.t,raw_envelope=EXCLUDED.raw_envelope,data_hash=EXCLUDED.data_hash,reported_at=EXCLUDED.reported_at,updated_at=NOW() WHERE EXCLUDED.event_time>device_parallel_state.event_time`, stationID, record.SN, data.Enabled, data.Mode, data.Count, data.TotalRatedPower, data.TotalActivePower, data.SyncState, record.RawDataFor("machines", data.Machines), record.Topic, record.EventTime, record.Timestamp, record.RawEnvelope, record.DataHash, record.EventTime)
	if err != nil {
		return protocolV1Result{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return protocolV1Result{}, err
	}
	return protocolV1Result{ID: eventID}, nil
	/*
		The WHERE clause above is a final database-side ordering guard. It keeps
		current state monotonic even if another writer races after the FOR UPDATE.
	*/
}

func (r protocolV1Record) RawDataFor(key string, fallback any) json.RawMessage {
	var data map[string]json.RawMessage
	if json.Unmarshal(r.RawData, &data) == nil && len(data[key]) > 0 {
		return data[key]
	}
	encoded, _ := json.Marshal(fallback)
	return encoded
}

func (s *postgresProtocolV1Store) IngestThreePhase(ctx context.Context, record protocolV1Record, data threePhaseV1Data) (protocolV1Result, error) {
	var valid bool
	if err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM devices d JOIN device_parallel_state p ON p.station_id=d.station_id WHERE d.sn=$1 AND d.deleted_at IS NULL AND p.master_sn=$1 AND p.enabled AND p.mode='three_phase')`, record.SN).Scan(&valid); err != nil {
		return protocolV1Result{}, err
	}
	if !valid {
		return protocolV1Result{}, errProtocolNotThreePhase
	}
	tag, err := s.db.Exec(ctx, `INSERT INTO device_three_phase_3min(device_sn,topic,event_time,t,received_at,data_hash,raw_envelope,voltage_l1,voltage_l2,voltage_l3,current_l1,current_l2,current_l3,active_power_l1,active_power_l2,active_power_l3,total_active_power,line_voltage_l1l2,line_voltage_l2l3,line_voltage_l3l1,frequency,voltage_unbalance,current_unbalance) VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23) ON CONFLICT(device_sn,event_time,data_hash) DO NOTHING`, record.SN, record.Topic, record.EventTime, record.Timestamp, record.ReceivedAt, record.DataHash, record.RawEnvelope, data.Voltage[0], data.Voltage[1], data.Voltage[2], data.Current[0], data.Current[1], data.Current[2], data.ActivePower[0], data.ActivePower[1], data.ActivePower[2], data.TotalActivePower, data.LineVoltage[0], data.LineVoltage[1], data.LineVoltage[2], data.Frequency, data.VoltageUnbalance, data.CurrentUnbalance)
	if err != nil {
		return protocolV1Result{}, err
	}
	return protocolV1Result{Duplicate: tag.RowsAffected() == 0}, nil
}

func nullableInt64(value sql.NullInt64) any {
	if value.Valid {
		return value.Int64
	}
	return nil
}

func missingAlarmSnapshotJSON() json.RawMessage {
	return json.RawMessage(`{"missing":true,"reason":"device_latest_state_not_found"}`)
}

func insertAlarmSnapshot(ctx context.Context, tx pgx.Tx, sn string, eventID int64, state int) error {
	snapshotType := "before"
	if state == 0 {
		snapshotType = "after"
	}
	tag, err := tx.Exec(ctx, `INSERT INTO device_alarm_snapshots(device_sn,alarm_event_id,snapshot_type,ac_voltage,ac_current,ac_active_power,ac_frequency,battery_soc,battery_voltage,battery_current,battery_temperature,internal_temperature,dc_bus_voltage,work_state,fault_code,raw_snapshot) SELECT device_sn,$2,$3,ac_voltage,ac_current,ac_active_power,ac_frequency,battery_soc,battery_voltage,battery_current,battery_temperature,inverter_temperature,dc_bus_voltage,work_state,fault_code,COALESCE(raw_envelope,'{}'::jsonb) FROM device_latest_state WHERE device_sn=$1 ON CONFLICT(alarm_event_id,snapshot_type) DO NOTHING`, sn, eventID, snapshotType)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		_, err = tx.Exec(ctx, `INSERT INTO device_alarm_snapshots(device_sn,alarm_event_id,snapshot_type,raw_snapshot) VALUES($1,$2,$3,$4::jsonb) ON CONFLICT(alarm_event_id,snapshot_type) DO NOTHING`, sn, eventID, snapshotType, missingAlarmSnapshotJSON())
	}
	return err
}

func (s *postgresProtocolV1Store) HasDeviceAccess(ctx context.Context, userID int64, sn string) (bool, error) {
	var allowed bool
	err := s.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM devices d
			WHERE d.sn = $2
			  AND d.deleted_at IS NULL
			  AND (
				d.user_id = $1
				OR EXISTS (
					SELECT 1
					FROM user_device_rel udr
					WHERE udr.user_id = $1 AND udr.device_sn = d.sn
				)
			  )
		)
	`, userID, sn).Scan(&allowed)
	return allowed, err
}

func (h *InternalHandler) ensureDeviceAccess(c *gin.Context, sn string) bool {
	if _, exists := c.Get("user_id"); !exists {
		response.Forbidden(c, "device access denied")
		return false
	}
	if middleware.GetRole(c) == 0 {
		return true
	}
	allowed, err := h.protocolStore().HasDeviceAccess(c.Request.Context(), middleware.GetUserID(c), sn)
	if err != nil {
		logger.Error("device ownership check failed", zap.String("sn", sn), zap.Error(err))
		response.InternalError(c, "device access check failed")
		return false
	}
	if !allowed {
		response.Forbidden(c, "device access denied")
		return false
	}
	return true
}
