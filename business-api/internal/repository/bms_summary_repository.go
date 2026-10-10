package repository

import (
	"context"
	"encoding/json"
	"inv-api-server/internal/model"
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
		normalizeLegacyBMSSummary(cached)
		markBMSSummaryFreshness(cached, time.Now())
	}
	var raw []byte
	err = r.db.QueryRow(ctx, `SELECT bms_summary FROM device_telemetry_3min
		WHERE device_sn=$1 AND bms_summary IS NOT NULL
		ORDER BY received_at DESC, event_time DESC LIMIT 1`, sn).Scan(&raw)
	if err == pgx.ErrNoRows {
		if cached, ok := result["bms_summary"].(map[string]interface{}); ok {
			attachBMSSummaryMetrics(result, cached)
		}
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
	normalizeLegacyBMSSummary(summary)
	markBMSSummaryFreshness(summary, time.Now())
	result["bms_summary"] = summary
	attachBMSSummaryMetrics(result, summary)
	return result, nil
}

// Batch lookup is restricted to the already-authorized device page.
func (r *DeviceRepository) attachDeviceListBMS(ctx context.Context, devices []*model.Device) {
	sns := make([]string, 0, len(devices))
	for _, d := range devices {
		sns = append(sns, d.SN)
	}
	for sn, summary := range r.batchBMSSummaries(ctx, sns) {
		for _, d := range devices {
			if d.SN == sn {
				d.BMSSummary = summary
				break
			}
		}
	}
}

func (r *DeviceRepository) batchBMSSummaries(ctx context.Context, sns []string) map[string]map[string]interface{} {
	result := make(map[string]map[string]interface{})
	if len(sns) == 0 {
		return result
	}
	rows, err := r.db.Query(ctx, `SELECT DISTINCT ON (device_sn) device_sn,bms_summary
		FROM device_telemetry_3min WHERE device_sn=ANY($1) AND bms_summary IS NOT NULL
		ORDER BY device_sn,received_at DESC,event_time DESC`, sns)
	if err != nil {
		return result
	}
	defer rows.Close()
	now := time.Now()
	for rows.Next() {
		var sn string
		var raw []byte
		if rows.Scan(&sn, &raw) != nil {
			continue
		}
		var summary map[string]interface{}
		if json.Unmarshal(raw, &summary) != nil {
			continue
		}
		normalizeLegacyBMSSummary(summary)
		markBMSSummaryFreshness(summary, now)
		result[sn] = summary
	}
	return result
}

func markBMSSummaryFreshness(summary map[string]interface{}, now time.Time) {
	expires, _ := summary["expires_at"].(string)
	deadline, err := time.Parse(time.RFC3339Nano, expires)
	if err != nil || now.After(deadline) || deadline.After(now.Add(215*time.Second)) {
		summary["bms_online"] = 0
		for _, key := range []string{"soc", "soh", "voltage", "current", "capacity_remain", "capacity_full", "capacity_design", "cycle_count", "max_cell_voltage", "min_cell_voltage", "mos_temp", "pcb_temp", "env_temp", "max_cell_temp", "min_cell_temp", "charging_voltage", "total_chg_capacity", "total_dsg_capacity", "chg_request_current", "chg_request_voltage"} {
			summary[key] = nil
		}
		summary["cell_voltages"] = make([]*float64, 16)
		summary["cell_temperatures"] = make([]*float64, 4)
	}
}
