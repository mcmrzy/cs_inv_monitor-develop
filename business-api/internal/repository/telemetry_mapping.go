package repository

import (
	"encoding/binary"
	"fmt"
	"math"
	"strings"
)

// Read compatibility for snapshots decoded before the confirmed CMD08 units.
// Reconstruct from retained bytes, never multiply an already corrected sample.
func normalizeLegacyBMSSummary(s map[string]interface{}) {
	if s["decoder_revision"] != nil || s["layout"] != float64(0) || s["bms_online"] != float64(1) {
		return
	}
	values, ok := s["raw_bytes"].([]interface{})
	if !ok || len(values) != 100 {
		return
	}
	b := make([]byte, 100)
	for i, raw := range values {
		n, ok := raw.(float64)
		if !ok || n < 0 || n > 255 || math.Trunc(n) != n {
			return
		}
		b[i] = byte(n)
	}
	u16 := func(off int) uint16 { return binary.LittleEndian.Uint16(b[off:]) }
	if b[0] == 0 || u16(7) == 255 {
		return
	}
	s16 := func(off int) float64 { return float64(int16(u16(off))) }
	u32 := func(off int) float64 { return float64(binary.LittleEndian.Uint32(b[off:])) }
	s["capacity_remain"], s["capacity_full"], s["capacity_design"] = float64(u16(11))/10, float64(u16(13))/10, u32(15)/10
	s["cell_temperatures"] = []interface{}{s16(59), s16(61), s16(63), s16(65)}
	s["max_cell_temp"], s["min_cell_temp"] = s16(73), s16(75)
	s["mos_temp"], s["pcb_temp"], s["env_temp"] = s16(77), s16(79), s16(81)
	s["charging_voltage"] = float64(u16(98)) / 10
	s["total_chg_capacity"], s["total_dsg_capacity"] = u32(85), u32(89)
	s["chg_request_current"], s["chg_request_voltage"] = float64(u16(93))/10, s16(95)/10
	s["decoder_revision"] = 1
}

// Dedicated BMS keys keep the BMS and DSP measurements distinguishable.
func attachBMSSummaryMetrics(row map[string]interface{}, s map[string]interface{}) {
	if s["bms_online"] != float64(1) && s["bms_online"] != 1 {
		return
	}
	for source, target := range map[string]string{
		"soc": "bms_soc", "soh": "bms_soh", "voltage": "bms_voltage", "current": "bms_current",
		"capacity_remain": "bms_capacity_remain", "capacity_full": "bms_capacity_full", "capacity_design": "bms_capacity_design",
		"cycle_count": "bms_cycle_count", "max_cell_temp": "bms_temp_max", "min_cell_temp": "bms_temp_min",
		"mos_temp": "bms_mos_temp", "pcb_temp": "bms_pcb_temp", "env_temp": "bms_env_temp",
		"max_cell_voltage": "bms_cell_voltage_max", "min_cell_voltage": "bms_cell_voltage_min",
		"charging_voltage": "bms_charging_voltage", "chg_request_current": "bms_charge_request_current", "chg_request_voltage": "bms_charge_request_voltage",
		"total_chg_capacity": "bms_total_charge_capacity", "total_dsg_capacity": "bms_total_discharge_capacity",
	} {
		if row[target] == nil && s[source] != nil {
			row[target] = s[source]
		}
	}
}

// The same projection is used before raw paging and bucket aggregation. It
// repairs omitted aliases without rewriting compressed historical chunks.
func telemetryProjectionSQL() string {
	return `to_jsonb(t) || jsonb_build_object(
		'pv1_current', COALESCE(t.pv1_current, CASE WHEN t.protocol_version=3 THEN (to_jsonb(t)->>'buck1_current')::numeric END),
		'pv2_current', COALESCE(t.pv2_current, CASE WHEN t.protocol_version=3 THEN (to_jsonb(t)->>'buck2_current')::numeric END),
		'pv1_power', COALESCE(t.pv1_power, ` + historicalV3PowerSQL("3") + `),
		'pv2_power', COALESCE(t.pv2_power, ` + historicalV3PowerSQL("4") + `),
		'mos_temperature', COALESCE(t.mos_temperature, CASE WHEN t.protocol_version=3 THEN (to_jsonb(t)->>'boost_temperature')::numeric END),
		'alarm_code', COALESCE(t.alarm_code::numeric, (to_jsonb(t)->>'warning')::numeric),
		'runtime_hours', COALESCE(t.runtime_hours::numeric, (to_jsonb(t)->>'work_time_total')::numeric / 3600),
		'daily_load_energy', COALESCE(t.daily_load_energy, (to_jsonb(t)->>'output_energy_daily')::numeric),
		'total_load_energy', COALESCE(t.total_load_energy, (to_jsonb(t)->>'output_energy_total')::numeric)) || ` + bmsHistoryProjectionSQL()
}

func bmsHistoryProjectionSQL() string {
	fields := []struct {
		source, target string
		legacyScale    float64
	}{
		{"soc", "bms_soc", 1}, {"soh", "bms_soh", 1}, {"voltage", "bms_voltage", 1}, {"current", "bms_current", 1},
		{"capacity_remain", "bms_capacity_remain", 100}, {"capacity_full", "bms_capacity_full", 100}, {"capacity_design", "bms_capacity_design", 100},
		{"cycle_count", "bms_cycle_count", 1}, {"max_cell_temp", "bms_temp_max", 1}, {"min_cell_temp", "bms_temp_min", 1},
		{"mos_temp", "bms_mos_temp", 10}, {"pcb_temp", "bms_pcb_temp", 10}, {"env_temp", "bms_env_temp", 10},
		{"max_cell_voltage", "bms_cell_voltage_max", 1}, {"min_cell_voltage", "bms_cell_voltage_min", 1},
		{"charging_voltage", "bms_charging_voltage", 1}, {"chg_request_current", "bms_charge_request_current", 1}, {"chg_request_voltage", "bms_charge_request_voltage", 1},
		{"total_chg_capacity", "bms_total_charge_capacity", 1}, {"total_dsg_capacity", "bms_total_discharge_capacity", 1},
	}
	parts := make([]string, 0, len(fields))
	for _, f := range fields {
		value := fmt.Sprintf(`CASE WHEN jsonb_typeof(t.bms_summary->'%s')='number' THEN (t.bms_summary->>'%s')::numeric END`, f.source, f.source)
		if f.legacyScale != 1 {
			value = fmt.Sprintf(`(%s) * CASE WHEN t.bms_summary->>'decoder_revision' IS NULL THEN %g ELSE 1 END`, value, f.legacyScale)
		}
		parts = append(parts, fmt.Sprintf(`'%s', COALESCE(NULLIF(to_jsonb(t)->'%s', 'null'::jsonb), to_jsonb(%s))`, f.target, f.target, value))
	}
	return `CASE WHEN t.bms_summary->>'layout'='0' AND t.bms_summary->>'bms_online'='1' THEN jsonb_strip_nulls(jsonb_build_object(` + strings.Join(parts, ",") + `)) ELSE '{}'::jsonb END`
}

func historicalV3PowerSQL(word string) string {
	value := "t.raw_envelope #>> '{data,run," + word + "}'"
	return `CASE WHEN t.protocol_version=3 AND
		CASE WHEN jsonb_typeof(t.raw_envelope #> '{data,run}')='array'
		THEN jsonb_array_length(t.raw_envelope #> '{data,run}')=87 ELSE false END
		AND ` + value + ` ~ '^[0-9]{1,4}$' THEN
		CASE WHEN (` + value + `)::numeric <= 7500 THEN (` + value + `)::numeric END END`
}
