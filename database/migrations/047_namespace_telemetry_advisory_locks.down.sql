-- Restore migration-025 lock keys. Function behavior is otherwise unchanged.

CREATE OR REPLACE FUNCTION maintain_telemetry_v2_derived()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.device_sn, 0));

    IF (NEW.quality_flags & 8) = 0 THEN
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

CREATE OR REPLACE FUNCTION maintain_latest_cells()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.device_sn, 0));
    IF (NEW.quality_flags & 8) = 0 THEN
        DELETE FROM device_latest_cells
        WHERE device_sn=NEW.device_sn AND event_time<=NEW.event_time;

        INSERT INTO device_latest_cells(device_sn,event_time,sequence_no,voltages,temperatures,quality_flags,updated_at)
        VALUES(NEW.device_sn,NEW.event_time,NEW.sequence_no,NEW.voltages,NEW.temperatures,NEW.quality_flags,NOW())
        ON CONFLICT(device_sn) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION maintain_telemetry_v2_derived() IS NULL;
COMMENT ON FUNCTION maintain_latest_cells() IS NULL;
