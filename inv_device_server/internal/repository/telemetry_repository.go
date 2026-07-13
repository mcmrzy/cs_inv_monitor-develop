package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"inv-device-server/internal/telemetry"
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

func (r *DeviceRepository) GetDeviceCellCount(ctx context.Context, sn string) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(dm.cell_count, 0)
		FROM devices d
		LEFT JOIN device_models dm ON dm.id = d.model_id
		WHERE d.sn = $1`, sn).Scan(&count)
	return count, err
}

// SaveTelemetryV2 atomically persists the two fact rows. PostgreSQL triggers
// maintain latest state and day rollups from these already validated columns.
func (r *DeviceRepository) SaveTelemetryV2(ctx context.Context, s *telemetry.Sample) error {
	row, err := json.Marshal(sampleRow(s))
	if err != nil {
		return err
	}
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

	_, err = tx.Exec(ctx, `
		INSERT INTO device_telemetry_3min
		SELECT (jsonb_populate_record(NULL::device_telemetry_3min, $1::jsonb)).*
		ON CONFLICT (device_sn, event_time) DO NOTHING`, row)
	if err != nil {
		return fmt.Errorf("insert telemetry v2: %w", err)
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO device_cell_samples(device_sn,event_time,sequence_no,voltages,temperatures,quality_flags,is_abnormal,received_at)
		VALUES($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7,$8)
		ON CONFLICT(device_sn,event_time) DO NOTHING`, s.DeviceSN, s.EventTime, s.Sequence, voltages, temperatures,
		s.QualityFlags, s.QualityFlags&(telemetry.QualityOutOfRange|telemetry.QualityInconsistent) != 0, s.ReceivedAt); err != nil {
		return fmt.Errorf("insert cell sample: %w", err)
	}
	return tx.Commit(ctx)
}

func sampleRow(s *telemetry.Sample) map[string]any {
	return map[string]any{
		"device_sn": s.DeviceSN, "protocol_version": s.ProtocolVersion, "sequence_no": s.Sequence,
		"event_time": s.EventTime, "received_at": s.ReceivedAt, "updated_at": s.ReceivedAt, "quality_flags": s.QualityFlags,
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
		"pv1_voltage": s.PV.PV1Voltage, "pv1_current": s.PV.PV1Current, "pv1_power": s.PV.PV1Power,
		"pv1_voltage_max": s.PV.PV1VoltageMax, "pv1_power_max": s.PV.PV1PowerMax,
		"pv2_voltage": s.PV.PV2Voltage, "pv2_current": s.PV.PV2Current, "pv2_power": s.PV.PV2Power,
		"pv2_voltage_max": s.PV.PV2VoltageMax, "pv2_power_max": s.PV.PV2PowerMax,
		"pv_total_power": s.PV.TotalPower, "mppt_state": s.PV.MPPTState,
		"work_state": s.System.WorkState, "fault_code": s.System.FaultCode, "alarm_code": s.System.AlarmCode,
		"inverter_temperature": s.System.InverterTemperature, "mos_temperature": s.System.MOSTemperature,
		"ambient_temperature": s.System.AmbientTemperature, "dc_bus_voltage": s.System.DCBusVoltage,
		"runtime_hours": s.System.RuntimeHours, "fan_speed_percent": s.System.FanSpeedPercent,
		"efficiency":      s.System.Efficiency,
		"daily_pv_energy": s.Energy.DailyPV, "total_pv_energy": s.Energy.TotalPV,
		"daily_charge_energy": s.Energy.DailyCharge, "total_charge_energy": s.Energy.TotalCharge,
		"daily_discharge_energy": s.Energy.DailyDischarge, "total_discharge_energy": s.Energy.TotalDischarge,
		"daily_load_energy": s.Energy.DailyLoad, "total_load_energy": s.Energy.TotalLoad,
	}
}
