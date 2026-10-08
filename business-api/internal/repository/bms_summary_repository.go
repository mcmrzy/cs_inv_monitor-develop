package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
)

// GetRealtimeData adds the last durable CMD08 snapshot even after Redis expiry.
func (r *DeviceRepository) GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error) {
	result, err := r.getRealtimeData(ctx, sn)
	if err != nil {
		return nil, err
	}
	if cached, ok := result["bms_summary"].(map[string]interface{}); ok {
		markBMSSummaryFreshness(cached, time.Now())
	}
	var raw []byte
	err = r.db.QueryRow(ctx, `SELECT bms_summary FROM device_telemetry_3min
		WHERE device_sn=$1 AND bms_summary IS NOT NULL
		ORDER BY received_at DESC, event_time DESC LIMIT 1`, sn).Scan(&raw)
	if err == pgx.ErrNoRows {
		return result, nil
	}
	if err != nil {
		// Optional BMS storage must not discard available inverter telemetry.
		return result, nil
	}
	var summary map[string]interface{}
	if err := json.Unmarshal(raw, &summary); err != nil {
		return result, nil
	}
	markBMSSummaryFreshness(summary, time.Now())
	result["bms_summary"] = summary
	return result, nil
}

func markBMSSummaryFreshness(summary map[string]interface{}, now time.Time) {
	expires, _ := summary["expires_at"].(string)
	deadline, err := time.Parse(time.RFC3339Nano, expires)
	if err != nil || now.After(deadline) || deadline.After(now.Add(215*time.Second)) {
		summary["bms_online"] = 0
		for _, key := range []string{"soc", "soh", "voltage", "current", "capacity_remain", "capacity_full", "capacity_design", "cycle_count", "max_cell_voltage", "min_cell_voltage", "mos_temp", "pcb_temp", "env_temp"} {
			summary[key] = nil
		}
		summary["cell_voltages"] = make([]*float64, 16)
	}
}
