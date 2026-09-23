package telemetry

import (
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// v3RunSample 是实机 H1ZZX00139000038（09-22 快照）的 ARM App(10) RunParamDef
// 87 个 u16 字序值，ESP 原样转发形态。字段对照见 heartbeat_v3.go 的 word* 常量。
// 该组值同时被 v2 测试夹具（l10App8ContractHeartbeatV2 / FixedARMLayout）覆盖，
// 用于锁定「v2 换算值 ≡ v3 原值解析」的跨版本等价性。
// 注意 ACOutputVolt=230 与 BoostTemp=35 是 **1V / 1℃ 单位**（UsartDsp.c 权威注释），
// 非早期误判的 0.1V / 0.1℃。
const v3RunSample = `[777,350,0,0,0,1240,820,0,35,300,` +
	`1870,1875,850,3470,3500,231,498,230,500,3470,` +
	`3500,3470,3500,120,490,80,618,0,0,69,` +
	`0,3919,0,0,0,0,50,100,0,0,` +
	`0,0,0,0,0,0,5,0,0,0,` +
	`0,0,0,0,0,0,0,0,0,0,` +
	`0,0,0,0,0,1192,0,0,0,0,` +
	`0,0,0,0,0,0,0,0,0,0,` +
	`0,2300,0,500,0,0,0]`

func v3Envelope(run string, ts int64) []byte {
	return []byte(`{"v":3,"t":` + strconv.FormatInt(ts, 10) +
		`,"data":{"run":` + run + `}}`)
}

// TestParseHeartbeatV3RawStruct 正常帧：87 字原值 → 物理量（DSP 量纲还原）。
func TestParseHeartbeatV3RawStruct(t *testing.T) {
	ts := int64(1789974000)
	s, err := ParseHeartbeatV3("H1ZZX00139000038",
		v3Envelope(v3RunSample, ts), time.Unix(ts+60, 0))
	require.NoError(t, err)
	require.Equal(t, uint16(3), s.ProtocolVersion)
	require.Equal(t, ts, s.EventTime.Unix())

	// sys
	require.Equal(t, uint32(777), *s.System.SysStatus)
	require.Equal(t, uint32(0), *s.System.FaultCode)
	require.Equal(t, uint64(5), *s.System.Warning)
	require.InDelta(t, 30.0, *s.System.InverterTemperature, 0.0001) // 300×0.1
	require.InDelta(t, 35.0, *s.System.BoostTemperature, 0.0001)    // 350×0.1
	require.InDelta(t, 391.9, *s.System.DCBusVoltage, 0.0001)       // 3919×0.1
	require.Equal(t, uint8(0), *s.System.BatteryOvercharge)
	// ARM 未赋值字段 → null
	require.Nil(t, s.System.TransformerTemperature)
	require.Nil(t, s.System.PVTemperature)

	// pv（Vpv 1V 直传、Buck 0.01A、Ppv 1W 直传）
	require.InDelta(t, 350.0, *s.PV.PV1Voltage, 0.0001)
	require.InDelta(t, 8.2, *s.PV.Buck1Current, 0.0001) // 820×0.01
	require.InDelta(t, 1240.0, *s.PV.TotalPower, 0.0001)

	// ac（AFoutputVolt 0.1V、频率 0.1Hz、电流 0.01A、功率 1W）
	require.InDelta(t, 230.0, *s.AC.Voltage, 0.0001)      // 2300×0.1
	require.InDelta(t, 50.0, *s.AC.Frequency, 0.0001)     // 500×0.1
	require.InDelta(t, 1870.0, *s.AC.ActivePower, 0.0001)
	require.InDelta(t, 8.5, *s.AC.Current, 0.0001)        // 850×0.01
	require.InDelta(t, 231.0, *s.AC.GridVoltage, 0.0001)  // 231×1V
	require.InDelta(t, 49.8, *s.AC.GridFrequency, 0.0001) // 498×0.1
	require.InDelta(t, 3470.0, *s.AC.ACInputPower, 0.0001)
	require.InDelta(t, 1.2, *s.AC.ACChargeCurrent, 0.0001) // 120×0.01
	require.InDelta(t, 5.0, *s.AC.LoadPercent, 0.0001)     // 50×0.1

	// bat（Vbat 0.1V、Ibat 0.1A 带方向、功率 1W）
	require.InDelta(t, 49.0, *s.Battery.Voltage, 0.0001)         // 490×0.1
	require.InDelta(t, 80.0, *s.Battery.SOC, 0.0001)
	require.InDelta(t, -6.9, *s.Battery.Current, 0.0001)         // bit3=Discharging → -69×0.1
	require.InDelta(t, 618.0, *s.Battery.DischargePower, 0.0001)

	// eng（0.1kWh）
	require.InDelta(t, 119.2, *s.Energy.DailyDischarge, 0.0001) // 1192×0.1

	// fan / diag / sock
	require.InDelta(t, 0.0, *s.Fan.MPPTSpeed, 0.0001)
	require.Nil(t, s.Diag.InvCurrent)
	require.Nil(t, s.Sock.PairedSocket)

	require.Zero(t, s.QualityFlags&QualityOutOfRange)
}

// TestParseHeartbeatV3SignedFields：s16 字段以 u16 位模式转发 → 服务端补码还原。
// 温度负值（冬季）与负功率是核心用例：若不做补码还原会得到 6552.x℃ / 6553x W，
// 被界限拒绝成 null（丢数据）。
func TestParseHeartbeatV3SignedFields(t *testing.T) {
	// BoostTemp = -5 (1℃ 单位, 0x FFFB = 65531) → -5.0℃;
	// InvertTemp = -100 (0.1℃ 单位, 65436) → -10.0℃;
	// OutputWatt = -200 (65336) → clamp0 → 0
	run := make([]string, runParamWordsV3)
	for i := range run {
		run[i] = "0"
	}
	run[wordBoostTemp] = "65531"
	run[wordInvertTemp] = "65436"
	run[wordOutputWatt] = "65336"
	ts := int64(1789974000)
	s, err := ParseHeartbeatV3("SN-TEST",
		[]byte(`{"v":3,"t":1789974000,"data":{"run":[`+strings.Join(run, ",")+`]}}`),
		time.Unix(ts+60, 0))
	require.NoError(t, err)
	require.InDelta(t, -5.0, *s.System.BoostTemperature, 0.0001)
	require.InDelta(t, -10.0, *s.System.InverterTemperature, 0.0001)
	require.InDelta(t, 0.0, *s.AC.ActivePower, 0.0001) // 负功率钳 0
	require.Zero(t, s.QualityFlags&QualityOutOfRange)
}

// TestParseHeartbeatV3U32U64Assembly：u32/u64 由连续字小端合成。
// Warning = 0x0000000100000005 → 字 [5,0,1,0] → 4294967301。
func TestParseHeartbeatV3U32U64Assembly(t *testing.T) {
	run := make([]string, runParamWordsV3)
	for i := range run {
		run[i] = "0"
	}
	run[wordWarning+0] = "5"
	run[wordWarning+2] = "1"
	run[wordFaultValue] = "0"
	run[wordFaultValue+1] = "1" // hi 字 = 1 → FaultValue = 65536
	run[wordEGenTotal] = "3"
	run[wordEGenTotal+1] = "1" // 3 + 65536 = 65539 (0.1kWh → 6553.9)
	ts := int64(1789974000)
	s, err := ParseHeartbeatV3("SN-TEST",
		[]byte(`{"v":3,"t":1789974000,"data":{"run":[`+strings.Join(run, ",")+`]}}`),
		time.Unix(ts+60, 0))
	require.NoError(t, err)
	require.Equal(t, uint64(4294967301), *s.System.Warning)
	require.Equal(t, uint32(65536), *s.System.FaultCode)
	require.InDelta(t, 6553.9, *s.Energy.GenTotal, 0.0001)
}

// TestPVVoltageFloor：PV 电压 <60V 视为无输入归 0（实测无 PV 接入时 Vpv1 上送
// ~11V 感应电压，直接展示会被误读为「有 PV 输入」）；60~530V 保留；>530V 仍越界。
func TestPVVoltageFloor(t *testing.T) {
	at := func(f float64) *float64 { return &f }
	var flags uint32

	require.InDelta(t, 0.0, *pvVoltageNormalized(at(0), &flags), 0.0001)
	require.InDelta(t, 0.0, *pvVoltageNormalized(at(11), &flags), 0.0001)   // 残压
	require.InDelta(t, 0.0, *pvVoltageNormalized(at(59.9), &flags), 0.0001)
	require.InDelta(t, 60.0, *pvVoltageNormalized(at(60), &flags), 0.0001)  // 边界保留
	require.InDelta(t, 350.0, *pvVoltageNormalized(at(350), &flags), 0.0001)
	require.InDelta(t, 530.0, *pvVoltageNormalized(at(530), &flags), 0.0001) // 上界保留
	require.Zero(t, flags&QualityOutOfRange) // 归零不是越界，不置质量位

	require.Nil(t, pvVoltageNormalized(at(600), &flags)) // >530V 仍判越界
	require.NotZero(t, flags&QualityOutOfRange)
	require.Nil(t, pvVoltageNormalized(nil, &flags))
}

// TestParseHeartbeatV3PVResidualVoltage：端到端——v3 帧里 Vpv1=11（无接入残压）
// 落 0、Vpv2=350（正常工作电压）保留。
func TestParseHeartbeatV3PVResidualVoltage(t *testing.T) {
	run := make([]string, runParamWordsV3)
	for i := range run {
		run[i] = "0"
	}
	run[wordVpv1] = "11"
	run[wordVpv2] = "350"
	ts := int64(1789974000)
	s, err := ParseHeartbeatV3("SN-TEST",
		[]byte(`{"v":3,"t":1789974000,"data":{"run":[`+strings.Join(run, ",")+`]}}`),
		time.Unix(ts+60, 0))
	require.NoError(t, err)
	require.InDelta(t, 0.0, *s.PV.PV1Voltage, 0.0001)
	require.InDelta(t, 350.0, *s.PV.PV2Voltage, 0.0001)
}

// TestParseHeartbeatV3RejectsBadLength：字数必须精确 = 87（结构体改版必须
// 同步服务端，否则整帧拒收并落 ingest error，便于发现固件/服务端不同步）。
func TestParseHeartbeatV3RejectsBadLength(t *testing.T) {
	_, err := ParseHeartbeatV3("SN-TEST",
		[]byte(`{"v":3,"t":1789974000,"data":{"run":[1,2,3]}}`),
		time.Unix(1789974000, 0))
	require.Error(t, err)
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

// TestParseHeartbeatV3RejectsV2Envelope：v2 帧（57 值分组）不得被 v3 解析器接受，
// 反之亦然——版本号是固件/服务端配套的唯一判据。
func TestParseHeartbeatV3RejectsV2Envelope(t *testing.T) {
	_, err := ParseHeartbeatV3("SN-TEST", []byte(validHeartbeatV2), time.Unix(1783000005, 0))
	require.Error(t, err)
}

// TestParseHeartbeatV3EnergyBounds：eng 日组 >200kWh 拒绝（实机 1190.1kWh 走字
// 脏值），与 v2 同界。
func TestParseHeartbeatV3EnergyBounds(t *testing.T) {
	run := make([]string, runParamWordsV3)
	for i := range run {
		run[i] = "0"
	}
	run[wordEacChrToday] = "11901" // 1190.1kWh > 200 → NULL
	ts := int64(1789974000)
	s, err := ParseHeartbeatV3("SN-TEST",
		[]byte(`{"v":3,"t":1789974000,"data":{"run":[`+strings.Join(run, ",")+`]}}`),
		time.Unix(ts+60, 0))
	require.NoError(t, err)
	require.Nil(t, s.Energy.ACChargeDaily)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
}
