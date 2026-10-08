package telemetry

import (
	"encoding/binary"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func summaryFixture(t *testing.T) *BatterySummaryEnvelope {
	t.Helper()
	b := make([]int, 100)
	data := make([]byte, 100)
	data[0] = 2
	for off, value := range map[int]uint16{1: 5123, 7: 875, 9: 990, 11: 12500, 13: 20000, 19: 32769, 21: 64, 23: 0x0d01, 25: 3, 27: 3300, 57: 3400, 67: 321, 69: 3400, 71: 3300, 77: 65511, 79: 253, 81: 65411, 93: 123, 95: 65036} {
		binary.LittleEndian.PutUint16(data[off:], value)
	}
	for off, value := range map[int]uint32{3: 4294967173, 15: 100000, 85: 3000000000, 89: 4000000000} {
		binary.LittleEndian.PutUint32(data[off:], value)
	}
	data[83], data[84], data[97] = 3, 4, 5
	for i := range b {
		b[i] = int(data[i])
	}
	payload, err := json.Marshal(map[string]any{"layout": 0, "age_ms": 3000, "bytes": b})
	require.NoError(t, err)
	var e BatterySummaryEnvelope
	require.NoError(t, json.Unmarshal(payload, &e))
	return &e
}

func TestBatterySummaryFieldsAndSignedValues(t *testing.T) {
	now := time.Unix(1791400000, 0).UTC()
	e := summaryFixture(t)
	s, err := DecodeBatterySummary(e, now)
	require.NoError(t, err)
	require.Equal(t, 1, s["bms_online"])
	require.InDelta(t, 51.23, s["voltage"], 1e-9)
	require.InDelta(t, -1.23, s["current"], 1e-9)
	require.InDelta(t, 87.5, *s["soc"].(*float64), 1e-9)
	require.InDelta(t, 99, *s["soh"].(*float64), 1e-9)
	require.Equal(t, 12.5, s["capacity_remain"])
	require.Equal(t, 20.0, s["capacity_full"])
	require.Equal(t, 100.0, s["capacity_design"])
	require.Equal(t, -2.5, s["mos_temp"])
	require.Equal(t, 25.3, s["pcb_temp"])
	require.Equal(t, -12.5, s["env_temp"])
	require.Equal(t, int16(-500), s["chg_request_voltage_raw"])
	require.Equal(t, uint32(3000000000), s["total_chg_capacity_raw"])
	require.Equal(t, uint32(4000000000), s["total_dsg_capacity_raw"])
	require.Equal(t, uint16(32769), s["warning_flag"])
	require.Equal(t, uint16(64), s["protection_flag"])
	require.Equal(t, uint16(0x0d01), s["status_fault_flag"])
	cells := s["cell_voltages"].([]*float64)
	require.Len(t, cells, 16)
	require.Equal(t, 3300.0, *cells[0])
	require.Nil(t, cells[1])
	require.Equal(t, 3400.0, *cells[15])
	require.Nil(t, s["max_cell_temp"])
	require.Nil(t, s["charging_voltage"])
	require.Equal(t, now.Add(-3*time.Second).Format(time.RFC3339Nano), s["updated_at"])
	require.Equal(t, now.Format(time.RFC3339Nano), s["reported_at"])
	require.Equal(t, now.Add(210*time.Second).Format(time.RFC3339Nano), s["expires_at"])
}

func TestBatterySummaryOfflineAndInvalidEnvelope(t *testing.T) {
	for _, change := range []func(*BatterySummaryEnvelope){
		func(e *BatterySummaryEnvelope) { *e.AgeMS = 120001 },
		func(e *BatterySummaryEnvelope) { e.Bytes[0] = json.RawMessage("0") },
		func(e *BatterySummaryEnvelope) {
			e.Bytes[7] = json.RawMessage("255")
			e.Bytes[8] = json.RawMessage("0")
		},
	} {
		e := summaryFixture(t)
		change(e)
		s, err := DecodeBatterySummary(e, time.Now())
		require.NoError(t, err)
		require.Equal(t, 0, s["bms_online"])
		require.Nil(t, s["voltage"])
		require.Nil(t, s["soc"].(*float64))
	}
	for _, value := range []string{"null", "-1", "256", "1.5", "\"1\""} {
		e := summaryFixture(t)
		e.Bytes[3] = json.RawMessage(value)
		_, err := DecodeBatterySummary(e, time.Now())
		require.Error(t, err)
	}
	e := summaryFixture(t)
	e.Bytes = e.Bytes[:99]
	_, err := DecodeBatterySummary(e, time.Now())
	require.Error(t, err)
	e = summaryFixture(t)
	*e.Layout = 1
	_, err = DecodeBatterySummary(e, time.Now())
	require.Error(t, err)
}

func TestHeartbeatV3BatterySummaryOptionalAndStrict(t *testing.T) {
	now := time.Unix(1791400000, 0)
	var env map[string]any
	require.NoError(t, json.Unmarshal(v3Envelope(v3RunSample, now.Unix()), &env))
	data := env["data"].(map[string]any)
	data["bms_summary"] = summaryFixture(t)
	payload, err := json.Marshal(env)
	require.NoError(t, err)
	s, err := ParseHeartbeatV3("TEST", payload, now)
	require.NoError(t, err)
	require.NotNil(t, s.BMSSummary)
	require.Equal(t, 49.0, *s.Battery.Voltage)
	data["bms_summary"] = map[string]any{"layout": 0, "bytes": []int{1}, "age_ms": 0}
	payload, err = json.Marshal(env)
	require.NoError(t, err)
	_, err = ParseHeartbeatV3("TEST", payload, now)
	require.Error(t, err)
}

func TestHeartbeatV3BatterySummaryExpiryUsesServerClock(t *testing.T) {
	now := time.Unix(1791400000, 0).UTC()
	for _, skew := range []time.Duration{-4*time.Minute, 4*time.Minute} {
		var env map[string]any
		require.NoError(t, json.Unmarshal(v3Envelope(v3RunSample, now.Add(skew).Unix()), &env))
		env["data"].(map[string]any)["bms_summary"] = summaryFixture(t)
		payload, err := json.Marshal(env)
		require.NoError(t, err)
		s, err := ParseHeartbeatV3("TEST", payload, now)
		require.NoError(t, err)
		require.Equal(t, now.Add(210*time.Second).Format(time.RFC3339Nano), s.BMSSummary["expires_at"])
		require.Equal(t, now.Format(time.RFC3339Nano), s.BMSSummary["reported_at"])
	}
}
