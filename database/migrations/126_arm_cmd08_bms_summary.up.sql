ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS bms_summary JSONB;
CREATE INDEX IF NOT EXISTS idx_telemetry_bms_summary_sn_time
    ON device_telemetry_3min(device_sn, received_at DESC, event_time DESC)
    WHERE bms_summary IS NOT NULL;
