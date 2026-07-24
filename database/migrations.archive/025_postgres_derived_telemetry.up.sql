-- 025: move deterministic telemetry derivatives from Device Server into PostgreSQL.
CREATE OR REPLACE FUNCTION maintain_telemetry_v2_derived()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Serialize only the same device. This prevents an older concurrent sample
    -- from replacing a newer latest-state row.
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.device_sn, 0));

    -- QualityBackfill is bit 6. Backfills update historical rollups, never realtime state.
    IF (NEW.quality_flags & 64) = 0 THEN
        DELETE FROM device_latest_state
        WHERE device_sn = NEW.device_sn AND event_time <= NEW.event_time;

        INSERT INTO device_latest_state
        SELECT (jsonb_populate_record(
            NULL::device_latest_state,
            to_jsonb(NEW) || jsonb_build_object('updated_at', NOW())
        )).*
        ON CONFLICT (device_sn) DO NOTHING;
    END IF;

    INSERT INTO device_energy_day(
        device_sn,stat_date,timezone,pv_energy,charge_energy,discharge_energy,load_energy,
        total_pv_energy,total_charge_energy,total_discharge_energy,total_load_energy,
        max_pv_power,max_ac_power,max_charge_power,max_discharge_power,
        avg_battery_soc,min_battery_soc,max_battery_soc,max_inverter_temperature,
        max_mos_temperature,max_battery_temperature,sample_count,online_minutes,run_minutes,quality_flags)
    SELECT NEW.device_sn,
        (NEW.event_time AT TIME ZONE COALESCE(NULLIF(d.timezone,''),'Asia/Shanghai'))::date,
        COALESCE(NULLIF(d.timezone,''),'Asia/Shanghai'),
        COALESCE(NEW.daily_pv_energy,0),COALESCE(NEW.daily_charge_energy,0),
        COALESCE(NEW.daily_discharge_energy,0),COALESCE(NEW.daily_load_energy,0),
        NEW.total_pv_energy,NEW.total_charge_energy,NEW.total_discharge_energy,NEW.total_load_energy,
        COALESCE(NEW.pv_total_power,0),COALESCE(NEW.ac_active_power,0),
        GREATEST(COALESCE(NEW.battery_power,0),0),GREATEST(-COALESCE(NEW.battery_power,0),0),
        COALESCE(NEW.battery_soc,0),COALESCE(NEW.battery_soc,0),COALESCE(NEW.battery_soc,0),
        COALESCE(NEW.inverter_temperature,0),COALESCE(NEW.mos_temperature,0),
        COALESCE(NEW.battery_temperature,0),1,3,
        CASE WHEN COALESCE(NEW.ac_active_power,0)>0 THEN 3 ELSE 0 END,NEW.quality_flags
    FROM devices d WHERE d.sn=NEW.device_sn
    ON CONFLICT(device_sn,stat_date) DO UPDATE SET
        pv_energy=GREATEST(device_energy_day.pv_energy,EXCLUDED.pv_energy),
        charge_energy=GREATEST(device_energy_day.charge_energy,EXCLUDED.charge_energy),
        discharge_energy=GREATEST(device_energy_day.discharge_energy,EXCLUDED.discharge_energy),
        load_energy=GREATEST(device_energy_day.load_energy,EXCLUDED.load_energy),
        total_pv_energy=COALESCE(EXCLUDED.total_pv_energy,device_energy_day.total_pv_energy),
        total_charge_energy=COALESCE(EXCLUDED.total_charge_energy,device_energy_day.total_charge_energy),
        total_discharge_energy=COALESCE(EXCLUDED.total_discharge_energy,device_energy_day.total_discharge_energy),
        total_load_energy=COALESCE(EXCLUDED.total_load_energy,device_energy_day.total_load_energy),
        max_pv_power=GREATEST(device_energy_day.max_pv_power,EXCLUDED.max_pv_power),
        max_ac_power=GREATEST(device_energy_day.max_ac_power,EXCLUDED.max_ac_power),
        max_charge_power=GREATEST(device_energy_day.max_charge_power,EXCLUDED.max_charge_power),
        max_discharge_power=GREATEST(device_energy_day.max_discharge_power,EXCLUDED.max_discharge_power),
        avg_battery_soc=((COALESCE(device_energy_day.avg_battery_soc,0)*device_energy_day.sample_count)+EXCLUDED.avg_battery_soc)/(device_energy_day.sample_count+1),
        min_battery_soc=LEAST(device_energy_day.min_battery_soc,EXCLUDED.min_battery_soc),
        max_battery_soc=GREATEST(device_energy_day.max_battery_soc,EXCLUDED.max_battery_soc),
        max_inverter_temperature=GREATEST(device_energy_day.max_inverter_temperature,EXCLUDED.max_inverter_temperature),
        max_mos_temperature=GREATEST(device_energy_day.max_mos_temperature,EXCLUDED.max_mos_temperature),
        max_battery_temperature=GREATEST(device_energy_day.max_battery_temperature,EXCLUDED.max_battery_temperature),
        sample_count=device_energy_day.sample_count+1,
        online_minutes=LEAST(1440,device_energy_day.online_minutes+3),
        run_minutes=LEAST(1440,device_energy_day.run_minutes+EXCLUDED.run_minutes),
        quality_flags=device_energy_day.quality_flags|EXCLUDED.quality_flags,
        updated_at=NOW();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_telemetry_v2_derived ON device_telemetry_3min;
CREATE TRIGGER trg_telemetry_v2_derived
AFTER INSERT ON device_telemetry_3min
FOR EACH ROW EXECUTE FUNCTION maintain_telemetry_v2_derived();

CREATE OR REPLACE FUNCTION maintain_latest_cells()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.device_sn, 0));
    IF (NEW.quality_flags & 64) = 0 THEN
        DELETE FROM device_latest_cells
        WHERE device_sn=NEW.device_sn AND event_time<=NEW.event_time;

        INSERT INTO device_latest_cells(device_sn,event_time,sequence_no,voltages,temperatures,quality_flags,updated_at)
        VALUES(NEW.device_sn,NEW.event_time,NEW.sequence_no,NEW.voltages,NEW.temperatures,NEW.quality_flags,NOW())
        ON CONFLICT(device_sn) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_latest_cells ON device_cell_samples;
CREATE TRIGGER trg_latest_cells
AFTER INSERT ON device_cell_samples
FOR EACH ROW EXECUTE FUNCTION maintain_latest_cells();

CREATE OR REPLACE PROCEDURE refresh_device_energy_month(job_id INTEGER, config JSONB)
LANGUAGE plpgsql
AS $$
DECLARE
    start_month DATE;
    months_back INTEGER;
BEGIN
    IF COALESCE((config->>'full_refresh')::boolean,FALSE) THEN
        start_month := DATE '1970-01-01';
    ELSE
        months_back := GREATEST(COALESCE((config->>'months_back')::integer,4),1);
        start_month := (date_trunc('month',CURRENT_DATE)-make_interval(months=>months_back-1))::date;
    END IF;

    INSERT INTO device_energy_month(
        device_sn,stat_month,timezone,pv_energy,charge_energy,discharge_energy,load_energy,
        total_pv_energy,total_charge_energy,total_discharge_energy,total_load_energy,
        online_minutes,run_minutes,alarm_count,fault_count,quality_flags,updated_at)
    SELECT device_sn,date_trunc('month',stat_date)::date,
        (array_agg(timezone ORDER BY stat_date DESC))[1],
        SUM(pv_energy),SUM(charge_energy),SUM(discharge_energy),SUM(load_energy),
        MAX(total_pv_energy),MAX(total_charge_energy),MAX(total_discharge_energy),MAX(total_load_energy),
        SUM(online_minutes),SUM(run_minutes),SUM(alarm_count),SUM(fault_count),bit_or(quality_flags),NOW()
    FROM device_energy_day
    WHERE stat_date>=start_month
    GROUP BY device_sn,date_trunc('month',stat_date)::date
    ON CONFLICT(device_sn,stat_month) DO UPDATE SET
        timezone=EXCLUDED.timezone,pv_energy=EXCLUDED.pv_energy,
        charge_energy=EXCLUDED.charge_energy,discharge_energy=EXCLUDED.discharge_energy,
        load_energy=EXCLUDED.load_energy,total_pv_energy=EXCLUDED.total_pv_energy,
        total_charge_energy=EXCLUDED.total_charge_energy,total_discharge_energy=EXCLUDED.total_discharge_energy,
        total_load_energy=EXCLUDED.total_load_energy,online_minutes=EXCLUDED.online_minutes,
        run_minutes=EXCLUDED.run_minutes,alarm_count=EXCLUDED.alarm_count,
        fault_count=EXCLUDED.fault_count,quality_flags=EXCLUDED.quality_flags,updated_at=NOW();
END;
$$;

CALL refresh_device_energy_month(NULL,'{"full_refresh":true}'::jsonb);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='timescaledb')
       AND NOT EXISTS (
           SELECT 1 FROM timescaledb_information.jobs
           WHERE proc_schema='public' AND proc_name='refresh_device_energy_month'
       ) THEN
        PERFORM add_job('refresh_device_energy_month',INTERVAL '1 day',
            config=>'{"months_back":4}'::jsonb,
            initial_start=>(date_trunc('day',NOW() AT TIME ZONE 'Asia/Shanghai')+INTERVAL '1 day 2 hours 10 minutes') AT TIME ZONE 'Asia/Shanghai',
            timezone=>'Asia/Shanghai');
    END IF;
END $$;
