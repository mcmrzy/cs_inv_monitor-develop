package repository

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// BatteryProfile 电池配置模板
type BatteryProfile struct {
	ID                 int64                  `json:"id"`
	ProfileCode        string                 `json:"profile_code"`
	Manufacturer       string                 `json:"manufacturer"`
	Model              string                 `json:"model"`
	Chemistry          string                 `json:"chemistry"`
	SeriesCells        int16                  `json:"series_cells"`
	CapacityMinAh      *int                   `json:"capacity_min_ah"`
	CapacityMaxAh      *int                   `json:"capacity_max_ah"`
	BMSProtocol        string                 `json:"bms_protocol"`
	ChargeEnvelope     map[string]interface{} `json:"charge_envelope"`
	DischargeEnvelope  map[string]interface{} `json:"discharge_envelope"`
	VoltageCurve       map[string]interface{} `json:"voltage_curve"`
	TemperatureDerating map[string]interface{} `json:"temperature_derating"`
	LifecycleStatus    string                 `json:"lifecycle_status"`
	Version            int                    `json:"version"`
	CreatedAt          time.Time              `json:"created_at"`
	UpdatedAt          time.Time              `json:"updated_at"`
}

// DeviceBatteryConfig 设备电池配置绑定
type DeviceBatteryConfig struct {
	DeviceSN          string                 `json:"device_sn"`
	ProfileID         int64                  `json:"profile_id"`
	CapacityAh        int                    `json:"capacity_ah"`
	ParallelStrings   int16                  `json:"parallel_strings"`
	InstallerLimits   map[string]interface{} `json:"installer_limits"`
	ReportedBMSIdentity map[string]interface{} `json:"reported_bms_identity"`
	Revision          int64                  `json:"revision"`
	ConfiguredBy      *int64                 `json:"configured_by"`
	ConfiguredAt      time.Time              `json:"configured_at"`
}

// CreateBatteryProfileReq 创建电池模板请求
type CreateBatteryProfileReq struct {
	ProfileCode        string                 `json:"profile_code"`
	Manufacturer       string                 `json:"manufacturer"`
	Model              string                 `json:"model"`
	Chemistry          string                 `json:"chemistry"`
	SeriesCells        int16                  `json:"series_cells"`
	CapacityMinAh      *int                   `json:"capacity_min_ah"`
	CapacityMaxAh      *int                   `json:"capacity_max_ah"`
	BMSProtocol        string                 `json:"bms_protocol"`
	ChargeEnvelope     map[string]interface{} `json:"charge_envelope"`
	DischargeEnvelope  map[string]interface{} `json:"discharge_envelope"`
	VoltageCurve       map[string]interface{} `json:"voltage_curve"`
	TemperatureDerating map[string]interface{} `json:"temperature_derating"`
}

// UpsertBatteryConfigReq 更新设备电池配置请求
type UpsertBatteryConfigReq struct {
	ProfileID       int64                  `json:"profile_id"`
	CapacityAh      int                    `json:"capacity_ah"`
	ParallelStrings int16                  `json:"parallel_strings"`
	InstallerLimits map[string]interface{} `json:"installer_limits"`
	ConfiguredBy    int64                  `json:"configured_by"`
}

type BatteryRepository struct {
	db *pgxpool.Pool
}

func NewBatteryRepository(db *pgxpool.Pool) *BatteryRepository {
	return &BatteryRepository{db: db}
}

func (r *BatteryRepository) ListBatteryProfiles(ctx context.Context) ([]BatteryProfile, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, profile_code, COALESCE(manufacturer, ''), COALESCE(model, ''), chemistry,
			series_cells, capacity_min_ah, capacity_max_ah, COALESCE(bms_protocol, ''),
			charge_envelope, discharge_envelope, voltage_curve, temperature_derating,
			lifecycle_status, version, created_at, updated_at
		FROM battery_profiles
		ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var profiles []BatteryProfile
	for rows.Next() {
		var p BatteryProfile
		var chargeEnv, dischargeEnv, voltCurve, tempDerating []byte
		if err := rows.Scan(
			&p.ID, &p.ProfileCode, &p.Manufacturer, &p.Model, &p.Chemistry,
			&p.SeriesCells, &p.CapacityMinAh, &p.CapacityMaxAh, &p.BMSProtocol,
			&chargeEnv, &dischargeEnv, &voltCurve, &tempDerating,
			&p.LifecycleStatus, &p.Version, &p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, err
		}
		if chargeEnv != nil {
			json.Unmarshal(chargeEnv, &p.ChargeEnvelope)
		}
		if dischargeEnv != nil {
			json.Unmarshal(dischargeEnv, &p.DischargeEnvelope)
		}
		if voltCurve != nil {
			json.Unmarshal(voltCurve, &p.VoltageCurve)
		}
		if tempDerating != nil {
			json.Unmarshal(tempDerating, &p.TemperatureDerating)
		}
		profiles = append(profiles, p)
	}
	return profiles, nil
}

func (r *BatteryRepository) GetBatteryProfile(ctx context.Context, id int64) (*BatteryProfile, error) {
	var p BatteryProfile
	var chargeEnv, dischargeEnv, voltCurve, tempDerating []byte
	err := r.db.QueryRow(ctx, `
		SELECT id, profile_code, COALESCE(manufacturer, ''), COALESCE(model, ''), chemistry,
			series_cells, capacity_min_ah, capacity_max_ah, COALESCE(bms_protocol, ''),
			charge_envelope, discharge_envelope, voltage_curve, temperature_derating,
			lifecycle_status, version, created_at, updated_at
		FROM battery_profiles WHERE id = $1`, id).Scan(
		&p.ID, &p.ProfileCode, &p.Manufacturer, &p.Model, &p.Chemistry,
		&p.SeriesCells, &p.CapacityMinAh, &p.CapacityMaxAh, &p.BMSProtocol,
		&chargeEnv, &dischargeEnv, &voltCurve, &tempDerating,
		&p.LifecycleStatus, &p.Version, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	if chargeEnv != nil {
		json.Unmarshal(chargeEnv, &p.ChargeEnvelope)
	}
	if dischargeEnv != nil {
		json.Unmarshal(dischargeEnv, &p.DischargeEnvelope)
	}
	if voltCurve != nil {
		json.Unmarshal(voltCurve, &p.VoltageCurve)
	}
	if tempDerating != nil {
		json.Unmarshal(tempDerating, &p.TemperatureDerating)
	}
	return &p, nil
}

func (r *BatteryRepository) CreateBatteryProfile(ctx context.Context, req CreateBatteryProfileReq) (*BatteryProfile, error) {
	chargeEnv, _ := json.Marshal(req.ChargeEnvelope)
	dischargeEnv, _ := json.Marshal(req.DischargeEnvelope)
	voltCurve, _ := json.Marshal(req.VoltageCurve)
	tempDerating, _ := json.Marshal(req.TemperatureDerating)

	var p BatteryProfile
	var chargeRaw, dischargeRaw, voltRaw, tempRaw []byte
	err := r.db.QueryRow(ctx, `
		INSERT INTO battery_profiles (profile_code, manufacturer, model, chemistry, series_cells,
			capacity_min_ah, capacity_max_ah, bms_protocol, charge_envelope, discharge_envelope,
			voltage_curve, temperature_derating)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING id, profile_code, COALESCE(manufacturer, ''), COALESCE(model, ''), chemistry,
			series_cells, capacity_min_ah, capacity_max_ah, COALESCE(bms_protocol, ''),
			charge_envelope, discharge_envelope, voltage_curve, temperature_derating,
			lifecycle_status, version, created_at, updated_at`,
		req.ProfileCode, req.Manufacturer, req.Model, req.Chemistry, req.SeriesCells,
		req.CapacityMinAh, req.CapacityMaxAh, req.BMSProtocol, chargeEnv, dischargeEnv,
		voltCurve, tempDerating,
	).Scan(
		&p.ID, &p.ProfileCode, &p.Manufacturer, &p.Model, &p.Chemistry,
		&p.SeriesCells, &p.CapacityMinAh, &p.CapacityMaxAh, &p.BMSProtocol,
		&chargeRaw, &dischargeRaw, &voltRaw, &tempRaw,
		&p.LifecycleStatus, &p.Version, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return nil, err
	}
	if chargeRaw != nil {
		json.Unmarshal(chargeRaw, &p.ChargeEnvelope)
	}
	if dischargeRaw != nil {
		json.Unmarshal(dischargeRaw, &p.DischargeEnvelope)
	}
	if voltRaw != nil {
		json.Unmarshal(voltRaw, &p.VoltageCurve)
	}
	if tempRaw != nil {
		json.Unmarshal(tempRaw, &p.TemperatureDerating)
	}
	return &p, nil
}

func (r *BatteryRepository) GetDeviceBatteryConfig(ctx context.Context, sn string) (*DeviceBatteryConfig, error) {
	var cfg DeviceBatteryConfig
	var installerLimits, reportedBMS []byte
	err := r.db.QueryRow(ctx, `
		SELECT device_sn, profile_id, capacity_ah, parallel_strings,
			installer_limits, reported_bms_identity, revision, configured_by, configured_at
		FROM device_battery_config WHERE device_sn = $1`, sn).Scan(
		&cfg.DeviceSN, &cfg.ProfileID, &cfg.CapacityAh, &cfg.ParallelStrings,
		&installerLimits, &reportedBMS, &cfg.Revision, &cfg.ConfiguredBy, &cfg.ConfiguredAt)
	if err != nil {
		return nil, err
	}
	if installerLimits != nil {
		json.Unmarshal(installerLimits, &cfg.InstallerLimits)
	}
	if reportedBMS != nil {
		json.Unmarshal(reportedBMS, &cfg.ReportedBMSIdentity)
	}
	return &cfg, nil
}

func (r *BatteryRepository) UpsertDeviceBatteryConfig(ctx context.Context, sn string, req UpsertBatteryConfigReq) error {
	installerLimits, _ := json.Marshal(req.InstallerLimits)
	_, err := r.db.Exec(ctx, `
		INSERT INTO device_battery_config (device_sn, profile_id, capacity_ah, parallel_strings,
			installer_limits, configured_by, configured_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
		ON CONFLICT (device_sn) DO UPDATE SET
			profile_id = EXCLUDED.profile_id,
			capacity_ah = EXCLUDED.capacity_ah,
			parallel_strings = EXCLUDED.parallel_strings,
			installer_limits = EXCLUDED.installer_limits,
			configured_by = EXCLUDED.configured_by,
			configured_at = EXCLUDED.configured_at,
			revision = device_battery_config.revision + 1`,
		sn, req.ProfileID, req.CapacityAh, req.ParallelStrings,
		installerLimits, req.ConfiguredBy)
	return err
}
