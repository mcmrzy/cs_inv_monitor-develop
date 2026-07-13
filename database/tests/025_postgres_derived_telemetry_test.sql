\set ON_ERROR_STOP on
BEGIN;

INSERT INTO devices(sn,user_id,timezone) VALUES('TEST-PG-DERIVED',1,'Asia/Shanghai');

INSERT INTO device_telemetry_3min(
    device_sn,protocol_version,sequence_no,event_time,received_at,quality_flags,
    ac_active_power,battery_soc,battery_power,pv_total_power,inverter_temperature,
    mos_temperature,battery_temperature,daily_pv_energy,total_pv_energy)
VALUES
    ('TEST-PG-DERIVED',1,2,'2026-07-13 00:03:00+00',NOW(),0,1200,80,300,1500,45,50,30,12,1012),
    ('TEST-PG-DERIVED',1,1,'2026-07-13 00:00:00+00',NOW(),0,1000,70,-200,1300,40,48,28,10,1010),
    ('TEST-PG-DERIVED',1,99,'2026-06-15 00:00:00+00',NOW(),64,900,60,100,1100,38,45,27,8,900)
ON CONFLICT(device_sn,event_time) DO NOTHING;

-- A duplicate fact row must not increment the daily rollup.
INSERT INTO device_telemetry_3min(
    device_sn,protocol_version,sequence_no,event_time,received_at,quality_flags)
VALUES('TEST-PG-DERIVED',1,2,'2026-07-13 00:03:00+00',NOW(),0)
ON CONFLICT(device_sn,event_time) DO NOTHING;

INSERT INTO device_cell_samples(
    device_sn,event_time,sequence_no,voltages,temperatures,quality_flags,is_abnormal)
VALUES
    ('TEST-PG-DERIVED','2026-07-13 00:03:00+00',2,'[3.2,3.2]','[25,25]',0,FALSE),
    ('TEST-PG-DERIVED','2026-07-13 00:00:00+00',1,'[3.1,3.1]','[24,24]',0,FALSE),
    ('TEST-PG-DERIVED','2026-07-14 00:00:00+00',99,'[3.0,3.0]','[23,23]',64,FALSE);

CALL refresh_device_energy_month(NULL,'{"full_refresh":true}'::jsonb);

DO $$
DECLARE
    latest_sequence BIGINT;
    latest_cell_sequence BIGINT;
    july_samples INTEGER;
    july_pv DOUBLE PRECISION;
    june_pv DOUBLE PRECISION;
BEGIN
    SELECT sequence_no INTO latest_sequence
    FROM device_latest_state WHERE device_sn='TEST-PG-DERIVED';
    IF latest_sequence <> 2 THEN
        RAISE EXCEPTION 'latest telemetry expected sequence 2, got %',latest_sequence;
    END IF;

    SELECT sequence_no INTO latest_cell_sequence
    FROM device_latest_cells WHERE device_sn='TEST-PG-DERIVED';
    IF latest_cell_sequence <> 2 THEN
        RAISE EXCEPTION 'latest cells expected sequence 2, got %',latest_cell_sequence;
    END IF;

    SELECT sample_count INTO july_samples FROM device_energy_day
    WHERE device_sn='TEST-PG-DERIVED' AND stat_date=DATE '2026-07-13';
    IF july_samples <> 2 THEN
        RAISE EXCEPTION 'July daily sample count expected 2, got %',july_samples;
    END IF;

    SELECT pv_energy INTO july_pv FROM device_energy_month
    WHERE device_sn='TEST-PG-DERIVED' AND stat_month=DATE '2026-07-01';
    SELECT pv_energy INTO june_pv FROM device_energy_month
    WHERE device_sn='TEST-PG-DERIVED' AND stat_month=DATE '2026-06-01';
    IF july_pv <> 12 OR june_pv <> 8 THEN
        RAISE EXCEPTION 'monthly energy expected July=12 June=8, got July=% June=%',july_pv,june_pv;
    END IF;
END;
$$;

ROLLBACK;
