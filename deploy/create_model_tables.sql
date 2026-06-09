CREATE TABLE IF NOT EXISTS device_model_field (
    id BIGSERIAL PRIMARY KEY,
    model_id INT NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
    field_key VARCHAR(64) NOT NULL,
    field_name VARCHAR(128) NOT NULL,
    field_type VARCHAR(32) NOT NULL,
    unit VARCHAR(32),
    sort INT NOT NULL DEFAULT 0,
    is_show BOOLEAN NOT NULL DEFAULT true,
    is_control BOOLEAN NOT NULL DEFAULT false,
    parse_rule TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model_id, field_key)
);

CREATE INDEX IF NOT EXISTS idx_model_field_model ON device_model_field(model_id);

CREATE TABLE IF NOT EXISTS device_model_protocol (
    id BIGSERIAL PRIMARY KEY,
    model_id INT NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
    topic_pattern VARCHAR(200) NOT NULL,
    parse_type VARCHAR(32) NOT NULL DEFAULT 'json',
    parse_config JSONB,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(model_id, topic_pattern)
);

CREATE INDEX IF NOT EXISTS idx_model_protocol_model ON device_model_protocol(model_id);

INSERT INTO device_model_field (model_id, field_key, field_name, field_type, unit, sort, is_show)
SELECT 
    dm.id,
    key,
    COALESCE(value->>'label', key),
    COALESCE(value->>'type', 'string'),
    value->>'unit',
    0,
    true
FROM device_models dm, jsonb_each(dm.data_fields)
WHERE dm.is_active = true
ON CONFLICT (model_id, field_key) DO NOTHING;
