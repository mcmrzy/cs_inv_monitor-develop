CREATE TABLE IF NOT EXISTS device_models (
    id              SERIAL PRIMARY KEY,
    model_code      VARCHAR(50) NOT NULL UNIQUE,
    model_name      VARCHAR(100) NOT NULL,
    manufacturer    VARCHAR(50),
    category        VARCHAR(20) NOT NULL DEFAULT 'inverter',
    rated_power_kw  DECIMAL(8,2) DEFAULT 0,
    data_fields     JSONB NOT NULL DEFAULT '{}',
    field_mapping   JSONB NOT NULL DEFAULT '{}',
    mqtt_topics     JSONB NOT NULL DEFAULT '[]',
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, data_fields, field_mapping, mqtt_topics) VALUES
('INV-5000-TL', 'INVT 5000TL Inverter', 'INVT', 'inverter', 5.0,
 '{"serial_number":{"type":"string","label":"Serial Number"},"total_active_power":{"type":"float","unit":"W","label":"Total Active Power"},"work_state_1":{"type":"string","label":"Work State"},"work_state_1_code":{"type":"int","label":"State Code"},"internal_temperature":{"type":"float","unit":"C","label":"Internal Temperature"},"bus_voltage":{"type":"float","unit":"V","label":"Bus Voltage"},"efficiency":{"type":"float","unit":"percent","label":"Efficiency"},"fault_code":{"type":"int","label":"Fault Code"},"daily_power_yields":{"type":"float","unit":"kWh","label":"Daily Power Yields"},"total_power_yields":{"type":"float","unit":"kWh","label":"Total Power Yields"},"grid_frequency":{"type":"float","unit":"Hz","label":"Grid Frequency"},"power_factor":{"type":"float","label":"Power Factor"},"nominal_active_power":{"type":"float","unit":"W","label":"Nominal Active Power"},"output_type":{"type":"int","label":"Output Type"}}'::jsonb,
 '{"data/status":{"work_state":"work_state_1","temp":"internal_temperature","bus_voltage":"bus_voltage","efficiency":"efficiency","fault_code":"fault_code"},"data/ac":{"active_power":"total_active_power","frequency":"grid_frequency","pf":"power_factor"},"data/energy":{"daily":"daily_power_yields","total":"total_power_yields"}}'::jsonb,
 '["cs_inv/+/data/status", "cs_inv/+/data/ac", "cs_inv/+/data/energy"]'::jsonb)
ON CONFLICT (model_code) DO NOTHING;
