package telemetry

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
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

func TestCMD08ConfirmedUnitsAndPopulatedSlots(t *testing.T) {
	e := summaryFixture(t)
	for off, value := range map[int]uint16{59: 65531, 61: 0, 63: 25, 65: 30, 73: 30, 75: 65531, 98: 560} {
		e.Bytes[off] = json.RawMessage(fmt.Sprint(value & 255))
		e.Bytes[off+1] = json.RawMessage(fmt.Sprint(value >> 8))
	}
	s, err := DecodeBatterySummary(e, time.Now())
	require.NoError(t, err)
	require.Equal(t, 1250.0, s["capacity_remain"])
	require.Equal(t, -25.0, s["mos_temp"])
	temps := s["cell_temperatures"].([]*float64)
	for i, want := range []float64{-5, 0, 25, 30} {
		require.Equal(t, want, *temps[i])
	}
	require.Equal(t, 30.0, s["max_cell_temp"])
	require.Equal(t, -5.0, s["min_cell_temp"])
	require.Equal(t, 56.0, s["charging_voltage"])
	require.Equal(t, 12.3, s["chg_request_current"])
	require.Equal(t, -50.0, s["chg_request_voltage"])
	require.Equal(t, float64(3000000000), s["total_chg_capacity"])
	*e.AgeMS = 120001
	s, err = DecodeBatterySummary(e, time.Now())
	require.NoError(t, err)
	require.Nil(t, s["charging_voltage"])
	require.Nil(t, s["chg_request_current"])
	require.Nil(t, s["max_cell_temp"])
	for _, temp := range s["cell_temperatures"].([]*float64) {
		require.Nil(t, temp)
	}
}

func TestV3MappedPVAndLoadAliases(t *testing.T) {
	var words []int
	require.NoError(t, json.Unmarshal([]byte(v3RunSample), &words))
	words[wordPpv1], words[wordPpv2] = 900, 250
	now := time.Unix(1791400000, 0)
	run, err := json.Marshal(words)
	require.NoError(t, err)
	s, err := ParseHeartbeatV3("TEST", v3Envelope(string(run), now.Unix()), now)
	require.NoError(t, err)
	require.NotNil(t, s.PV.PV1Power)
	require.Equal(t, 900.0, *s.PV.PV1Power)
	require.Equal(t, 250.0, *s.PV.PV2Power)
	require.Equal(t, s.PV.Buck1Current, s.PV.PV1Current)
	require.Equal(t, s.PV.Buck2Current, s.PV.PV2Current)
	require.Equal(t, s.System.BoostTemperature, s.System.MOSTemperature)
	require.Equal(t, s.Energy.OutputDaily, s.Energy.DailyLoad)
	require.Equal(t, s.Energy.OutputTotal, s.Energy.TotalLoad)
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
	require.Equal(t, 1250.0, s["capacity_remain"])
	require.Equal(t, 2000.0, s["capacity_full"])
	require.Equal(t, 10000.0, s["capacity_design"])
	require.Equal(t, -25.0, s["mos_temp"])
	require.Equal(t, 253.0, s["pcb_temp"])
	require.Equal(t, -125.0, s["env_temp"])
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
	require.Equal(t, 0.0, s["max_cell_temp"])
	require.Equal(t, 0.0, s["charging_voltage"])
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
	for _, skew := range []time.Duration{-4 * time.Minute, 4 * time.Minute} {
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
