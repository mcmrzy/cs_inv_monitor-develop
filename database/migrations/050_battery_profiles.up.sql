-- 050_battery_profiles: 电池配置模板与设备绑定
CREATE TABLE IF NOT EXISTS battery_profiles (
    id BIGSERIAL PRIMARY KEY,
    profile_code VARCHAR(64) NOT NULL UNIQUE,
    manufacturer VARCHAR(128),
    model VARCHAR(128),
    chemistry VARCHAR(32) NOT NULL,
    series_cells SMALLINT NOT NULL,
    capacity_min_ah INTEGER,
    capacity_max_ah INTEGER,
    bms_protocol VARCHAR(64),
    charge_envelope JSONB NOT NULL DEFAULT '{}'::jsonb,
    discharge_envelope JSONB NOT NULL DEFAULT '{}'::jsonb,
    voltage_curve JSONB DEFAULT '{}'::jsonb,
    temperature_derating JSONB DEFAULT '{}'::jsonb,
    lifecycle_status VARCHAR(20) DEFAULT 'active',
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_battery_config (
    device_sn VARCHAR(50) PRIMARY KEY,
    profile_id BIGINT NOT NULL REFERENCES battery_profiles(id),
    capacity_ah INTEGER NOT NULL,
    parallel_strings SMALLINT NOT NULL DEFAULT 1,
    installer_limits JSONB DEFAULT '{}'::jsonb,
    reported_bms_identity JSONB DEFAULT '{}'::jsonb,
    revision BIGINT NOT NULL DEFAULT 0,
    configured_by BIGINT,
    configured_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 默认 LiFePO4 16S 电池模板
INSERT INTO battery_profiles (profile_code, manufacturer, model, chemistry, series_cells, capacity_min_ah, capacity_max_ah, bms_protocol, charge_envelope, discharge_envelope)
VALUES ('lifepo4-16s-default', 'Generic', 'LiFePO4-16S', 'LiFePO4', 16, 50, 400, 'standard',
    '{"max_voltage_v": 58.4, "float_voltage_v": 53.2, "max_current_a": 60, "cutoff_voltage_v": 40.0}'::jsonb,
    '{"cutoff_voltage_v": 40.0, "restart_voltage_v": 42.0, "max_current_a": 120}'::jsonb
) ON CONFLICT (profile_code) DO NOTHING;
