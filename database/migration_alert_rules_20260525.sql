-- SYS-T-009: Alert Rule Engine and Notification System
-- Migration Date: 2026-05-25

CREATE TABLE IF NOT EXISTS alert_rules (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    field_name VARCHAR(100) NOT NULL,
    operator VARCHAR(20) NOT NULL,
    threshold_value DECIMAL(12,4) NOT NULL,
    alarm_level SMALLINT DEFAULT 2,
    fault_code VARCHAR(200) NOT NULL,
    fault_message TEXT NOT NULL,
    device_model VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    cooldown_minutes INTEGER DEFAULT 5,
    created_by BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_alert_rules_model ON alert_rules(device_model);
CREATE INDEX IF NOT EXISTS idx_alert_rules_active ON alert_rules(is_active);

CREATE TABLE IF NOT EXISTS alert_notifications (
    id BIGSERIAL PRIMARY KEY,
    alert_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    notify_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    error_message TEXT,
    sent_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_alert_notify_alert ON alert_notifications(alert_id);
CREATE INDEX IF NOT EXISTS idx_alert_notify_user ON alert_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_alert_notify_status ON alert_notifications(status);
