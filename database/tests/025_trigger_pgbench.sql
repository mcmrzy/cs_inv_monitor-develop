\set device_id random(1, 10000)
INSERT INTO device_telemetry_3min(
    device_sn,protocol_version,sequence_no,event_time,received_at,quality_flags,
    ac_active_power,battery_soc,battery_power,pv_total_power,daily_pv_energy,total_pv_energy)
VALUES(
    'BENCH-' || :device_id,1,:device_id,clock_timestamp(),clock_timestamp(),0,
    1000,80,200,1200,10,1000 + :device_id
);

INSERT INTO device_cell_samples(
    device_sn,event_time,sequence_no,voltages,temperatures,quality_flags,is_abnormal)
VALUES(
    'BENCH-' || :device_id,clock_timestamp(),:device_id,
    '[3.2,3.2,3.2,3.2]'::jsonb,'[25,25,25,25]'::jsonb,0,FALSE
);
