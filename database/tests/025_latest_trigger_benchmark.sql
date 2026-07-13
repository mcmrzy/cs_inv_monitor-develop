\set ON_ERROR_STOP on
\timing on
BEGIN;

CREATE OR REPLACE FUNCTION maintain_telemetry_v2_derived()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.device_sn,0));
    IF (NEW.quality_flags & 64)=0 THEN
        DELETE FROM device_latest_state
        WHERE device_sn=NEW.device_sn AND event_time<=NEW.event_time;
        INSERT INTO device_latest_state
        SELECT (jsonb_populate_record(NULL::device_latest_state,
            to_jsonb(NEW)||jsonb_build_object('updated_at',NOW()))).*
        ON CONFLICT(device_sn) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

INSERT INTO devices(sn,user_id,timezone)
SELECT 'PERF-'||g,1,'Asia/Shanghai' FROM generate_series(1,1000) g;

EXPLAIN (ANALYZE,BUFFERS,TIMING OFF)
INSERT INTO device_telemetry_3min(
    device_sn,protocol_version,sequence_no,event_time,received_at,quality_flags,
    ac_active_power,battery_soc,pv_total_power,daily_pv_energy)
SELECT 'PERF-'||g,1,1,'2026-07-13 00:00:00+00',NOW(),0,1000,80,1200,10
FROM generate_series(1,1000) g;

ROLLBACK;
