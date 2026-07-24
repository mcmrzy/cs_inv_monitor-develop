ALTER TABLE alarms
    ADD COLUMN IF NOT EXISTS alarm_source SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS event_state VARCHAR(16) NOT NULL DEFAULT 'active';

CREATE INDEX IF NOT EXISTS idx_alarms_v1_active
    ON alarms(device_sn, alarm_source, fault_code)
    WHERE status = 0;

COMMENT ON COLUMN alarms.alarm_source IS 'V1 alarm source: 0 PCS, 1 BMS, 2 MPPT, 3 COMM';
COMMENT ON COLUMN alarms.event_state IS 'V1 lifecycle state: active or recovered';
