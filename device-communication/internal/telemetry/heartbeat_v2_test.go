package telemetry

import (
	"bytes"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// V2.1 文档 6.4 完整示例：V2 位置数组 57 值（原始量纲，0.1/0.01 缩放，fan/diag/sock 为 V2.1 新增）；
// bms 为 2026-09 储能 BMS 扩展组（45 值，additive，见储能BMS遥测扩展协议设计.md §7.7）。
const validHeartbeatV2 = `{"v":2,"t":1783000000,"data":{
  "sys":[2050,0,32,0,282,450,431,300,41000,624,0],
  "pv":[1450,82,0,0,12400],
  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
  "chr":[0,0,0],
  "bat":[5120,80,-255,0,13056],
  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765],
  "fan":[88,76],
  "diag":[880,45,68400000],
  "sock":[3,2,2],
  "bms":[1,805,985,1800,2800,3000,152,3351,3288,63,0,6,28,25,31,25,29,2,2,3,500,584,0,0,0,0,12345,11000,3351,3345,3338,3340,3302,3290,3288,3295,3300,3310,3315,3320,3325,3330,3335,3340,16]
}}`

func TestParseHeartbeatV2Valid(t *testing.T) {
	received := time.Unix(1783000005, 0)
	s, err := ParseHeartbeatV2("CSL1062K00000001", []byte(validHeartbeatV2), received)
	require.NoError(t, err)
	require.Equal(t, uint16(2), s.ProtocolVersion)
	require.Equal(t, int64(1783000000), s.EventTime.Unix())
	require.Zero(t, s.QualityFlags)

	// sys：原始量纲 → 物理量（scale 还原）
	require.Equal(t, uint32(2050), *s.System.SysStatus)
	require.Equal(t, uint32(0), *s.System.FaultCode)
	require.Equal(t, uint64(32), *s.System.Warning)
	require.Equal(t, uint32(0), *s.System.BmsWarning)
	require.InDelta(t, 28.2, *s.System.InverterTemperature, 0.0001)
	require.InDelta(t, 45.0, *s.System.BoostTemperature, 0.0001)
	require.InDelta(t, 43.1, *s.System.TransformerTemperature, 0.0001)
	require.InDelta(t, 30.0, *s.System.PVTemperature, 0.0001)
	require.InDelta(t, 410.0, *s.System.DCBusVoltage, 0.0001)
	require.InDelta(t, 62.4, *s.AC.LoadPercent, 0.0001)
	require.Equal(t, uint8(0), *s.System.BatteryOvercharge)

	// pv
	require.InDelta(t, 145.0, *s.PV.PV1Voltage, 0.0001)
	require.InDelta(t, 8.2, *s.PV.Buck1Current, 0.0001)
	require.InDelta(t, 0.0, *s.PV.PV2Voltage, 0.0001)
	require.InDelta(t, 0.0, *s.PV.Buck2Current, 0.0001)
	require.InDelta(t, 1240.0, *s.PV.TotalPower, 0.0001)

	// ac + chr
	require.InDelta(t, 220.5, *s.AC.Voltage, 0.0001)
	require.InDelta(t, 50.02, *s.AC.Frequency, 0.0001)
	require.InDelta(t, 1870.3, *s.AC.ActivePower, 0.0001)
	require.InDelta(t, 1875.6, *s.AC.ApparentPower, 0.0001)
	require.InDelta(t, 85.2, *s.AC.Current, 0.0001)
	require.Equal(t, 0.0, *s.AC.GridVoltage) // ac[5]=0 为有效值

	// bat（battery_soc 为 1%，scale=1）
	require.InDelta(t, 51.2, *s.Battery.Voltage, 0.0001)
	require.InDelta(t, 80.0, *s.Battery.SOC, 0.0001)
	require.InDelta(t, -25.5, *s.Battery.Current, 0.0001)
	require.InDelta(t, 1305.6, *s.Battery.DischargePower, 0.0001)
	require.Equal(t, 0.0, *s.Battery.ChargePower) // bat[3]=0 为有效值

	// eng
	require.InDelta(t, 125.0, *s.Energy.DailyPV, 0.0001)
	require.InDelta(t, 4567.8, *s.Energy.TotalPV, 0.0001)
	require.InDelta(t, 130.5, *s.Energy.DailyDischarge, 0.0001)
	require.InDelta(t, 2345.6, *s.Energy.TotalDischarge, 0.0001)
	require.InDelta(t, 187.0, *s.Energy.OutputDaily, 0.0001)
	require.InDelta(t, 9876.5, *s.Energy.OutputTotal, 0.0001)
	require.Equal(t, 0.0, *s.Energy.GenDaily) // eng[0]=0 为有效值

	// fan（V2.1 新增，scale=1）
	require.InDelta(t, 88.0, *s.Fan.MPPTSpeed, 0.0001)
	require.InDelta(t, 76.0, *s.Fan.InvSpeed, 0.0001)

	// diag（V2.1 新增：inv_current 0.1 缩放、parallel_charge_current 1A、work_time_total s）
	require.InDelta(t, 88.0, *s.Diag.InvCurrent, 0.0001)
	require.InDelta(t, 45.0, *s.Diag.ParallelChargeCurrent, 0.0001)
	require.InDelta(t, 68400000.0, *s.Diag.WorkTimeTotal, 0.0001)

	// sock（V2.1 新增：u16 位掩码）
	require.Equal(t, uint32(3), *s.Sock.PairedSocket)
	require.Equal(t, uint32(2), *s.Sock.OnlineSocket)
	require.Equal(t, uint32(2), *s.Sock.OnSocket)

	// bms（2026-09 储能扩展组：soc/soh/容量 0.1 缩放，芯压 mV，温度 ℃）
	require.Equal(t, uint8(1), *s.BMS.Online)
	require.InDelta(t, 80.5, *s.BMS.SOC, 0.0001)
	require.InDelta(t, 98.5, *s.BMS.SOH, 0.0001)
	require.InDelta(t, 180.0, *s.BMS.CapacityRemain, 0.0001)
	require.InDelta(t, 280.0, *s.BMS.CapacityFull, 0.0001)
	require.InDelta(t, 300.0, *s.BMS.CapacityDesign, 0.0001)
	require.InDelta(t, 152.0, *s.BMS.CycleCount, 0.0001)
	require.InDelta(t, 3351.0, *s.BMS.CellVoltageMax, 0.0001)
	require.InDelta(t, 3288.0, *s.BMS.CellVoltageMin, 0.0001)
	require.InDelta(t, 63.0, *s.BMS.CellVoltageDiff, 0.0001)
	require.InDelta(t, 0.0, *s.BMS.CellVoltageMaxIdx, 0.0001)
	require.InDelta(t, 6.0, *s.BMS.CellVoltageMinIdx, 0.0001)
	require.InDelta(t, 28.0, *s.BMS.CellTempMax, 0.0001)
	require.InDelta(t, 25.0, *s.BMS.CellTempMin, 0.0001)
	require.InDelta(t, 31.0, *s.BMS.MOSTemp, 0.0001)
	require.Equal(t, uint8(2), *s.BMS.BatteryWorkMode)   // 放电
	require.Equal(t, uint8(2), *s.BMS.MOSStatus)         // 放 MOS 开
	require.InDelta(t, 50.0, *s.BMS.ChgRequestCurrent, 0.0001)
	require.InDelta(t, 58.4, *s.BMS.ChgRequestVoltage, 0.0001)
	require.Equal(t, uint32(0), *s.BMS.FaultStatus)
	require.InDelta(t, 12345.0, *s.BMS.TotalChgCapacity, 0.0001)
	require.InDelta(t, 11000.0, *s.BMS.TotalDsgCapacity, 0.0001)
	require.Len(t, s.BMS.CellVoltages, 16)
	require.InDelta(t, 3351.0, *s.BMS.CellVoltages[0], 0.0001)
	require.InDelta(t, 3340.0, *s.BMS.CellVoltages[15], 0.0001)
	require.Equal(t, uint32(16), *s.BMS.BalanceBitmap)   // 芯 4 均衡

	require.Len(t, s.DataHash, 64)
	require.JSONEq(t, validHeartbeatV2, string(s.RawEnvelope))
}

// ARM 能量流界面直接按 V 显示交流输出电压、按 0.1Hz 显示频率。
// ESP32 当前透传 ARM 的运行参数，因此服务端必须按 ARM 实际量纲还原，
// 不能继续沿用 CollectorParamAddr.h 中过时的 0.1V/0.01Hz 注释。
func TestParseHeartbeatV2UsesActualARMACOutputUnits(t *testing.T) {
	payload := []byte(`{"v":2,"t":1783000000,"data":{
	  "sys":[256,0,0,0,250,250,null,null,0,0,0],
	  "pv":[0,0,0,0,0],
	  "ac":[31,500,0,0,0,0,0,0,0,0,0],
	  "chr":[0,0,0],
	  "bat":[0,0,0,0,0],
	  "eng":[0,0,0,0,0,0,0,0,0,0,0,0,0,0]
	}}`)

	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1783000005, 0))
	require.NoError(t, err)
	require.InDelta(t, 31.0, *s.AC.Voltage, 0.0001)
	require.InDelta(t, 50.0, *s.AC.Frequency, 0.0001)
}

// 49 值旧固件（V2.0）不带 fan/diag/sock 组：六组正常解析，新组置空，QualityPartial。
func TestParseHeartbeatV2Legacy49Values(t *testing.T) {
	payload := []byte(`{"v":2,"t":1783000000,"data":{
	  "sys":[2050,0,32,0,282,450,431,300,41000,624,0],
	  "pv":[1450,82,0,0,12400],
	  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
	  "chr":[0,0,0],
	  "bat":[5120,80,-255,0,13056],
	  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]
	}}`)
	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1783000005, 0))
	require.NoError(t, err)
	require.NotZero(t, s.QualityFlags&QualityPartial)
	require.InDelta(t, 220.5, *s.AC.Voltage, 0.0001)
	require.InDelta(t, 80.0, *s.Battery.SOC, 0.0001)
	require.Nil(t, s.Fan.MPPTSpeed)
	require.Nil(t, s.Diag.WorkTimeTotal)
	require.Nil(t, s.Sock.PairedSocket)
	require.Nil(t, s.BMS.Online)   // 旧固件无 bms 组：零值结构
	require.Nil(t, s.BMS.CellVoltages)
}

// bms 组存在但长度错误 → 格式错误（不按旧固件容忍）
func TestParseHeartbeatV2RejectsBadBMSLength(t *testing.T) {
	payload := bytes.Replace([]byte(validHeartbeatV2),
		[]byte(`"bms":[1,805,985,1800,2800,3000,152,3351,3288,63,0,6,28,25,31,25,29,2,2,3,500,584,0,0,0,0,12345,11000,3351,3345,3338,3340,3302,3290,3288,3295,3300,3310,3315,3320,3325,3330,3335,3340,16]`),
		[]byte(`"bms":[1,805,985]`), 1)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

// bms 离线帧：online=0，其余值 null（ESP 端离线语义）→ null 标记 QualityPartial，字段为 nil
func TestParseHeartbeatV2BMSOffline(t *testing.T) {
	nulls := strings.Repeat("null,", 43)
	payload := bytes.Replace([]byte(validHeartbeatV2),
		[]byte(`"bms":[1,805,985,1800,2800,3000,152,3351,3288,63,0,6,28,25,31,25,29,2,2,3,500,584,0,0,0,0,12345,11000,3351,3345,3338,3340,3302,3290,3288,3295,3300,3310,3315,3320,3325,3330,3335,3340,16]`),
		[]byte(`"bms":[0,`+nulls+`null]`), 1)
	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1783000005, 0))
	require.NoError(t, err)
	require.Equal(t, uint8(0), *s.BMS.Online)
	require.Nil(t, s.BMS.SOC)
	require.Nil(t, s.BMS.CellVoltages[0])
	require.Nil(t, s.BMS.BalanceBitmap)
}

func TestParseHeartbeatV2RejectsArrayLength(t *testing.T) {
	payload := []byte(`{"v":2,"t":1,"data":{"sys":[],"pv":[],"ac":[],"chr":[],"bat":[],"eng":[]}}`)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

// V2.2+ 固件扩展格式（实测 H1CNA00135000014）：data 内新增 arm_online、
// chr 扩到 4 值、fan 扩到 3 值；新值语义未发布，仅容忍并忽略，已知索引正常映射
func TestParseHeartbeatV2AcceptsV22Extensions(t *testing.T) {
	payload := []byte(`{"v":2,"t":1786685655,"data":{
	  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
	  "arm_online":true,
	  "bat":[5120,80,-255,0,13056],
	  "chr":[1250,1300,85,999],
	  "diag":[420,30,1800000],
	  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765],
	  "fan":[88,76,50],
	  "pv":[1450,82,0,0,12400],
	  "sock":[3,2,2],
	  "sys":[2050,0,32,0,282,450,null,null,41000,624,0]
	}}`)
	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1786685660, 0))
	require.NoError(t, err)
	// 已知索引正常映射（chr 前 3 值 / fan 前 2 值）
	require.InDelta(t, 125.0, *s.AC.ACChargePower, 0.0001)
	require.InDelta(t, 88.0, *s.Fan.MPPTSpeed, 0.0001)
	require.InDelta(t, 76.0, *s.Fan.InvSpeed, 0.0001)
	require.Equal(t, uint32(3), *s.Sock.PairedSocket)
}

// 新组存在但长度错误 → 格式错误（不按旧固件容忍）
func TestParseHeartbeatV2RejectsBadFanLength(t *testing.T) {
	payload := bytes.Replace([]byte(validHeartbeatV2), []byte(`"fan":[88,76]`), []byte(`"fan":[88]`), 1)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

// sock 位掩码为负数 → 越界（u32 拒绝，置 nil + QualityOutOfRange，不阻断整包）
func TestParseHeartbeatV2RejectsBadSockValue(t *testing.T) {
	payload := bytes.Replace([]byte(validHeartbeatV2), []byte(`"sock":[3,2,2]`), []byte(`"sock":[-1,2,2]`), 1)
	s, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.NoError(t, err)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
	require.Nil(t, s.Sock.PairedSocket)
	require.Equal(t, uint32(2), *s.Sock.OnlineSocket)
}

func TestParseHeartbeatV2RejectsUnknownVersion(t *testing.T) {
	_, err := ParseHeartbeatV2("sn", []byte(`{"v":3}`), time.Now())
	require.True(t, errors.Is(err, ErrUnsupportedVersion))
}

func TestParseHeartbeatV2RejectsUnknownField(t *testing.T) {
	payload := bytes.Replace([]byte(validHeartbeatV2), []byte(`"eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]`), []byte(`"eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765],"cells":[[1.0]]`), 1)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseHeartbeatV2NullsMarkQualityPartial(t *testing.T) {
	payload := []byte(`{"v":2,"t":1783000000,"data":{
	  "sys":[null,null,null,null,null,null,null,null,null,null,null],
	  "pv":[null,null,null,null,null],
	  "ac":[null,null,null,null,null,null,null,null,null,null,null],
	  "chr":[null,null,null],
	  "bat":[null,null,null,null,null],
	  "eng":[null,null,null,null,null,null,null,null,null,null,null,null,null,null]
	}}`)
	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1783000005, 0))
	require.NoError(t, err)
	require.NotZero(t, s.QualityFlags&QualityPartial)
	require.Nil(t, s.System.SysStatus)
	require.Nil(t, s.Battery.Voltage)
}

// 越界值 → 值置 nil（落库 NULL）+ QualityOutOfRange，防止固件脏值上屏（V2 bounded 语义）。
func TestParseHeartbeatV2DiscardsOutOfRangeValue(t *testing.T) {
	payload := []byte(`{"v":2,"t":1783000000,"data":{
	  "sys":[0,0,0,0,9999,450,431,300,5120,624,0],
	  "pv":[1450,82,0,0,12400],
	  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
	  "chr":[0,0,0],
	  "bat":[5120,80,-255,0,13056],
	  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]
	}}`)
	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1783000005, 0))
	require.NoError(t, err)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
	require.Nil(t, s.System.InverterTemperature) // 越界值丢弃（9999*0.1=999.9 > 100）
	// 同包合法值不受影响
	require.InDelta(t, 62.4, *s.AC.LoadPercent, 0.0001)
	require.InDelta(t, 51.2, *s.System.DCBusVoltage, 0.0001) // sys[8]=5120×0.01
}

func TestParseHeartbeatV2InvalidClockFallback(t *testing.T) {
	payload := []byte(`{"v":2,"t":0,"data":{
	  "sys":[0,0,0,0,0,0,0,0,0,0,0],
	  "pv":[0,0,0,0,0],
	  "ac":[0,0,0,0,0,0,0,0,0,0,0],
	  "chr":[0,0,0],
	  "bat":[0,0,0,0,0],
	  "eng":[0,0,0,0,0,0,0,0,0,0,0,0,0,0]
	}}`)
	received := time.Unix(1783000005, 0).UTC()
	s, err := ParseHeartbeatV2("sn", payload, received)
	require.NoError(t, err)
	require.Equal(t, received, s.EventTime)
	require.NotZero(t, s.QualityFlags&QualityClockInvalid)
}

func TestParseHeartbeatV2RejectsNonNumeric(t *testing.T) {
	payload := []byte(`{"v":2,"t":1783000000,"data":{
	  "sys":[2050,0,0,0,282,450,431,300,5120,"x",0],
	  "pv":[1450,82,0,0,12400],
	  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
	  "chr":[0,0,0],
	  "bat":[5120,80,-255,0,13056],
	  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]
	}}`)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

// 现场实测脏心跳（SN H1ZZX0023900002P，ARM 固件输出垃圾值）：合法值照常保留，
// 越界值全部置 nil + QualityOutOfRange，防止视在功率 2883584VA、负载率 3735% 之类的
// 脏值落库并显示到页面（缩放按 v2Scales：sys[9] 0.1、ac/chr[1]/diag[0] 0.1）。
func TestParseHeartbeatV2RealDirtyHeartbeat(t *testing.T) {
	payload := []byte(`{"v":2,"t":1789887119,"data":{"sys":[265,0,0,0,0,0,null,null,0,37350,0],"pv":[6,0,0,0,0],"ac":[0,0,500,28180480,6187,0,0,10,325714148,0,0],"chr":[0,560726016,0],"bat":[0,0,0,4900,0],"eng":[20078,0,0,0,0,3,0,0,0,11907,0,11907,0,0],"fan":[0,100],"diag":[13340,21008,0],"sock":[0,0,0]}}`)
	s, err := ParseHeartbeatV2("H1ZZX0023900002P", payload, time.Unix(1789887119+60, 0))
	require.NoError(t, err)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)

	// 合法值保留（原始值 × v2Scales 缩放）
	require.Equal(t, "H1ZZX0023900002P", s.DeviceSN)
	require.Equal(t, uint32(265), *s.System.SysStatus)
	require.InDelta(t, 0.0, *s.PV.PV1Voltage, 0.0001) // pv[0]=6 → 0.6V <60V 残压归 0
	require.InDelta(t, 50.0, *s.AC.ActivePower, 0.0001)
	require.InDelta(t, 1.0, *s.AC.ACInputPower, 0.0001)   // ac[7]=10×0.1
	require.InDelta(t, 100.0, *s.Fan.InvSpeed, 0.0001)
	require.InDelta(t, 0.3, *s.Energy.ACChargeTotal, 0.0001)
	require.InDelta(t, 1190.7, *s.Energy.TotalCharge, 0.0001)
	require.InDelta(t, 490.0, *s.Battery.ChargePower, 0.0001)
	require.InDelta(t, 0.0, *s.System.DCBusVoltage, 0.0001)

	// 越界值 → nil（落库 NULL / realtime null）
	require.Nil(t, s.AC.LoadPercent)                    // 37350×0.1=3735 > 120
	require.Nil(t, s.AC.Current)                        // 6187×0.1=618.7 > 100
	require.Nil(t, s.AC.ApparentPower)                  // 28180480×0.1=2818048 > 7500
	require.Nil(t, s.AC.ACInputApparentPower)           // 325714148×0.1=32571414.8 > 7500
	require.Nil(t, s.AC.ACChargeApparentPower)          // 560726016×0.1=56072601.6 > 7500
	require.Nil(t, s.Diag.InvCurrent)                   // 13340×0.1=1334 > 100
	require.Nil(t, s.Diag.ParallelChargeCurrent)        // 21008 > 600
	require.Nil(t, s.Energy.GenDaily)                   // 20078×0.1=2007.8 > 200（日组界）
}

// mirrorDeriveV2BatteryPower 按 internal/service/protocol_parser.go deriveV2BatteryPower
// 的语义（battery_power = charge - discharge，充电为正、放电为负，与电流方向一致）复刻派生，
// 供验收断言 Battery.Power。telemetry 包不能反向 import service，故在此锁定同一契约；
// 若生产派生逻辑变更，需同步更新此处。
func mirrorDeriveV2BatteryPower(s *Sample) *float64 {
	switch {
	case s.Battery.ChargePower != nil && s.Battery.DischargePower != nil:
		v := *s.Battery.ChargePower - *s.Battery.DischargePower
		return &v
	case s.Battery.ChargePower != nil:
		return s.Battery.ChargePower
	case s.Battery.DischargePower != nil:
		v := -*s.Battery.DischargePower
		return &v
	}
	return nil
}

// fixedARMLayoutHeartbeatV2 是 ESP 固件按 ARM 新版 200B 寄存器布局 + 单位换算修复后，
// 对同一组现场寄存器值的预期心跳输出（SN H1ZZX0023900002P）：所有数值经 v2Scales
// 缩放后必须落在 bounded() 界内，仅语义性 null（sys[6]/sys[7] 温度传感器、diag[0]、sock
// 全组）与缺省 bms 组允许置 QualityPartial。
const fixedARMLayoutHeartbeatV2 = `{"v":2,"t":1789887119,"data":{"sys":[265,0,5,0,430,350,null,null,37350,1000,0],"pv":[60,50,0,0,62000],"ac":[2300,5000,61870,65000,8,0,0,0,0,0,0],"chr":[0,0,0],"bat":[4900,0,-1334,0,61870],"eng":[0,0,3,0,0,0,1190,0,1190,0,0,0,0,0],"fan":[0,0],"diag":[null,0,0],"sock":[null,null,null]}}`

// TestParseHeartbeatV2FixedARMLayout 验收测试：锁定"修复后的 ESP 输出"必须解析出的
// 物理正确值。修复前同一组寄存器错位/未换算时的服务端表现见
// TestParseHeartbeatV2MisalignedOldLayout（对照负例）。
func TestParseHeartbeatV2FixedARMLayout(t *testing.T) {
	s, err := ParseHeartbeatV2("H1ZZX0023900002P", []byte(fixedARMLayoutHeartbeatV2), time.Unix(1789887119+60, 0))
	require.NoError(t, err)

	require.Equal(t, "H1ZZX0023900002P", s.DeviceSN)
	require.Equal(t, uint16(2), s.ProtocolVersion)
	require.Equal(t, int64(1789887119), s.EventTime.Unix()) // t 与 receivedAt 偏差 60s，时钟有效

	// System
	require.Equal(t, uint32(265), *s.System.SysStatus)
	require.Equal(t, uint32(0), *s.System.FaultCode)
	require.Equal(t, uint64(5), *s.System.Warning) // 高位已被固件屏蔽
	require.Equal(t, uint32(0), *s.System.BmsWarning)
	require.InDelta(t, 43.0, *s.System.InverterTemperature, 0.0001) // 430×0.1
	require.InDelta(t, 35.0, *s.System.BoostTemperature, 0.0001)    // 350×0.1
	require.Nil(t, s.System.TransformerTemperature)                 // 语义性 null
	require.Nil(t, s.System.PVTemperature)
	require.InDelta(t, 373.5, *s.System.DCBusVoltage, 0.0001)       // 37350×0.01
	require.Equal(t, uint8(0), *s.System.BatteryOvercharge)

	// PV
	require.InDelta(t, 0.0, *s.PV.PV1Voltage, 0.0001)    // 60×0.1=6.0V <60V → 残压归 0
	require.InDelta(t, 5.0, *s.PV.Buck1Current, 0.0001)  // 50×0.1
	require.InDelta(t, 0.0, *s.PV.PV2Voltage, 0.0001)
	require.InDelta(t, 0.0, *s.PV.Buck2Current, 0.0001)
	require.InDelta(t, 6200.0, *s.PV.TotalPower, 0.0001) // 62000×0.1

	// AC（5000∉[450,650]，不触发 normalizeActualARMACOutputUnits，按 v2Scales 0.01 还原频率）
	require.InDelta(t, 230.0, *s.AC.Voltage, 0.0001)      // 2300×0.1
	require.InDelta(t, 50.0, *s.AC.Frequency, 0.0001)     // 5000×0.01
	require.InDelta(t, 6187.0, *s.AC.ActivePower, 0.0001) // 61870×0.1
	require.InDelta(t, 6500.0, *s.AC.ApparentPower, 0.0001)
	require.InDelta(t, 0.8, *s.AC.Current, 0.0001)        // 8×0.1
	require.InDelta(t, 100.0, *s.AC.LoadPercent, 0.0001)  // sys[9]=1000×0.1，界 0..120

	// Battery
	require.InDelta(t, 49.0, *s.Battery.Voltage, 0.0001)       // 4900×0.01
	require.InDelta(t, 0.0, *s.Battery.SOC, 0.0001)
	require.InDelta(t, -133.4, *s.Battery.Current, 0.0001)     // -1334×0.1，放电为负
	require.InDelta(t, 0.0, *s.Battery.ChargePower, 0.0001)
	require.InDelta(t, 6187.0, *s.Battery.DischargePower, 0.0001) // 61870×0.1

	// Energy
	require.InDelta(t, 0.3, *s.Energy.DailyPV, 0.0001) // eng[2]=3×0.1

	// Fan 全 0（0 是界内有效值，不置 null）
	require.InDelta(t, 0.0, *s.Fan.MPPTSpeed, 0.0001)
	require.InDelta(t, 0.0, *s.Fan.InvSpeed, 0.0001)

	// Diag / Sock 的 nil 语义
	require.Nil(t, s.Diag.InvCurrent)
	require.InDelta(t, 0.0, *s.Diag.ParallelChargeCurrent, 0.0001)
	require.Nil(t, s.Sock.PairedSocket)
	require.Nil(t, s.Sock.OnlineSocket)
	require.Nil(t, s.Sock.OnSocket)

	// 质量位：null + bms 缺组 → QualityPartial；全部数值在界内 → 不得置 QualityOutOfRange
	require.NotZero(t, s.QualityFlags&QualityPartial)
	require.Zero(t, s.QualityFlags&QualityOutOfRange)

	// battery_power 派生（deriveV2BatteryPower）：0 - 6187 = -6187（放电为负）
	power := mirrorDeriveV2BatteryPower(s)
	require.NotNil(t, power)
	require.InDelta(t, -6187.0, *power, 0.0001)
}

// l10App8ContractHeartbeatV2 是 2026-09-21 依 ARM 源码 App(8) Collector.c:ReadRunParam
// 重校量纲后，ESP 固件对实机 H1ZZX00139000038 同一组寄存器的预期输出
// （2026-09-22 依 DSP TxBuf 实源 UsartDsp.c 修正 chr[2]/sys[9] 两处结论）：
//   - ac[0] ACOutputVolt：VloadA 直传，线上即 0.1V（2310 = 231.0V；旧固件按 1V 再 ×10
//     得 23100，服务端判越界置 NULL——即现场「交流电压永远 --」的根因）；
//   - sys[9] LoadPercent：DSP PloadPercent×10 已是 0.1%，直传配服务器 scale=0.1
//     即还原百分比（实机 50 → 5.0%，与 ac 有功 347W/6kW≈5.8% 互证）；
//   - chr[2] ACChrCurr：IgridA 为 0.01A（DSP Igrid_rms_DP×100），线上契约 0.1A
//     需 ÷10（实机 chr=12 → 1.2A；09-21 曾按 "×10 后已 0.1A" 直传 124 得 12.4A，
//     与 347W/231V≈1.5A 负载电流矛盾，系量纲算术错误）；
//   - pv[0]：1V 量纲 ×10 不变，但界限放宽到 500V（PV 工作电压常见 200~450V）。
const l10App8ContractHeartbeatV2 = `{"v":2,"t":1789972771,"data":{"sys":[777,0,0,0,300,0,null,null,39190,50,0],"pv":[3500,0,0,0,0],"ac":[2310,4980,3470,0,0,40,0,0,0,0,0],"chr":[0,0,12],"bat":[5040,0,-69,0,null],"eng":[0,0,0,0,0,0,1192,0,1192,0,0,0,0,0],"fan":[0,0],"diag":[null,0,0],"sock":[null,null,null]}}`

func TestParseHeartbeatV2L10App8UnitsContract(t *testing.T) {
	s, err := ParseHeartbeatV2("H1ZZX00139000038", []byte(l10App8ContractHeartbeatV2), time.Unix(1789972771+60, 0))
	require.NoError(t, err)

	// PV：350V 工作电压必须落库（旧界 150V 会置 NULL + QualityOutOfRange）
	require.InDelta(t, 350.0, *s.PV.PV1Voltage, 0.0001) // 3500×0.1

	// AC：输出电压 231.0V（旧固件发布 23100 → NULL）；频率 49.80Hz 直传
	require.InDelta(t, 231.0, *s.AC.Voltage, 0.0001)  // 2310×0.1
	require.InDelta(t, 49.8, *s.AC.Frequency, 0.0001) // 4980×0.01
	require.InDelta(t, 347.0, *s.AC.ActivePower, 0.0001)
	// 负载百分比：sys[9]=50 直传 → 5.0%（旧固件 ×10 后为 50%）
	require.InDelta(t, 5.0, *s.AC.LoadPercent, 0.0001)
	// AC 充电电流：chr[2]=12 → 1.2A（IgridA 0.01A 契约 0.1A ÷10，见夹具头注释）
	require.InDelta(t, 1.2, *s.AC.ACChargeCurrent, 0.0001)

	// System / Battery：母线 391.9V（scale 0.01 两侧本就一致）、电池 50.40V 放电 6.9A
	require.InDelta(t, 391.9, *s.System.DCBusVoltage, 0.0001)
	require.InDelta(t, 30.0, *s.System.InverterTemperature, 0.0001)
	require.InDelta(t, 50.4, *s.Battery.Voltage, 0.0001)
	require.InDelta(t, -6.9, *s.Battery.Current, 0.0001)
	require.Nil(t, s.Battery.DischargePower) // 语义性 null

	// 全部数值在界内：不得置 QualityOutOfRange
	require.Zero(t, s.QualityFlags&QualityOutOfRange)
}

// l10App10DirectPassHeartbeatV2 是 2026-09-22 依 ARM 源码 App(10) Collector.c
// ReadRunParam（全字段直传 DSP 原值，删除旧版全部 ×10/×100 放大）+ ESP 固件
// 1.7.16 新换算的预期输出。物理场景与 TestParseHeartbeatV2FixedARMLayout
// （App(8) 时代实测锚点）完全相同——新旧两代固件对同一物理状态必须产出
// 可互换的线上值，服务端 scale/界无需任何变更：
//   sys: 温度直传（30.0℃/35.0℃，struct 0.1℃/1℃）；母线 3919(0.1V)×10=39190；
//        负载率 10(1%)×10=100
//   pv:  Vpv 350(1V)×10=3500；Buck 820(0.01A)÷10=82（App(10) 不再 ×100，
//        旧 >6.55A u16 回绕问题随之消失）；Ppv 1240(1W)×10=12400
//   ac:  输出 2300(0.1V) 直传、频率 500(0.1Hz)×10=5000；功率 1870/1875(1W)×10；
//        输出电流 852(0.01A)÷10=85；市电 231(1V)×10=2310、498(0.1Hz)×10=4980；
//        ACIn 347/350(1W)×10；旁路与 ACIn 同源
//   chr: ACChrWatt/VA=ACInWatt/VA 同源 ×10；ACChrCurr 12(1A)×10=120
//   bat: 电压 490(0.1V)×10=4900；SOC 直传；放电 6.9A → BatDischgCurr=69(0.1A)
//        直传取负；放电功率 618(1W)×10=6180
//   eng: ARM /360000(today)/原值(total) 透传
//   Transformer/PvTemp、InvCurr、sock：App(10) 未赋值（memset 恒 0）→ null
const l10App10DirectPassHeartbeatV2 = `{"v":2,"t":1789974000,"data":{"sys":[777,0,0,0,300,350,null,null,39190,100,0],"pv":[3500,82,0,0,12400],"ac":[2300,5000,18700,18750,85,2310,4980,3470,3500,3470,3500],"chr":[3470,3500,120],"bat":[4900,80,-69,0,6180],"eng":[0,0,0,0,0,0,1192,0,0,0,0,0,0,0],"fan":[0,0],"diag":[null,0,0],"sock":[null,null,null]}}`

func TestParseHeartbeatV2L10App10DirectPassContract(t *testing.T) {
	s, err := ParseHeartbeatV2("H1ZZX00139000038", []byte(l10App10DirectPassHeartbeatV2), time.Unix(1789974000+60, 0))
	require.NoError(t, err)

	// PV：350V 工作电压、Buck 8.2A（struct 820×0.01A ÷10）、总功率 1240W
	require.InDelta(t, 350.0, *s.PV.PV1Voltage, 0.0001)  // 3500×0.1
	require.InDelta(t, 8.2, *s.PV.Buck1Current, 0.0001)  // 82×0.1
	require.InDelta(t, 1240.0, *s.PV.TotalPower, 0.0001) // 12400×0.1

	// AC：输出 230.0V/50.00Hz（struct 0.1V 直传、0.1Hz×10）；功率 ×10；
	// 市电 231.0V/49.80Hz；旁路 = ACIn 同源
	require.InDelta(t, 230.0, *s.AC.Voltage, 0.0001)      // 2300×0.1
	require.InDelta(t, 50.0, *s.AC.Frequency, 0.0001)     // 5000×0.01
	require.InDelta(t, 1870.0, *s.AC.ActivePower, 0.0001) // 18700×0.1
	require.InDelta(t, 1875.0, *s.AC.ApparentPower, 0.0001)
	require.InDelta(t, 8.5, *s.AC.Current, 0.0001)        // 85×0.1（struct 852×0.01A ÷10）
	require.InDelta(t, 231.0, *s.AC.GridVoltage, 0.0001)  // 2310×0.1（struct 231×1V ×10）
	require.InDelta(t, 49.8, *s.AC.GridFrequency, 0.0001) // 4980×0.01（struct 498×0.1Hz ×10）
	require.InDelta(t, 347.0, *s.AC.ACInputPower, 0.0001)
	require.InDelta(t, 350.0, *s.AC.ACInputApparentPower, 0.0001)
	require.InDelta(t, 347.0, *s.AC.ACBypassPower, 0.0001)
	require.InDelta(t, 350.0, *s.AC.ACBypassApparentPower, 0.0001)

	// chr：与 ACIn 同源 ×10；充电电流 struct 1200×0.01A ÷10 = 12.0A（DSP Igrid 0.01A）
	require.InDelta(t, 347.0, *s.AC.ACChargePower, 0.0001)
	require.InDelta(t, 350.0, *s.AC.ACChargeApparentPower, 0.0001)
	require.InDelta(t, 12.0, *s.AC.ACChargeCurrent, 0.0001)

	// sys：温度直传/×10；母线 ×10；负载率 DSP 已 0.1% 直传 = 10.0%
	require.InDelta(t, 30.0, *s.System.InverterTemperature, 0.0001) // 300×0.1 直传
	require.InDelta(t, 35.0, *s.System.BoostTemperature, 0.0001)    // struct 35(1℃)×10=350×0.1
	require.InDelta(t, 391.9, *s.System.DCBusVoltage, 0.0001)       // 39190×0.01（struct 3919×0.1V ×10）
	require.InDelta(t, 10.0, *s.AC.LoadPercent, 0.0001)             // 100×0.1（struct 100×0.1% 直传）

	// bat：电压 ×10；SOC 直传；放电电流 0.1A 直传取负；放电功率 ×10
	require.InDelta(t, 49.0, *s.Battery.Voltage, 0.0001)         // 4900×0.01（struct 490×0.1V ×10）
	require.InDelta(t, 80.0, *s.Battery.SOC, 0.0001)
	require.InDelta(t, -6.9, *s.Battery.Current, 0.0001)         // -69×0.1 直传
	require.InDelta(t, 618.0, *s.Battery.DischargePower, 0.0001) // 6180×0.1（struct 618×1W ×10）

	// eng 透传 / 未赋值槽位 null 语义 / 风扇恒 0
	require.InDelta(t, 119.2, *s.Energy.DailyDischarge, 0.0001) // 1192×0.1（200kWh 日界内）
	require.Nil(t, s.System.TransformerTemperature)
	require.Nil(t, s.System.PVTemperature)
	require.Nil(t, s.Diag.InvCurrent)
	require.Nil(t, s.Sock.PairedSocket)
	require.InDelta(t, 0.0, *s.Fan.MPPTSpeed, 0.0001)

	// null（未赋值 + bms 缺组）→ Partial；全部数值在界内 → 不得 OutOfRange
	require.NotZero(t, s.QualityFlags&QualityPartial)
	require.Zero(t, s.QualityFlags&QualityOutOfRange)
}

// TestParseHeartbeatV2PVVoltageAbove500Rejected：500V 新界仍须拒绝超量程值
// （如 PV 接线异常/垃圾值），拒绝语义与旧界一致。
func TestParseHeartbeatV2PVVoltageAbove500Rejected(t *testing.T) {
	payload := []byte(`{"v":2,"t":1789972771,"data":{"sys":[777,0,0,0,300,0,null,null,0,0,0],"pv":[6300,0,0,0,0],"ac":[0,0,0,0,0,0,0,0,0,0,0],"chr":[0,0,0],"bat":[0,0,0,0,0],"eng":[0,0,0,0,0,0,0,0,0,0,0,0,0,0],"fan":[0,0],"diag":[null,0,0],"sock":[null,null,null]}}`)
	s, err := ParseHeartbeatV2("H1ZZX00139000038", payload, time.Unix(1789972771+60, 0))
	require.NoError(t, err)
	require.Nil(t, s.PV.PV1Voltage) // 630V > 500V → NULL
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
}

// TestParseHeartbeatV2DailyEnergyAbove200Rejected：2026-09-22 收紧能量组界限。
// 日组 ≤200kWh（6kW 机型 24h 物理天花板 144kWh 含余量）：实机 14:57 快照
// eng[4]=11901 → 1190.1kWh「日充电量」在零充电电流下照样落库展示（ARM
// Statistics 计数器走字脏值，today /360000 与 total 原值换算互相矛盾），
// 旧界 1e6 等于不设防；总组 ≤1e7kWh 拒 u32 溢出量级（u32max×0.1≈4.29e8）。
func TestParseHeartbeatV2DailyEnergyAbove200Rejected(t *testing.T) {
	payload := []byte(`{"v":2,"t":1789974000,"data":{"sys":[0,0,0,0,0,0,null,null,0,0,0],"pv":[0,0,0,0,0],"ac":[0,0,0,0,0,0,0,0,0,0,0],"chr":[0,0,0],"bat":[0,0,0,0,0],"eng":[0,0,0,0,11901,4294967295,0,0,0,0,0,0,0,0],"fan":[0,0],"diag":[null,0,0],"sock":[null,null,null]}}`)
	s, err := ParseHeartbeatV2("H1ZZX00139000038", payload, time.Unix(1789974000+60, 0))
	require.NoError(t, err)
	require.Nil(t, s.Energy.ACChargeDaily) // 1190.1kWh > 200 → NULL
	require.Nil(t, s.Energy.ACChargeTotal) // 4.29e8 > 1e7 → NULL
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)
}

// misalignedDirtyHeartbeatV2 是固件修复前现场实际发出的错位脏 payload（SN H1ZZX0023900002P，
// 与 TestParseHeartbeatV2RealDirtyHeartbeat 同一输入）：值未按 ARM 新版 200B 布局换算而错位，
// 作为修复前后的对照负例。
const misalignedDirtyHeartbeatV2 = `{"v":2,"t":1789887119,"data":{"sys":[265,0,0,0,0,0,null,null,0,37350,0],"pv":[6,0,0,0,0],"ac":[0,0,500,28180480,6187,0,0,10,325714148,0,0],"chr":[0,560726016,0],"bat":[0,0,0,4900,0],"eng":[20078,0,0,0,0,3,0,0,0,11907,0,11907,0,0],"fan":[0,100],"diag":[13340,21008,0],"sock":[0,0,0]}}`

// TestParseHeartbeatV2MisalignedOldLayout 负例：错位旧布局 payload 仍被解析（不拒包），
// 但越界值全为 nil 且 QualityOutOfRange 置位——服务端防线语义，修复后的固件输出
// 不应再触发（见 TestParseHeartbeatV2FixedARMLayout）。逐字段细节已由
// TestParseHeartbeatV2RealDirtyHeartbeat 覆盖，此处仅锁对照签名，避免重复断言膨胀。
func TestParseHeartbeatV2MisalignedOldLayout(t *testing.T) {
	s, err := ParseHeartbeatV2("H1ZZX0023900002P", []byte(misalignedDirtyHeartbeatV2), time.Unix(1789887119+60, 0))
	require.NoError(t, err)
	require.NotZero(t, s.QualityFlags&QualityOutOfRange)

	// 错位产生的越界值 → 全部 nil（落库 NULL / realtime null）
	require.Nil(t, s.AC.LoadPercent)           // 37350×0.1=3735% > 120（母线电压真值被挤到 sys[9]）
	require.Nil(t, s.AC.ApparentPower)         // 28180480×0.1 > 7500
	require.Nil(t, s.AC.Current)               // 6187×0.1 > 100
	require.Nil(t, s.AC.ACChargeApparentPower) // 560726016×0.1 > 7500
	require.Nil(t, s.Diag.InvCurrent)          // 13340×0.1 > 100
	require.Nil(t, s.Diag.ParallelChargeCurrent)
	require.Nil(t, s.Energy.GenDaily) // 20078×0.1=2007.8 > 200（日组界，2026-09-22 收紧）

	// 巧合落在界内的错位值照常保留（服务端只按 V2 位置定义 + 界校验，不做布局推断）
	require.Equal(t, uint32(265), *s.System.SysStatus)
	require.InDelta(t, 0.0, *s.System.DCBusVoltage, 0.0001) // sys[8]=0，真值 373.5 在 sys[9] 位置
	require.InDelta(t, 0.0, *s.PV.PV1Voltage, 0.0001)       // pv[0]=6 错位值 <60V → PV 残压归 0
	require.InDelta(t, 490.0, *s.Battery.ChargePower, 0.0001)
}
