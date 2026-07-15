package telemetry

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"time"
)

var (
	ErrUnsupportedVersion = errors.New("unsupported heartbeat version")
	ErrInvalidHeartbeat   = errors.New("invalid heartbeat payload")
)

type heartbeatEnvelope struct {
	Version uint16        `json:"v"`
	Time    int64         `json:"t"`
	Data    heartbeatData `json:"data"`
}

type heartbeatData struct {
	AC      []json.RawMessage `json:"ac"`
	Battery []json.RawMessage `json:"bat"`
	PV      []json.RawMessage `json:"pv"`
	System  []json.RawMessage `json:"sys"`
	Energy  []json.RawMessage `json:"eng"`
	Cells   []json.RawMessage `json:"cells"`
	// Extensions is the only forward-compatible extension point in V1. Core
	// positional arrays remain exact; vendor fields are namespaced under ext and
	// are retained by RawEnvelope without widening the telemetry table.
	Extensions json.RawMessage `json:"ext,omitempty"`
}

func ParseHeartbeat(deviceSN string, payload []byte, cellCount, tempSensorCount int, receivedAt time.Time) (*Sample, error) {
	dec := json.NewDecoder(bytes.NewReader(payload))
	dec.UseNumber()
	dec.DisallowUnknownFields()
	var raw heartbeatEnvelope
	if err := dec.Decode(&raw); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidHeartbeat, err)
	}
	if dec.Decode(&struct{}{}) != io.EOF {
		return nil, fmt.Errorf("%w: trailing JSON content", ErrInvalidHeartbeat)
	}
	if raw.Version != 1 {
		return nil, fmt.Errorf("%w: %d", ErrUnsupportedVersion, raw.Version)
	}
	if deviceSN == "" {
		return nil, fmt.Errorf("%w: missing device sn", ErrInvalidHeartbeat)
	}
	data := raw.Data
	if len(data.Extensions) > 0 {
		var extensions map[string]json.RawMessage
		if err := json.Unmarshal(data.Extensions, &extensions); err != nil || extensions == nil {
			return nil, fmt.Errorf("%w: ext must be a JSON object", ErrInvalidHeartbeat)
		}
	}
	for name, pair := range map[string]struct{ got, want int }{
		"ac": {len(data.AC), 8}, "bat": {len(data.Battery), 23}, "pv": {len(data.PV), 7},
		"sys": {len(data.System), 11}, "eng": {len(data.Energy), 12}, "cells": {len(data.Cells), 2},
	} {
		if pair.got != pair.want {
			return nil, fmt.Errorf("%w: %s length %d, want %d", ErrInvalidHeartbeat, name, pair.got, pair.want)
		}
	}

	eventTime := time.Unix(raw.Time, 0).UTC()
	normalizedData, _ := json.Marshal(data)
	hash := sha256.Sum256(normalizedData)
	s := &Sample{ProtocolVersion: 1, DeviceSN: deviceSN, EventTime: eventTime, ReceivedAt: receivedAt.UTC(), DataHash: fmt.Sprintf("%x", hash[:]), RawEnvelope: append([]byte(nil), payload...)}
	if raw.Time <= 0 || eventTime.After(receivedAt.Add(5*time.Minute)) || eventTime.Before(receivedAt.Add(-24*time.Hour)) {
		s.QualityFlags |= QualityClockInvalid
		s.EventTime = receivedAt.UTC()
	}

	vals := func(group string, in []json.RawMessage) ([]*float64, error) {
		out := make([]*float64, len(in))
		for i, item := range in {
			if bytes.Equal(bytes.TrimSpace(item), []byte("null")) {
				s.QualityFlags |= QualityPartial
				continue
			}
			var n json.Number
			if err := json.Unmarshal(item, &n); err != nil {
				return nil, fmt.Errorf("%w: %s[%d] must be numeric or null", ErrInvalidHeartbeat, group, i)
			}
			f, err := n.Float64()
			if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
				return nil, fmt.Errorf("%w: %s[%d] invalid number", ErrInvalidHeartbeat, group, i)
			}
			out[i] = &f
		}
		return out, nil
	}

	ac, err := vals("ac", data.AC)
	if err != nil {
		return nil, err
	}
	bat, err := vals("bat", data.Battery)
	if err != nil {
		return nil, err
	}
	pv, err := vals("pv", data.PV)
	if err != nil {
		return nil, err
	}
	sys, err := vals("sys", data.System)
	if err != nil {
		return nil, err
	}
	eng, err := vals("eng", data.Energy)
	if err != nil {
		return nil, err
	}

	bounded := func(p *float64, min, max float64) *float64 {
		if p != nil && (*p < min || *p > max) {
			s.QualityFlags |= QualityOutOfRange
		}
		return p
	}
	u8 := func(p *float64, max uint8) *uint8 {
		if p == nil {
			return nil
		}
		if *p < 0 || *p > float64(max) || math.Trunc(*p) != *p {
			s.QualityFlags |= QualityOutOfRange
			return nil
		}
		v := uint8(*p)
		return &v
	}
	u32 := func(p *float64) *uint32 {
		if p == nil {
			return nil
		}
		if *p < 0 || *p > math.MaxUint32 || math.Trunc(*p) != *p {
			s.QualityFlags |= QualityOutOfRange
			return nil
		}
		v := uint32(*p)
		return &v
	}

	s.AC = AC{
		Voltage: bounded(ac[0], 0, 250), Current: bounded(ac[1], 0, 28.2),
		ActivePower: bounded(ac[2], 0, 6200), ApparentPower: bounded(ac[3], 0, 6200),
		Frequency: bounded(ac[4], 0, 50.5), PowerFactor: bounded(ac[5], 0, 1),
		LoadPercent: bounded(ac[6], 0, 100), VoltageTHD: bounded(ac[7], 0, 5),
	}
	s.Battery = Battery{
		SOC: bounded(bat[0], 0, 100), SOH: bounded(bat[1], 0, 100), Voltage: bounded(bat[2], 40, 60),
		Current: bounded(bat[3], -150, 150), Power: bounded(bat[4], -7500, 7500), CapacityRemain: bounded(bat[5], 0, 1000),
		CapacityTotal: bounded(bat[6], 0, 1000), CycleCount: u32(bat[7]), TempMax: bounded(bat[8], -20, 85),
		TempMin: bounded(bat[9], -20, 85), CellVoltageMax: bounded(bat[10], 0, 5), CellVoltageMin: bounded(bat[11], 0, 5),
		CellVoltageDiff: bounded(bat[12], 0, 2), State: u8(bat[13], 3), ProtectStatus: u32(bat[14]), FaultCode: u32(bat[15]),
		MaxChargeCurrent: bounded(bat[16], 0, 150), MaxDischargeCurrent: bounded(bat[17], 0, 150),
		ChargeVoltageRef: bounded(bat[18], 40, 60), DischargeCutoffVoltage: bounded(bat[19], 40, 60), Temperature: bounded(bat[20], -20, 85),
		ChargeRequestCurrentX10: u32(bat[21]), ChargeRequestVoltageX10: u32(bat[22]),
	}
	pv1Power, pv2Power := bounded(pv[2], 0, 6200), bounded(pv[5], 0, 6200)
	var totalPV *float64
	if pv1Power != nil && pv2Power != nil {
		v := *pv1Power + *pv2Power
		totalPV = &v
	}
	s.PV = PV{
		PV1Voltage: bounded(pv[0], 0, 150), PV1Current: bounded(pv[1], 0, 30), PV1Power: pv1Power,
		PV2Voltage: bounded(pv[3], 0, 150), PV2Current: bounded(pv[4], 0, 30), PV2Power: pv2Power,
		TotalPower: totalPV, MPPTState: u8(pv[6], 2),
	}
	s.System = System{
		WorkState: u8(sys[0], 4), FaultCode: u32(sys[1]), AlarmCode: u32(sys[2]),
		InverterTemperature: bounded(sys[3], -20, 85), MOSTemperature: bounded(sys[4], -20, 85),
		AmbientTemperature: bounded(sys[5], -20, 85), DCBusVoltage: bounded(sys[6], 0, 450),
		RuntimeHours: u32(sys[7]), FanSpeedPercent: u8(sys[8], 100), Efficiency: bounded(sys[9], 0, 100),
		SystemMode: u32(sys[10]),
	}
	s.Energy = Energy{
		DailyPV: bounded(eng[0], 0, 1e6), TotalPV: bounded(eng[1], 0, 1e12),
		DailyCharge: bounded(eng[2], 0, 1e6), TotalCharge: bounded(eng[3], 0, 1e12),
		DailyDischarge: bounded(eng[4], 0, 1e6), TotalDischarge: bounded(eng[5], 0, 1e12),
		DailyLoad: bounded(eng[6], 0, 1e6), TotalLoad: bounded(eng[7], 0, 1e12),
		TotalChargeCapacity: bounded(eng[8], 0, 1e12), TotalDischargeCapacity: bounded(eng[9], 0, 1e12),
		TotalChargeTime: u32(eng[10]), TotalDischargeTime: u32(eng[11]),
	}
	if s.System.WorkState != nil && (*s.System.WorkState == 1 || *s.System.WorkState == 2) {
		bounded(s.AC.Voltage, 200, 250)
		bounded(s.AC.Frequency, 49.5, 50.5)
	}

	var cellArrays [2][]json.RawMessage
	for i := range data.Cells {
		if err := json.Unmarshal(data.Cells[i], &cellArrays[i]); err != nil {
			return nil, fmt.Errorf("%w: cells[%d] must be an array", ErrInvalidHeartbeat, i)
		}
	}
	if cellCount <= 0 {
		cellCount = len(cellArrays[0])
	}
	if tempSensorCount <= 0 {
		tempSensorCount = len(cellArrays[1])
	}
	if len(cellArrays[0]) != cellCount || len(cellArrays[1]) != tempSensorCount {
		return nil, fmt.Errorf("%w: cell voltage length must equal %d and temperature length must equal %d", ErrInvalidHeartbeat, cellCount, tempSensorCount)
	}
	cellV, err := vals("cells.voltages", cellArrays[0])
	if err != nil {
		return nil, err
	}
	cellT, err := vals("cells.temperatures", cellArrays[1])
	if err != nil {
		return nil, err
	}
	for i := range cellV {
		cellV[i] = bounded(cellV[i], 0, 5)
	}
	for i := range cellT {
		cellT[i] = bounded(cellT[i], -20, 85)
	}
	s.Cells = Cells{Voltages: cellV, Temperatures: cellT}

	if s.Battery.State != nil && s.Battery.Power != nil && ((*s.Battery.State == 1 && *s.Battery.Power < 0) || (*s.Battery.State == 2 && *s.Battery.Power > 0)) {
		s.QualityFlags |= QualityOutOfRange
	}
	return s, nil
}
