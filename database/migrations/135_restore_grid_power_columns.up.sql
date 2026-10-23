-- Repair schema drift: migration 091 can be recorded while its telemetry columns
-- are absent. Nullable columns preserve unknown readings; the next heartbeat
-- populates them through the existing telemetry-to-latest-state trigger.
ALTER TABLE device_telemetry_3min
    ADD COLUMN IF NOT EXISTS ac_input_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_power REAL;

ALTER TABLE device_latest_state
    ADD COLUMN IF NOT EXISTS ac_input_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_power REAL;
