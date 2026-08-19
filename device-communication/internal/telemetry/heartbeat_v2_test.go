package telemetry

import (
	"bytes"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// V2.1 文档 6.4 完整示例：V2 位置数组 57 值（原始量纲，0.1/0.01 缩放，fan/diag/sock 为 V2.1 新增）。
const validHeartbeatV2 = `{"v":2,"t":1783000000,"data":{
  "sys":[2050,0,32,0,282,450,431,300,41000,624,0],
  "pv":[1450,82,0,0,12400],
  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
  "chr":[0,0,0],
  "bat":[5120,80,-255,0,13056],
  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765],
  "fan":[88,76],
  "diag":[880,45,68400000],
  "sock":[3,2,2]
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

	require.Len(t, s.DataHash, 64)
	require.JSONEq(t, validHeartbeatV2, string(s.RawEnvelope))
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

func TestParseHeartbeatV2PreservesOutOfRangeValue(t *testing.T) {
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
	require.InDelta(t, 999.9, *s.System.InverterTemperature, 0.0001) // 越界值保留（9999*0.1）
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
