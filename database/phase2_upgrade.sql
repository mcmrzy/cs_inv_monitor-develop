CREATE TABLE IF NOT EXISTS device_telemetry (
    id BIGSERIAL, device_sn VARCHAR(50) NOT NULL, model_code VARCHAR(50),
    topic VARCHAR(200), data JSONB NOT NULL,
    total_active_power DECIMAL(12,2) DEFAULT 0,
    daily_energy DECIMAL(14,4) DEFAULT 0,
    work_state VARCHAR(50), fault_code VARCHAR(50),
    internal_temperature DECIMAL(6,1) DEFAULT 0,
    time TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time ON device_telemetry(device_sn, time DESC);

CREATE TABLE IF NOT EXISTS device_models (
    id SERIAL PRIMARY KEY,
    model_code VARCHAR(50) NOT NULL UNIQUE,
    model_name VARCHAR(100) NOT NULL,
    manufacturer VARCHAR(50),
    category VARCHAR(20) NOT NULL DEFAULT 'inverter',
    rated_power_kw DECIMAL(8,2) DEFAULT 0,
    data_fields JSONB NOT NULL DEFAULT '{}',
    field_mapping JSONB NOT NULL DEFAULT '{}',
    mqtt_topics JSONB NOT NULL DEFAULT '[]',
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, data_fields, field_mapping)
VALUES ('INV-5000-TL', 'INVT 5000TL 逆变器', 'INVT', 'inverter', 5.0,
'{"serial_number":{"type":"string","label":"序列号"},"total_active_power":{"type":"float","unit":"W","label":"总有功功率"},"work_state_1":{"type":"string","label":"工作状态"},"internal_temperature":{"type":"float","unit":"C","label":"内部温度"}}',
'{"data/status":{"work_state":"work_state_1","temp":"internal_temperature"}}')
ON CONFLICT DO NOTHING;

SELECT 'TABLES_CREATED_OK' as result;
