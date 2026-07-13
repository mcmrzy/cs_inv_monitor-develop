package telemetry

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"time"
)

var (
	ErrUnsupportedVersion = errors.New("unsupported heartbeat version")
	ErrInvalidHeartbeat   = errors.New("invalid heartbeat payload")
)

type heartbeatEnvelope struct {
	Version uint16            `json:"v"`
	Time    int64             `json:"t"`
	Seq     uint32            `json:"seq"`
	AC      []json.RawMessage `json:"ac"`
	Battery []json.RawMessage `json:"bat"`
	PV      []json.RawMessage `json:"pv"`
	System  []json.RawMessage `json:"sys"`
	Energy  []json.RawMessage `json:"eng"`
	Cells   []json.RawMessage `json:"cells"`
}

func ParseHeartbeat(deviceSN string, payload []byte, cellCount int, receivedAt time.Time) (*Sample, error) {
	dec := json.NewDecoder(bytes.NewReader(payload))
	dec.UseNumber()
	var raw heartbeatEnvelope
	if err := dec.Decode(&raw); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidHeartbeat, err)
	}
	if raw.Version != 1 {
		return nil, fmt.Errorf("%w: %d", ErrUnsupportedVersion, raw.Version)
	}
	if deviceSN == "" || raw.Time <= 0 {
		return nil, fmt.Errorf("%w: missing sn or timestamp", ErrInvalidHeartbeat)
	}
	for name, pair := range map[string]struct{ got, want int }{
		"ac": {len(raw.AC), 8}, "bat": {len(raw.Battery), 21}, "pv": {len(raw.PV), 12},
		"sys": {len(raw.System), 10}, "eng": {len(raw.Energy), 8}, "cells": {len(raw.Cells), 2},
	} {
		if pair.got != pair.want {
			return nil, fmt.Errorf("%w: %s length %d, want %d", ErrInvalidHeartbeat, name, pair.got, pair.want)
		}
	}

	eventTime := time.Unix(raw.Time, 0).UTC()
	s := &Sample{ProtocolVersion: 1, DeviceSN: deviceSN, Sequence: raw.Seq, EventTime: eventTime, ReceivedAt: receivedAt.UTC()}
	if eventTime.After(receivedAt.Add(5 * time.Minute)) {
		s.QualityFlags |= QualityClockSkew
	}
	if eventTime.Before(receivedAt.Add(-24 * time.Hour)) {
		s.QualityFlags |= QualityBackfill
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

	ac, err := vals("ac", raw.AC)
	if err != nil {
		return nil, err
	}
	bat, err := vals("bat", raw.Battery)
	if err != nil {
		return nil, err
	}
	pv, err := vals("pv", raw.PV)
	if err != nil {
		return nil, err
	}
	sys, err := vals("sys", raw.System)
	if err != nil {
		return nil, err
	}
	eng, err := vals("eng", raw.Energy)
	if err != nil {
		return nil, err
	}

	bounded := func(p *float64, min, max float64) *float64 {
		if p != nil && (*p < min || *p > max) {
			s.QualityFlags |= QualityOutOfRange
			return nil
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

	s.AC = AC{bounded(ac[0], 0, 300), bounded(ac[1], 0, 40), bounded(ac[2], 0, 7500), bounded(ac[3], 0, 7500), bounded(ac[4], 45, 55), bounded(ac[5], 0, 1), bounded(ac[6], 0, 120), bounded(ac[7], 0, 100)}
	s.Battery = Battery{
		SOC: bounded(bat[0], 0, 100), SOH: bounded(bat[1], 0, 100), Voltage: bounded(bat[2], 0, 70),
		Current: bounded(bat[3], -150, 150), Power: bounded(bat[4], -7500, 7500), CapacityRemain: bounded(bat[5], 0, 1000),
		CapacityTotal: bounded(bat[6], 0, 1000), CycleCount: u32(bat[7]), TempMax: bounded(bat[8], -40, 100),
		TempMin: bounded(bat[9], -40, 100), CellVoltageMax: bounded(bat[10], 0, 5), CellVoltageMin: bounded(bat[11], 0, 5),
		CellVoltageDiff: bounded(bat[12], 0, 2), State: u8(bat[13], 3), ProtectStatus: u32(bat[14]), FaultCode: u32(bat[15]),
		MaxChargeCurrent: bounded(bat[16], 0, 150), MaxDischargeCurrent: bounded(bat[17], 0, 150),
		ChargeVoltageRef: bounded(bat[18], 0, 70), DischargeCutoffVoltage: bounded(bat[19], 0, 70), Temperature: bounded(bat[20], -40, 100),
	}
	s.PV = PV{bounded(pv[0], 0, 150), bounded(pv[1], 0, 30), bounded(pv[2], 0, 4000), bounded(pv[3], 0, 150), bounded(pv[4], 0, 4000), bounded(pv[5], 0, 150), bounded(pv[6], 0, 30), bounded(pv[7], 0, 4000), bounded(pv[8], 0, 150), bounded(pv[9], 0, 4000), bounded(pv[10], 0, 7500), u8(pv[11], 2)}
	s.System = System{u8(sys[0], 4), u32(sys[1]), u32(sys[2]), bounded(sys[3], -40, 100), bounded(sys[4], -40, 120), bounded(sys[5], -40, 100), bounded(sys[6], 0, 500), u32(sys[7]), u8(sys[8], 100), bounded(sys[9], 0, 100)}
	s.Energy = Energy{bounded(eng[0], 0, 1e6), bounded(eng[1], 0, 1e12), bounded(eng[2], 0, 1e6), bounded(eng[3], 0, 1e12), bounded(eng[4], 0, 1e6), bounded(eng[5], 0, 1e12), bounded(eng[6], 0, 1e6), bounded(eng[7], 0, 1e12)}

	var cellArrays [2][]json.RawMessage
	for i := range raw.Cells {
		if err := json.Unmarshal(raw.Cells[i], &cellArrays[i]); err != nil {
			return nil, fmt.Errorf("%w: cells[%d] must be an array", ErrInvalidHeartbeat, i)
		}
	}
	if cellCount <= 0 {
		cellCount = len(cellArrays[0])
	}
	if len(cellArrays[0]) != cellCount || len(cellArrays[1]) != cellCount {
		return nil, fmt.Errorf("%w: cell array lengths must equal %d", ErrInvalidHeartbeat, cellCount)
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
		cellT[i] = bounded(cellT[i], -40, 100)
	}
	s.Cells = Cells{Voltages: cellV, Temperatures: cellT}

	if s.PV.TotalPower != nil && s.PV.PV1Power != nil && s.PV.PV2Power != nil && math.Abs(*s.PV.TotalPower-*s.PV.PV1Power-*s.PV.PV2Power) > 50 {
		s.QualityFlags |= QualityInconsistent
	}
	if s.Battery.State != nil && s.Battery.Power != nil && ((*s.Battery.State == 1 && *s.Battery.Power < 0) || (*s.Battery.State == 2 && *s.Battery.Power > 0)) {
		s.QualityFlags |= QualityInconsistent
	}
	return s, nil
}
