package telemetry

import (
	"bytes"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// 文档 4.3 完整示例：V2 位置数组 50 值（原始量纲，0.1/0.01 缩放）。
const validHeartbeatV2 = `{"v":2,"t":1783000000,"data":{
  "sys":[2050,0,0,0,282,450,431,300,5120,624,0],
  "pv":[1450,82,0,0,12400],
  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
  "chr":[0,0,0],
  "bat":[5120,785,-255,0,13056,0],
  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]
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
	require.Equal(t, uint64(0), *s.System.Warning)
	require.Equal(t, uint32(0), *s.System.BmsWarning)
	require.InDelta(t, 28.2, *s.System.InverterTemperature, 0.0001)
	require.InDelta(t, 45.0, *s.System.BoostTemperature, 0.0001)
	require.InDelta(t, 43.1, *s.System.TransformerTemperature, 0.0001)
	require.InDelta(t, 30.0, *s.System.PVTemperature, 0.0001)
	require.InDelta(t, 51.2, *s.System.DCBusVoltage, 0.0001)
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

	// bat
	require.InDelta(t, 51.2, *s.Battery.Voltage, 0.0001)
	require.InDelta(t, 78.5, *s.Battery.SOC, 0.0001)
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

	require.Len(t, s.DataHash, 64)
	require.JSONEq(t, validHeartbeatV2, string(s.RawEnvelope))
}

func TestParseHeartbeatV2RejectsArrayLength(t *testing.T) {
	payload := []byte(`{"v":2,"t":1,"data":{"sys":[],"pv":[],"ac":[],"chr":[],"bat":[],"eng":[]}}`)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
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
	  "bat":[null,null,null,null,null,null],
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
	  "bat":[5120,785,-255,0,13056,0],
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
	  "bat":[0,0,0,0,0,0],
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
	  "bat":[5120,785,-255,0,13056,0],
	  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]
	}}`)
	_, err := ParseHeartbeatV2("sn", payload, time.Now())
	require.ErrorIs(t, err, ErrInvalidHeartbeat)
}

func TestParseHeartbeatV2BatteryOverchargeFallbackFromBat(t *testing.T) {
	// sys[10] 缺失（null），bat[5]=1 同源补充
	payload := []byte(`{"v":2,"t":1783000000,"data":{
	  "sys":[2050,0,0,0,282,450,431,300,5120,624,null],
	  "pv":[1450,82,0,0,12400],
	  "ac":[2205,5002,18703,18756,852,0,0,0,0,0,0],
	  "chr":[0,0,0],
	  "bat":[5120,785,-255,0,13056,1],
	  "eng":[0,0,1250,45678,0,0,1305,23456,0,0,0,0,1870,98765]
	}}`)
	s, err := ParseHeartbeatV2("sn", payload, time.Unix(1783000005, 0))
	require.NoError(t, err)
	require.Equal(t, uint8(1), *s.System.BatteryOvercharge)
	require.NotZero(t, s.QualityFlags&QualityPartial)
}
