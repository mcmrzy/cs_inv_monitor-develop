CREATE TABLE IF NOT EXISTS alert_rules (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    type VARCHAR(40) NOT NULL DEFAULT 'telemetry',
    station_id BIGINT,
    device_sn VARCHAR(64),
    conditions JSONB NOT NULL DEFAULT '[]'::jsonb,
    severity VARCHAR(16) NOT NULL DEFAULT 'warning',
    notification_channels JSONB NOT NULL DEFAULT '["app"]'::jsonb,
    cooldown_minutes INTEGER NOT NULL DEFAULT 5 CHECK (cooldown_minutes BETWEEN 1 AND 1440),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alert_rules_owner ON alert_rules(created_by, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_alert_rules_target ON alert_rules(device_sn, station_id) WHERE enabled;
