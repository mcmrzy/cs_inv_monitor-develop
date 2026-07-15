-- TimescaleDB compatibility bootstrap
--
-- Canonical telemetry storage is installed by numbered migrations:
--   * device_telemetry_3min: one row per 3-minute Heartbeat sample
--   * device_telemetry_hour: hourly continuous aggregate
--   * device_energy_day: daily derived aggregate
--
-- The final HTML protocol explicitly forbids a 1-minute aggregate because the
-- source sampling period is 3 minutes. This file remains only for deployments
-- that still have the legacy device_telemetry table; it must not create a
-- device_telemetry_1min layer.

CREATE EXTENSION IF NOT EXISTS timescaledb;

DO $$
BEGIN
    IF to_regclass('public.device_telemetry') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM timescaledb_information.hypertables
           WHERE hypertable_schema = 'public'
             AND hypertable_name = 'device_telemetry'
       ) THEN
        PERFORM create_hypertable(
            'device_telemetry',
            'time',
            if_not_exists => TRUE
        );
    END IF;
END $$;

-- No 1-minute, legacy 1-hour, or legacy 1-day aggregate is created here.
-- Run the API migration entrypoint to install/upgrade the canonical 3-minute,
-- hourly and daily pipeline and its retention/compression policies.
