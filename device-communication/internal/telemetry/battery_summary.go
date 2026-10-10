package telemetry

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"time"
)

// Bytes are JSON numbers rather than Go []byte's base64 representation.
type BatterySummaryEnvelope struct {
	Layout *uint16           `json:"layout"`
	Bytes  []json.RawMessage `json:"bytes"`
	AgeMS  *uint32           `json:"age_ms"`
}

// DecodeBatterySummary follows the packed 100-byte BattSumDef CMD08 layout.
// Units follow the 2026-10-08 CMD08 layout table. Raw fields remain additive.
func DecodeBatterySummary(e *BatterySummaryEnvelope, receivedAt time.Time) (map[string]any, error) {
	if e.Layout == nil || *e.Layout != 0 || e.AgeMS == nil || len(e.Bytes) != 100 {
		return nil, fmt.Errorf("expected layout 0, age_ms and 100 bytes")
	}
	b := make([]byte, 100)
	rawBytes := make([]int, 100)
	for i, value := range e.Bytes {
		var n uint8
		if err := json.Unmarshal(value, &n); err != nil || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return nil, fmt.Errorf("byte %d must be an integer in [0,255]", i)
		}
		b[i] = n
		rawBytes[i] = int(n)
	}
	u16 := func(off int) uint16 { return binary.LittleEndian.Uint16(b[off:]) }
	s16 := func(off int) int16 { return int16(u16(off)) }
	u32 := func(off int) uint32 { return binary.LittleEndian.Uint32(b[off:]) }
	online := 1
	if b[0] == 0 || u16(7) == 255 || *e.AgeMS > 120000 {
		online = 0
	}
	cells := make([]*float64, 16)
	for i := range cells {
		if v := u16(27 + i*2); v != 0 && online == 1 {
			value := float64(v)
			cells[i] = &value
		}
	}
	var soc, soh *float64
	temps := make([]*float64, 4)
	if online == 1 {
		for i := range temps {
			value := float64(s16(59 + i*2))
			temps[i] = &value
		}
	}
	if online == 1 && u16(7) <= 1000 {
		value := float64(u16(7)) / 10
		soc = &value
	}
	if online == 1 && u16(9) <= 1000 {
		value := float64(u16(9)) / 10
		soh = &value
	}
	result := map[string]any{
		"layout": 0, "decoder_revision": 1, "bms_online": online, "age_ms": *e.AgeMS,
		"reported_at": receivedAt.UTC().Format(time.RFC3339Nano),
		// Normal heartbeats are 180s apart, with 30s delivery margin.
		"expires_at": receivedAt.Add(210 * time.Second).UTC().Format(time.RFC3339Nano),
		"updated_at": receivedAt.Add(-time.Duration(*e.AgeMS) * time.Millisecond).UTC().Format(time.RFC3339Nano),
		"raw_bytes":  rawBytes, "battery_count": b[0],
		"voltage": float64(u16(1)) / 100, "current": float64(int32(u32(3))) / 100,
		"soc": soc, "soh": soh, "soc_raw": u16(7), "soh_raw": u16(9),
		"capacity_remain": float64(u16(11)) / 10, "capacity_full": float64(u16(13)) / 10,
		"capacity_design": float64(u32(15)) / 10,
		"warning_flag":    u16(19), "protection_flag": u16(21), "status_fault_flag": u16(23),
		"balance_status": u16(25), "cell_voltages": cells,
		"cell_temperatures": temps, "cycle_count": u16(67),
		"max_cell_voltage": u16(69), "min_cell_voltage": u16(71),
		"max_cell_temp": float64(s16(73)), "min_cell_temp": float64(s16(75)),
		"mos_temp": float64(s16(77)), "pcb_temp": float64(s16(79)),
		"env_temp":     float64(s16(81)),
		"battery_mode": b[83], "battery_status": b[84],
		"total_chg_capacity_raw": u32(85), "total_dsg_capacity_raw": u32(89),
		"chg_request_current_raw": u16(93), "chg_request_voltage_raw": s16(95),
		"total_chg_capacity": float64(u32(85)), "total_dsg_capacity": float64(u32(89)),
		"chg_request_current": float64(u16(93)) / 10, "chg_request_voltage": float64(s16(95)) / 10,
		"system_mode": b[97], "charging_voltage": float64(u16(98)) / 10,
	}
	if online == 0 {
		for _, key := range []string{"voltage", "current", "capacity_remain", "capacity_full", "capacity_design", "cycle_count", "max_cell_voltage", "min_cell_voltage", "mos_temp", "pcb_temp", "env_temp", "max_cell_temp", "min_cell_temp", "charging_voltage", "total_chg_capacity", "total_dsg_capacity", "chg_request_current", "chg_request_voltage"} {
			result[key] = nil
		}
	}
	return result, nil
}
