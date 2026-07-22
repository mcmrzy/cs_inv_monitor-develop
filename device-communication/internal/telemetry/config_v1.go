package telemetry

import (
	"encoding/json"
	"fmt"
	"time"
)

type ReportedConfig struct {
	ProtocolVersion uint16
	EventTime       time.Time
	Revision        uint64
	Values          map[string]any
}

func ParseReportedConfig(payload []byte) (*ReportedConfig, error) {
	var raw struct {
		Version  uint16   `json:"v"`
		Time     int64    `json:"t"`
		Revision uint64   `json:"rev"`
		Inverter []int64  `json:"inv"`
		BMS      []int64  `json:"bms"`
		Parallel []*int64 `json:"parallel"`
	}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidHeartbeat, err)
	}
	if raw.Version != 1 {
		return nil, fmt.Errorf("%w: config version %d", ErrUnsupportedVersion, raw.Version)
	}
	if raw.Time <= 0 || len(raw.Inverter) != 8 || len(raw.BMS) != 6 || len(raw.Parallel) != 4 {
		return nil, fmt.Errorf("%w: invalid config array lengths or timestamp", ErrInvalidHeartbeat)
	}
	boolean := func(group string, index int, value int64) error {
		if value != 0 && value != 1 {
			return fmt.Errorf("%w: %s[%d] must be 0 or 1", ErrInvalidHeartbeat, group, index)
		}
		return nil
	}
	for _, i := range []int{0, 6, 7} {
		if err := boolean("inv", i, raw.Inverter[i]); err != nil {
			return nil, err
		}
	}
	for _, i := range []int{0, 1} {
		if err := boolean("bms", i, raw.BMS[i]); err != nil {
			return nil, err
		}
	}
	if raw.Inverter[1] < 0 || raw.Inverter[1] > 6200 || raw.Inverter[2] < 0 || raw.Inverter[2] > 6200 || raw.Inverter[3] < 0 || raw.Inverter[3] > 6200 {
		return nil, fmt.Errorf("%w: inverter power limit out of range", ErrInvalidHeartbeat)
	}
	if raw.Inverter[4] < 100 || raw.Inverter[4] > 500 || raw.Inverter[5] < 500 || raw.Inverter[5] > 1000 || raw.Inverter[5]-raw.Inverter[4] < 50 {
		return nil, fmt.Errorf("%w: invalid soc window", ErrInvalidHeartbeat)
	}
	if raw.Inverter[6] == 1 && raw.Inverter[7] == 1 {
		return nil, fmt.Errorf("%w: force charge and discharge are mutually exclusive", ErrInvalidHeartbeat)
	}
	values := map[string]any{
		"ac_enabled": raw.Inverter[0] == 1, "power_limit_w": raw.Inverter[1],
		"charge_limit_w": raw.Inverter[2], "discharge_limit_w": raw.Inverter[3],
		"soc_low_x10": raw.Inverter[4], "soc_high_x10": raw.Inverter[5],
		"force_charge": raw.Inverter[6] == 1, "force_discharge": raw.Inverter[7] == 1,
		"bms_charge_enabled": raw.BMS[0] == 1, "bms_discharge_enabled": raw.BMS[1] == 1,
		"max_charge_current_x10": raw.BMS[2], "max_discharge_current_x10": raw.BMS[3],
		"charge_voltage_x10": raw.BMS[4], "discharge_voltage_x10": raw.BMS[5],
		"parallel_mode": raw.Parallel[0], "parallel_role": raw.Parallel[1],
		"parallel_machine_id": raw.Parallel[2], "parallel_phase": raw.Parallel[3],
	}
	return &ReportedConfig{ProtocolVersion: 1, EventTime: time.Unix(raw.Time, 0).UTC(), Revision: raw.Revision, Values: values}, nil
}
