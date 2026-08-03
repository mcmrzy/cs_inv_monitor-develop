package telemetry

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"time"
)

// V2 心跳协议（CS-L10-6K2）：位置数组 50 值，与 V1 同构校验。
// 设计见 docs/CS-L10-6K2_MQTT_上报协议设计.md 第 4 节。
//
// 与 V1 的差异：
//   - 组结构 sys[11]/pv[5]/ac[11]/chr[3]/bat[6]/eng[14]，无 cells 组；
//   - 数组元素为采集器协议原始量纲（0.1/0.01 缩放），解析时按字段 scale
//     还原为物理量，范围校验作用于还原后的物理量；
//   - work_state / battery_power 由解析层推导（见 protocol_parser.go V2 分支）。

type heartbeatEnvelopeV2 struct {
	Version uint16          `json:"v"`
	Time    int64           `json:"t"`
	Data    heartbeatDataV2 `json:"data"`
}

type heartbeatDataV2 struct {
	Sys []json.RawMessage `json:"sys"`
	PV  []json.RawMessage `json:"pv"`
	AC  []json.RawMessage `json:"ac"`
	Chr []json.RawMessage `json:"chr"`
	Bat []json.RawMessage `json:"bat"`
	Eng []json.RawMessage `json:"eng"`
}

// v2Scales 各组位置值的原始量纲 → 物理量 缩放系数（与迁移 091 device_protocol_fields.scale 一致）。
var v2Scales = map[string][]float64{
	"sys": {1, 1, 1, 1, 0.1, 0.1, 0.1, 0.1, 0.01, 0.1, 1},
	"pv":  {0.1, 0.1, 0.1, 0.1, 0.1},
	"ac":  {0.1, 0.01, 0.1, 0.1, 0.1, 0.1, 0.01, 0.1, 0.1, 0.1, 0.1},
	"chr": {0.1, 0.1, 0.1},
	"bat": {0.01, 0.1, 0.1, 0.1, 0.1, 1},
	"eng": {0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1},
}

func ParseHeartbeatV2(deviceSN string, payload []byte, receivedAt time.Time) (*Sample, error) {
	dec := json.NewDecoder(bytes.NewReader(payload))
	dec.UseNumber()
	dec.DisallowUnknownFields()
	var raw heartbeatEnvelopeV2
	if err := dec.Decode(&raw); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidHeartbeat, err)
	}
	if dec.Decode(&struct{}{}) != io.EOF {
		return nil, fmt.Errorf("%w: trailing JSON content", ErrInvalidHeartbeat)
	}
	if raw.Version != 2 {
		return nil, fmt.Errorf("%w: %d", ErrUnsupportedVersion, raw.Version)
	}
	if deviceSN == "" {
		return nil, fmt.Errorf("%w: missing device sn", ErrInvalidHeartbeat)
	}

	data := raw.Data
	for name, pair := range map[string]struct{ got, want int }{
		"sys": {len(data.Sys), 11}, "pv": {len(data.PV), 5}, "ac": {len(data.AC), 11},
		"chr": {len(data.Chr), 3}, "bat": {len(data.Bat), 6}, "eng": {len(data.Eng), 14},
	} {
		if pair.got != pair.want {
			return nil, fmt.Errorf("%w: %s length %d, want %d", ErrInvalidHeartbeat, name, pair.got, pair.want)
		}
	}

	eventTime := time.Unix(raw.Time, 0).UTC()
	normalizedData, _ := json.Marshal(data)
	hash := sha256.Sum256(normalizedData)
	s := &Sample{ProtocolVersion: 2, DeviceSN: deviceSN, EventTime: eventTime, ReceivedAt: receivedAt.UTC(), DataHash: fmt.Sprintf("%x", hash[:]), RawEnvelope: append([]byte(nil), payload...)}
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

	// scale 还原：原始量纲 → 物理量
	scaled := func(group string, in []*float64) []*float64 {
		scales := v2Scales[group]
		out := make([]*float64, len(in))
		for i, p := range in {
			if p == nil || scales[i] == 1 {
				out[i] = p
				continue
			}
			v := *p * scales[i]
			out[i] = &v
		}
		return out
	}

	rawSys, err := vals("sys", data.Sys)
	if err != nil {
		return nil, err
	}
	rawPV, err := vals("pv", data.PV)
	if err != nil {
		return nil, err
	}
	rawAC, err := vals("ac", data.AC)
	if err != nil {
		return nil, err
	}
	rawChr, err := vals("chr", data.Chr)
	if err != nil {
		return nil, err
	}
	rawBat, err := vals("bat", data.Bat)
	if err != nil {
		return nil, err
	}
	rawEng, err := vals("eng", data.Eng)
	if err != nil {
		return nil, err
	}
	sys := scaled("sys", rawSys)
	pv := scaled("pv", rawPV)
	ac := scaled("ac", rawAC)
	chr := scaled("chr", rawChr)
	bat := scaled("bat", rawBat)
	eng := scaled("eng", rawEng)

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
	u64 := func(p *float64) *uint64 {
		if p == nil {
			return nil
		}
		if *p < 0 || *p > math.MaxUint64 || math.Trunc(*p) != *p {
			s.QualityFlags |= QualityOutOfRange
			return nil
		}
		v := uint64(*p)
		return &v
	}

	s.System = System{
		SysStatus:             u32(sys[0]),
		FaultCode:             u32(sys[1]),
		Warning:               u64(sys[2]),
		BmsWarning:            u32(sys[3]),
		InverterTemperature:   bounded(sys[4], -40, 100),
		BoostTemperature:      bounded(sys[5], -40, 120),
		TransformerTemperature: bounded(sys[6], -40, 120),
		PVTemperature:         bounded(sys[7], -40, 120),
		DCBusVoltage:          bounded(sys[8], 0, 500),
		BatteryOvercharge:     u8(sys[10], 1),
	}
	s.PV = PV{
		PV1Voltage:   bounded(pv[0], 0, 150),
		Buck1Current: bounded(pv[1], 0, 30),
		PV2Voltage:   bounded(pv[2], 0, 150),
		Buck2Current: bounded(pv[3], 0, 30),
		TotalPower:   bounded(pv[4], 0, 7500),
	}
	s.AC = AC{
		Voltage:                  bounded(ac[0], 0, 250),
		Frequency:                bounded(ac[1], 0, 55),
		ActivePower:              bounded(ac[2], 0, 7500),
		ApparentPower:            bounded(ac[3], 0, 7500),
		Current:                  bounded(ac[4], 0, 100),
		GridVoltage:              bounded(ac[5], 0, 300),
		GridFrequency:            bounded(ac[6], 0, 55),
		ACInputPower:             bounded(ac[7], 0, 7500),
		ACInputApparentPower:     bounded(ac[8], 0, 7500),
		ACBypassPower:            bounded(ac[9], 0, 7500),
		ACBypassApparentPower:    bounded(ac[10], 0, 7500),
		ACChargePower:            bounded(chr[0], 0, 7500),
		ACChargeApparentPower:    bounded(chr[1], 0, 7500),
		ACChargeCurrent:          bounded(chr[2], 0, 150),
		// sys[9] 的负载百分比（V2 位置定义），存储/展示统一走 AC.LoadPercent（与 V1 一致）
		LoadPercent:              bounded(sys[9], 0, 120),
	}
	s.Battery = Battery{
		Voltage:        bounded(bat[0], 0, 70),
		SOC:            bounded(bat[1], 0, 100),
		Current:        bounded(bat[2], -150, 150),
		ChargePower:    bounded(bat[3], 0, 7500),
		DischargePower: bounded(bat[4], 0, 7500),
	}
	// bat[5] 与 sys[10] 同源（协议 BatOverCharge 仅一处）；bat[5] 可省略置 null，
	// 若 sys 缺失则用 bat 侧补充。
	if s.System.BatteryOvercharge == nil && bat[5] != nil {
		s.System.BatteryOvercharge = u8(bat[5], 1)
	}
	s.Energy = Energy{
		GenDaily:       bounded(eng[0], 0, 1e6),
		GenTotal:       bounded(eng[1], 0, 1e12),
		DailyPV:        bounded(eng[2], 0, 1e6),
		TotalPV:        bounded(eng[3], 0, 1e12),
		ACChargeDaily:  bounded(eng[4], 0, 1e6),
		ACChargeTotal:  bounded(eng[5], 0, 1e12),
		DailyDischarge: bounded(eng[6], 0, 1e6),
		TotalDischarge: bounded(eng[7], 0, 1e12),
		DailyCharge:    bounded(eng[8], 0, 1e6),
		TotalCharge:    bounded(eng[9], 0, 1e12),
		ACBypassDaily:  bounded(eng[10], 0, 1e6),
		ACBypassTotal:  bounded(eng[11], 0, 1e12),
		OutputDaily:    bounded(eng[12], 0, 1e6),
		OutputTotal:    bounded(eng[13], 0, 1e12),
	}

	return s, nil
}
