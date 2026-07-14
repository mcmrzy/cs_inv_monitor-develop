package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-device-server/internal/telemetry"

	"github.com/jackc/pgx/v5"
)

// CheckTelemetryDerivedSchema prevents a direct-cutover binary from consuming
// heartbeat data before the database-side derivative maintenance is installed.
func (r *DeviceRepository) CheckTelemetryDerivedSchema(ctx context.Context) error {
	var ready bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=25)
			AND EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
				WHERE c.relname='device_telemetry_3min' AND t.tgname='trg_telemetry_v2_derived' AND t.tgenabled<>'D')
			AND EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
				WHERE c.relname='device_cell_samples' AND t.tgname='trg_latest_cells' AND t.tgenabled<>'D')`).Scan(&ready)
	if err != nil {
		return fmt.Errorf("check PostgreSQL telemetry derivatives: %w", err)
	}
	if !ready {
		return fmt.Errorf("database migration 025 and telemetry derivative triggers are required")
	}
	return nil
}

func (r *DeviceRepository) GetDeviceCellCounts(ctx context.Context, sn string) (int, int, error) {
	var cellCount, tempSensorCount int
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(dm.cell_count, d.cell_count, 0), COALESCE(dm.temp_sensor_count, d.temp_sensor_count, 0)
		FROM devices d
		LEFT JOIN device_models dm ON dm.id = d.model_id
		WHERE d.sn = $1`, sn).Scan(&cellCount, &tempSensorCount)
	return cellCount, tempSensorCount, err
}

func (r *DeviceRepository) SaveIngestError(ctx context.Context, sn, topic string, payload []byte, code, detail string) error {
	_, err := r.db.Exec(ctx, `INSERT INTO device_ingest_errors(device_sn,topic,raw_payload,error_code,error_detail,received_at)
		VALUES(NULLIF($1,''),$2,$3,$4,$5,NOW())`, sn, topic, payload, code, detail)
	return err
}

// SaveTelemetryV2 atomically persists the two fact rows. PostgreSQL triggers
// maintain latest state and day rollups from these already validated columns.
func (r *DeviceRepository) SaveTelemetryV2(ctx context.Context, s *telemetry.Sample) error {
	voltages, err := json.Marshal(s.Cells.Voltages)
	if err != nil {
		return err
	}
	temperatures, err := json.Marshal(s.Cells.Temperatures)
	if err != nil {
		return err
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, s.DeviceSN); err != nil {
		return err
	}
	var latestTime time.Time
	if err = tx.QueryRow(ctx, `SELECT event_time FROM device_latest_state WHERE device_sn=$1`, s.DeviceSN).Scan(&latestTime); err != nil && err != pgx.ErrNoRows {
		return err
	}
	if err == nil && s.EventTime.Before(latestTime) {
		s.QualityFlags |= telemetry.QualityOutOfOrder
	}
	row, err := json.Marshal(sampleRow(s))
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO device_telemetry_3min
		SELECT (jsonb_populate_record(NULL::device_telemetry_3min, $1::jsonb)).*
		ON CONFLICT (device_sn, event_time, data_hash) DO NOTHING`, row)
	if err != nil {
		return fmt.Errorf("insert telemetry v2: %w", err)
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO device_cell_samples(device_sn,event_time,sequence_no,data_hash,voltages,temperatures,quality_flags,is_abnormal,received_at)
		VALUES($1,$2,$3,$4,$5::jsonb,$6::jsonb,$7,$8,$9)
		ON CONFLICT(device_sn,event_time,data_hash) DO NOTHING`, s.DeviceSN, s.EventTime, s.Sequence, s.DataHash, voltages, temperatures,
		s.QualityFlags, s.QualityFlags&telemetry.QualityOutOfRange != 0, s.ReceivedAt); err != nil {
		return fmt.Errorf("insert cell sample: %w", err)
	}
	return tx.Commit(ctx)
}

func sampleRow(s *telemetry.Sample) map[string]any {
	return map[string]any{
		"device_sn": s.DeviceSN, "protocol_version": s.ProtocolVersion, "sequence_no": s.Sequence,
		"event_time": s.EventTime, "received_at": s.ReceivedAt, "quality_flags": s.QualityFlags,
		"topic": "heartbeat", "data_hash": s.DataHash, "raw_envelope": json.RawMessage(s.RawEnvelope),
		"ac_voltage": s.AC.Voltage, "ac_current": s.AC.Current, "ac_active_power": s.AC.ActivePower,
		"ac_apparent_power": s.AC.ApparentPower, "ac_frequency": s.AC.Frequency,
		"ac_power_factor": s.AC.PowerFactor, "load_percent": s.AC.LoadPercent, "ac_voltage_thd": s.AC.VoltageTHD,
		"battery_soc": s.Battery.SOC, "battery_soh": s.Battery.SOH, "battery_voltage": s.Battery.Voltage,
		"battery_current": s.Battery.Current, "battery_power": s.Battery.Power,
		"battery_capacity_remain": s.Battery.CapacityRemain, "battery_capacity_total": s.Battery.CapacityTotal,
		"battery_cycle_count": s.Battery.CycleCount, "battery_temp_max": s.Battery.TempMax,
		"battery_temp_min": s.Battery.TempMin, "cell_voltage_max": s.Battery.CellVoltageMax,
		"cell_voltage_min": s.Battery.CellVoltageMin, "cell_voltage_diff": s.Battery.CellVoltageDiff,
		"battery_state": s.Battery.State, "battery_protect_status": s.Battery.ProtectStatus,
		"bms_fault_code": s.Battery.FaultCode, "max_charge_current": s.Battery.MaxChargeCurrent,
		"max_discharge_current": s.Battery.MaxDischargeCurrent, "charge_voltage_ref": s.Battery.ChargeVoltageRef,
		"discharge_cutoff_voltage": s.Battery.DischargeCutoffVoltage, "battery_temperature": s.Battery.Temperature,
		"charge_request_current_x10": s.Battery.ChargeRequestCurrentX10, "charge_request_voltage_x10": s.Battery.ChargeRequestVoltageX10,
		"pv1_voltage": s.PV.PV1Voltage, "pv1_current": s.PV.PV1Current, "pv1_power": s.PV.PV1Power,
		"pv2_voltage": s.PV.PV2Voltage, "pv2_current": s.PV.PV2Current, "pv2_power": s.PV.PV2Power,
		"pv_total_power": s.PV.TotalPower, "mppt_state": s.PV.MPPTState,
		"work_state": s.System.WorkState, "fault_code": s.System.FaultCode, "alarm_code": s.System.AlarmCode,
		"inverter_temperature": s.System.InverterTemperature, "mos_temperature": s.System.MOSTemperature,
		"ambient_temperature": s.System.AmbientTemperature, "dc_bus_voltage": s.System.DCBusVoltage,
		"runtime_hours": s.System.RuntimeHours, "fan_speed_percent": s.System.FanSpeedPercent,
		"efficiency": s.System.Efficiency, "system_mode": s.System.SystemMode,
		"daily_pv_energy": s.Energy.DailyPV, "total_pv_energy": s.Energy.TotalPV,
		"daily_charge_energy": s.Energy.DailyCharge, "total_charge_energy": s.Energy.TotalCharge,
		"daily_discharge_energy": s.Energy.DailyDischarge, "total_discharge_energy": s.Energy.TotalDischarge,
		"daily_load_energy": s.Energy.DailyLoad, "total_load_energy": s.Energy.TotalLoad,
		"total_charge_capacity": s.Energy.TotalChargeCapacity, "total_discharge_capacity": s.Energy.TotalDischargeCapacity,
		"total_charge_time": s.Energy.TotalChargeTime, "total_discharge_time": s.Energy.TotalDischargeTime,
	}
}
