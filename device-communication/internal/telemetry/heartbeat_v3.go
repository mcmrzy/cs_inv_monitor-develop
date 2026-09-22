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

// V3 心跳协议（CS-L10-6K2 / ARM App(10)）：ESP 只转发 ARM 运行参数原值。
//
// 背景（2026-09-22 架构调整）：此前 ESP 固件承担「ARM 结构体字段 → 57 值契约
// 槽位 + 量纲换算」，先后出现两次换算结论错误（chr[2] 直传 vs ÷10、
// LoadPercent ×10 vs 直传），根因是量纲知识分散在固件里，且 DSP/ARM 各单位
// 不一致（同为 _DP 变量，Vload=0.1V 而 Vgrid=1V，无法从代码 ×1 推断）。
//
// 现改为：ESP 按 pack(1) 结构体字序原样转发 87 个 u16（{"run":[...]}），
// 字段映射 / 符号 / 量纲 / 界限全部集中在本文件 —— DSP/ARM 量纲调整只改
// 服务端一处，固件不再承担换算风险。
//
// 结构体布局见 ESP esp32c3_l10_idf/main/telemetry/arm_param.h
// （RunParamDef, 174B = 87×u16, pack(1)；u32 占 2 字、u64 占 4 字，小端）。
// 权威量纲来源 = DSP 发 ARM 的 TxBuf（UsartDsp.c）：
//
//	Vgrid/Vload/Vpv     ×1   （内部单位分别 1V / 0.1V / 1V，实机实证）
//	Igrid/Iload/Ipv/    ×100 → 0.01A
//	  Iinvt/Ibus
//	GridFreq/LoadFreq/  ×10  → 0.1Hz
//	  InvtFreq
//	Vbat/Vbus/Ibat      ×10  → 0.1V / 0.1A
//	Percent             ×10  → 0.1%
//	Temprature          ×10  → 0.1℃
//	功率                 ×1   → 1W / 1VA

type heartbeatEnvelopeV3 struct {
	Version uint16         `json:"v"`
	Time    int64          `json:"t"`
	Data    heartbeatRunV3 `json:"data"`
}

type heartbeatRunV3 struct {
	Run []json.RawMessage `json:"run"`
}

// runParamWordsV3 = RunParamDef 的 u16 字个数（174B / 2）。
const runParamWordsV3 = 87

// RunParamDef (arm_param.h, pack(1)) 的 u16 字序索引。
// u32/u64 字段在数组中连续占位（小端），由 u32At/u64At 合成。
const (
	wordSysStatus       = 0
	wordVpv1            = 1
	wordVpv2            = 2
	wordPpv1            = 3
	wordPpv2            = 4
	wordPpv             = 5
	wordBuck1Curr       = 6
	wordBuck2Curr       = 7
	wordBoostTemp       = 8
	wordInvertTemp      = 9
	wordOutputWatt      = 10
	wordOutputVA        = 11
	wordOutputCurr      = 12
	wordACChrWatt       = 13
	wordACChrVA         = 14
	wordGridVolt        = 15
	wordGridFreq        = 16
	wordACOutputVolt    = 17
	wordACOutputFreq    = 18
	wordACInWatt        = 19
	wordACInVA          = 20
	wordACDisChrWatt    = 21
	wordACDisChrVA      = 22
	wordACChrCurr       = 23
	wordBatVolt         = 24
	wordBatterySOC      = 25
	wordBatDisChrWatt   = 26
	wordBatChrWatt      = 27
	wordBatChgCurr      = 28
	wordBatDischgCurr   = 29
	wordBatOverCharge   = 30
	wordBusVolt         = 31
	wordIbus            = 32
	wordPvTemp          = 33
	wordInvCurr         = 34
	wordTransformerTemp = 35
	wordLoadPercent     = 36
	wordGridPercent     = 37
	wordParaChgCurr     = 38
	wordWorkTimeTotal   = 39 // u32: 39-40
	wordMpptFanSpeed    = 41
	wordInvFanSpeed     = 42
	wordPairedSocket    = 43
	wordOnlineSocket    = 44
	wordOnSocket        = 45
	wordWarning         = 46 // u64: 46-49
	wordBmsWarning      = 50
	wordFaultValue      = 51 // u32: 51-52
	wordEGenToday       = 53 // u32: 53-54
	wordEGenTotal       = 55 // u32: 55-56
	wordEpvToday        = 57 // u32: 57-58
	wordEpvTotal        = 59 // u32: 59-60
	wordEacChrToday     = 61 // u32: 61-62
	wordEacChrTotal     = 63 // u32: 63-64
	wordEbatDischrToday = 65 // u32: 65-66
	wordEbatDischrTotal = 67 // u32: 67-68
	wordEbatChrToday    = 69 // u32: 69-70
	wordEbatChrTotal    = 71 // u32: 71-72
	wordEacDischrToday  = 73 // u32: 73-74
	wordEacDischrTotal  = 75 // u32: 75-76
	wordEopDischrToday  = 77 // u32: 77-78
	wordEopDischrTotal  = 79 // u32: 79-80
	wordVinvtA          = 81
	wordIinvtA          = 82
	wordInvtFreq        = 83
	wordPinvt           = 84
	wordSinvt           = 85
	wordInvtPercent     = 86
)

// boundedValue 越界 → nil 并置 QualityOutOfRange（与 v2 的 bounded 闭包同语义，
// 提升为包级供 v3 复用）。越界不保留原值：ARM 固件可能输出垃圾值，保留会把
// 脏值写入数据库并展示到页面。
func boundedValue(p *float64, min, max float64, flags *uint32) *float64 {
	if p == nil {
		return nil
	}
	if *p < min || *p > max {
		*flags |= QualityOutOfRange
		return nil
	}
	return p
}

func u8Value(p *float64, max uint8, flags *uint32) *uint8 {
	if p == nil {
		return nil
	}
	if *p < 0 || *p > float64(max) || math.Trunc(*p) != *p {
		*flags |= QualityOutOfRange
		return nil
	}
	v := uint8(*p)
	return &v
}

func u32Value(p *float64, flags *uint32) *uint32 {
	if p == nil {
		return nil
	}
	if *p < 0 || *p > math.MaxUint32 || math.Trunc(*p) != *p {
		*flags |= QualityOutOfRange
		return nil
	}
	v := uint32(*p)
	return &v
}

func u64Value(p *float64, flags *uint32) *uint64 {
	if p == nil {
		return nil
	}
	if *p < 0 || *p > math.MaxUint64 || math.Trunc(*p) != *p {
		*flags |= QualityOutOfRange
		return nil
	}
	v := uint64(*p)
	return &v
}

// clamp0 负值钳 0：s16 的功率/电流字段为负视为测量毛刺（ARM 不做钳位，
// 旧 ESP 固件在固件侧钳；v3 起由服务端统一钳，语义与字段能力表一致）。
func clamp0(p *float64) *float64 {
	if p == nil {
		return nil
	}
	if *p < 0 {
		z := 0.0
		return &z
	}
	return p
}

func scale(p *float64, k float64) *float64 {
	if p == nil {
		return nil
	}
	v := *p * k
	return &v
}

// ParseHeartbeatV3 解析 ESP 原样转发的 ARM 运行参数（87 个 u16）。
func ParseHeartbeatV3(deviceSN string, payload []byte, receivedAt time.Time) (*Sample, error) {
	dec := json.NewDecoder(bytes.NewReader(payload))
	dec.UseNumber()
	dec.DisallowUnknownFields()
	var raw heartbeatEnvelopeV3
	if err := dec.Decode(&raw); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidHeartbeat, err)
	}
	if dec.Decode(&struct{}{}) != io.EOF {
		return nil, fmt.Errorf("%w: trailing JSON content", ErrInvalidHeartbeat)
	}
	if raw.Version != 3 {
		return nil, fmt.Errorf("%w: %d", ErrUnsupportedVersion, raw.Version)
	}
	if deviceSN == "" {
		return nil, fmt.Errorf("%w: missing device sn", ErrInvalidHeartbeat)
	}
	if len(raw.Data.Run) != runParamWordsV3 {
		return nil, fmt.Errorf("%w: run length %d, want %d",
			ErrInvalidHeartbeat, len(raw.Data.Run), runParamWordsV3)
	}

	eventTime := time.Unix(raw.Time, 0).UTC()
	normalizedData, _ := json.Marshal(raw.Data)
	hash := sha256.Sum256(normalizedData)
	s := &Sample{
		ProtocolVersion: 3,
		DeviceSN:        deviceSN,
		EventTime:       eventTime,
		ReceivedAt:      receivedAt.UTC(),
		DataHash:        fmt.Sprintf("%x", hash[:]),
		RawEnvelope:     append([]byte(nil), payload...),
	}
	if raw.Time <= 0 || eventTime.After(receivedAt.Add(5*time.Minute)) || eventTime.Before(receivedAt.Add(-24*time.Hour)) {
		s.QualityFlags |= QualityClockInvalid
		s.EventTime = receivedAt.UTC()
	}

	// 字序 → 数值。ESP 原样转发 u16 位模式，故 s16 字段需补码还原；
	// u32/u64 按小端由连续字合成（任一字缺失则整体视为缺失）。
	words := make([]*float64, runParamWordsV3)
	for i, item := range raw.Data.Run {
		if bytes.Equal(bytes.TrimSpace(item), []byte("null")) {
			s.QualityFlags |= QualityPartial
			continue
		}
		var n json.Number
		if err := json.Unmarshal(item, &n); err != nil {
			return nil, fmt.Errorf("%w: run[%d] must be numeric or null", ErrInvalidHeartbeat, i)
		}
		f, err := n.Float64()
		if err != nil || math.IsNaN(f) || math.IsInf(f, 0) || f < 0 || f > 65535 {
			return nil, fmt.Errorf("%w: run[%d] invalid value", ErrInvalidHeartbeat, i)
		}
		words[i] = &f
	}

	u16At := func(i int) *float64 { return words[i] }
	int16At := func(i int) *float64 {
		w := words[i]
		if w == nil {
			return nil
		}
		v := *w
		if v > 32767 {
			v -= 65536 // 补码：s16 负值以 u16 位模式转发
		}
		return &v
	}
	uint32At := func(i int) *float64 {
		lo, hi := words[i], words[i+1]
		if lo == nil || hi == nil {
			return nil
		}
		v := *lo + *hi*65536
		return &v
	}
	uint64At := func(i int) *float64 {
		v := 0.0
		for k := 0; k < 4; k++ {
			w := words[i+k]
			if w == nil {
				return nil
			}
			v += *w * math.Pow(65536, float64(k))
		}
		return &v
	}

	// ---- sys ----
	sysStatus := u32Value(u16At(wordSysStatus), &s.QualityFlags)
	s.System = System{
		SysStatus:              sysStatus,
		FaultCode:              u32Value(uint32At(wordFaultValue), &s.QualityFlags),
		Warning:                u64Value(uint64At(wordWarning), &s.QualityFlags),
		BmsWarning:             u32Value(u16At(wordBmsWarning), &s.QualityFlags),
		InverterTemperature:    boundedValue(scale(int16At(wordInvertTemp), 0.1), -40, 100, &s.QualityFlags),
		BoostTemperature:       boundedValue(scale(int16At(wordBoostTemp), 0.1), -40, 120, &s.QualityFlags),
		TransformerTemperature: nil, // ARM App(10) 未赋值（memset 恒 0），无测量意义
		PVTemperature:          nil,
		DCBusVoltage:           boundedValue(scale(u16At(wordBusVolt), 0.1), 0, 500, &s.QualityFlags),
		BatteryOvercharge:      u8Value(u16At(wordBatOverCharge), 1, &s.QualityFlags),
	}

	// ---- pv（Vpv 1V、Ipv 0.01A、Ppv 1W）----
	s.PV = PV{
		PV1Voltage:   boundedValue(u16At(wordVpv1), 0, 500, &s.QualityFlags),
		Buck1Current: boundedValue(scale(u16At(wordBuck1Curr), 0.01), 0, 30, &s.QualityFlags),
		PV2Voltage:   boundedValue(u16At(wordVpv2), 0, 500, &s.QualityFlags),
		Buck2Current: boundedValue(scale(u16At(wordBuck2Curr), 0.01), 0, 30, &s.QualityFlags),
		TotalPower:   boundedValue(u16At(wordPpv), 0, 7500, &s.QualityFlags),
	}

	// ---- ac（ACOutputVolt 0.1V、频率 0.1Hz、电流 0.01A、功率 1W/VA）----
	s.AC = AC{
		Voltage:                  boundedValue(scale(u16At(wordACOutputVolt), 0.1), 0, 250, &s.QualityFlags),
		Frequency:                boundedValue(scale(u16At(wordACOutputFreq), 0.1), 0, 55, &s.QualityFlags),
		ActivePower:              boundedValue(clamp0(int16At(wordOutputWatt)), 0, 7500, &s.QualityFlags),
		ApparentPower:            boundedValue(clamp0(int16At(wordOutputVA)), 0, 7500, &s.QualityFlags),
		Current:                  boundedValue(scale(clamp0(int16At(wordOutputCurr)), 0.01), 0, 100, &s.QualityFlags),
		GridVoltage:              boundedValue(u16At(wordGridVolt), 0, 300, &s.QualityFlags),
		GridFrequency:            boundedValue(scale(u16At(wordGridFreq), 0.1), 0, 55, &s.QualityFlags),
		ACInputPower:             boundedValue(clamp0(int16At(wordACInWatt)), 0, 7500, &s.QualityFlags),
		ACInputApparentPower:     boundedValue(clamp0(int16At(wordACInVA)), 0, 7500, &s.QualityFlags),
		ACBypassPower:            boundedValue(clamp0(int16At(wordACDisChrWatt)), 0, 7500, &s.QualityFlags),
		ACBypassApparentPower:    boundedValue(clamp0(int16At(wordACDisChrVA)), 0, 7500, &s.QualityFlags),
		ACChargePower:            boundedValue(clamp0(int16At(wordACChrWatt)), 0, 7500, &s.QualityFlags),
		ACChargeApparentPower:    boundedValue(clamp0(int16At(wordACChrVA)), 0, 7500, &s.QualityFlags),
		ACChargeCurrent:          boundedValue(scale(clamp0(int16At(wordACChrCurr)), 0.01), 0, 150, &s.QualityFlags),
		LoadPercent:              boundedValue(scale(u16At(wordLoadPercent), 0.1), 0, 120, &s.QualityFlags),
	}

	// ---- bat（Vbat 0.1V、Ibat 0.1A、功率 1W；电流方向由 SysStatus 位决定，
	// 与 v2 固件侧语义一致：bit2=Charge 取充电电流为正，bit3=Discharging 取负）----
	var batCurr *float64
	if sysStatus != nil {
		if *sysStatus&0x04 != 0 {
			batCurr = boundedValue(scale(u16At(wordBatChgCurr), 0.1), 0, 150, &s.QualityFlags)
		} else if *sysStatus&0x08 != 0 {
			if v := boundedValue(scale(u16At(wordBatDischgCurr), 0.1), 0, 150, &s.QualityFlags); v != nil {
				neg := -*v
				batCurr = &neg
			}
		}
	}
	s.Battery = Battery{
		Voltage:        boundedValue(scale(u16At(wordBatVolt), 0.1), 0, 70, &s.QualityFlags),
		SOC:            boundedValue(u16At(wordBatterySOC), 0, 100, &s.QualityFlags),
		Current:        batCurr,
		ChargePower:    boundedValue(u16At(wordBatChrWatt), 0, 7500, &s.QualityFlags),
		DischargePower: boundedValue(u16At(wordBatDisChrWatt), 0, 7500, &s.QualityFlags),
	}

	// ---- eng（0.1kWh；日组 ≤200kWh = 6kW 机型 24h 物理天花板含余量，
	// 总组 ≤1e7kWh；ARM Statistics 计数器有零充电走字脏值史，见
	// docs/ARM固件问题清单_运行参数上报_20260920.md）----
	engDaily := func(word int) *float64 {
		return boundedValue(scale(uint32At(word), 0.1), 0, 200, &s.QualityFlags)
	}
	engTotal := func(word int) *float64 {
		return boundedValue(scale(uint32At(word), 0.1), 0, 1e7, &s.QualityFlags)
	}
	s.Energy = Energy{
		GenDaily:       engDaily(wordEGenToday),
		GenTotal:       engTotal(wordEGenTotal),
		DailyPV:        engDaily(wordEpvToday),
		TotalPV:        engTotal(wordEpvTotal),
		ACChargeDaily:  engDaily(wordEacChrToday),
		ACChargeTotal:  engTotal(wordEacChrTotal),
		DailyDischarge: engDaily(wordEbatDischrToday),
		TotalDischarge: engTotal(wordEbatDischrTotal),
		DailyCharge:    engDaily(wordEbatChrToday),
		TotalCharge:    engTotal(wordEbatChrTotal),
		ACBypassDaily:  engDaily(wordEacDischrToday),
		ACBypassTotal:  engTotal(wordEacDischrTotal),
		OutputDaily:    engDaily(wordEopDischrToday),
		OutputTotal:    engTotal(wordEopDischrTotal),
	}

	// ---- fan / diag / sock（ARM App(10)：风扇与并机量恒 0，InvCurr/PvTemp/
	// TransformerTemp/插座未赋值 → 一律 null；ParaChgCurr/WorkTimeTotal 保留）----
	s.Fan = Fan{
		MPPTSpeed: boundedValue(u16At(wordMpptFanSpeed), 0, 100, &s.QualityFlags),
		InvSpeed:  boundedValue(u16At(wordInvFanSpeed), 0, 100, &s.QualityFlags),
	}
	s.Diag = Diag{
		InvCurrent:            nil, // ARM 未赋值
		ParallelChargeCurrent: boundedValue(u16At(wordParaChgCurr), 0, 600, &s.QualityFlags),
		WorkTimeTotal:         boundedValue(uint32At(wordWorkTimeTotal), 0, math.MaxUint32, &s.QualityFlags),
	}
	// 插座三值：ARM App(10) 未赋值（memset 恒 0），无测量意义 → null
	s.Sock = Sock{PairedSocket: nil, OnlineSocket: nil, OnSocket: nil}

	return s, nil
}
