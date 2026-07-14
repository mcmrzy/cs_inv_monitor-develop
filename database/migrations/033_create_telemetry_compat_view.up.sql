-- 033: Create compatibility view mapping device_telemetry_3min typed columns
-- to the legacy device_telemetry schema, enabling read-path migration without
-- rewriting every consumer.  Also redefines v_device_latest on the new table.

-- 1. Drop the old v_device_latest (depends on device_telemetry)
DROP VIEW IF EXISTS v_device_latest;

-- 2. Compatibility view: exposes device_telemetry_3min data in the old column
--    layout so that existing SELECT queries only need a table-name swap.
--    A reconstructed `data` JSONB column preserves the nested object structure
--    (ac / batt / battery / pv / sys / sys_status / energy / data / pv_data /
--    ac_data / batt_data / energy_data) that Go consumers and
--    normalizeRealtimeData() expect.
--    Extra typed columns (daily_charge_energy, daily_discharge_energy,
--    daily_load_energy) are exposed so rewritten statistics queries can
--    reference them directly without JSONB extraction.
CREATE OR REPLACE VIEW v_device_telemetry_compat AS
SELECT
    device_sn,
    topic,
    event_time                                                       AS time,
    jsonb_build_object(
        'device_sn', device_sn,
        'ac', jsonb_build_object(
            'voltage',      ac_voltage,
            'current',      ac_current,
            'power',         ac_active_power,
            'frequency',     ac_frequency,
            'load_percent',  load_percent
        ),
        'batt', jsonb_build_object(
            'soc',          battery_soc,
            'voltage',      battery_voltage,
            'current',      battery_current,
            'power',         battery_power,
            'charge_state',  battery_state::text
        ),
        'battery', jsonb_build_object(
            'soc',          battery_soc,
            'soh',          battery_soh,
            'voltage',      battery_voltage,
            'current',      battery_current,
            'charge_state',  battery_state::text
        ),
        'pv', jsonb_build_object(
            'pv_voltage',     pv1_voltage,
            'pv_current',     pv1_current,
            'pv_power',       pv1_power,
            'pv_power_total', pv_total_power,
            'mppt_state',     mppt_state::text
        ),
        'sys', jsonb_build_object(
            'state',      work_state::text,
            'fault_code', fault_code,
            'alarm_code', alarm_code,
            'temp_inv',   inverter_temperature,
            'temp_mos',   mos_temperature,
            'efficiency', efficiency
        ),
        'sys_status', jsonb_build_object(
            'state',      work_state::text,
            'fault_code', fault_code,
            'alarm_code', alarm_code,
            'temp_inv',   inverter_temperature,
            'temp_mos',   mos_temperature,
            'efficiency', efficiency
        ),
        'energy', jsonb_build_object(
            'daily_pv',          daily_pv_energy,
            'total_pv',          total_pv_energy,
            'daily_charge',      daily_charge_energy,
            'total_charge',      total_charge_energy,
            'daily_discharge',   daily_discharge_energy,
            'total_discharge',   total_discharge_energy,
            'daily_load',        daily_load_energy,
            'total_load',        total_load_energy,
            'runtime_hours',     runtime_hours
        ),
        'data', jsonb_build_object(
            'pv_power_total',   pv_total_power,
            'power',             ac_active_power,
            'voltage',           battery_voltage,
            'current',           battery_current,
            'soc',               battery_soc,
            'daily_pv',          daily_pv_energy,
            'daily_charge',      daily_charge_energy,
            'daily_discharge',   daily_discharge_energy,
            'daily_load',        daily_load_energy,
            'total_pv',          total_pv_energy
        ),
        'pv_data',      jsonb_build_object('pv_power_total', pv_total_power),
        'ac_data',      jsonb_build_object('power', ac_active_power),
        'batt_data',    jsonb_build_object('voltage', battery_voltage, 'current', battery_current, 'soc', battery_soc),
        'energy_data',  jsonb_build_object(
            'daily_pv',        daily_pv_energy,
            'daily_charge',    daily_charge_energy,
            'daily_discharge', daily_discharge_energy,
            'daily_load',     daily_load_energy,
            'total_pv',        total_pv_energy
        ),
        'daily_energy', daily_pv_energy
    )                                                                 AS data,
    ac_active_power                                                   AS total_active_power,
    daily_pv_energy                                                   AS daily_energy,
    work_state::TEXT                                                  AS work_state,
    fault_code::TEXT                                                  AS fault_code,
    inverter_temperature                                              AS internal_temperature,
    ac_frequency                                                      AS grid_frequency,
    battery_soc,
    battery_power,
    pv_total_power                                                    AS pv_power,
    daily_charge_energy,
    daily_discharge_energy,
    daily_load_energy,
    received_at                                                       AS created_at
FROM device_telemetry_3min;

-- 3. Recreate v_device_latest on top of the compatibility view so that
--    JOIN queries (GetBySN, GetAll, etc.) keep working unchanged.
CREATE OR REPLACE VIEW v_device_latest AS
SELECT DISTINCT ON (dt.device_sn)
    dt.device_sn,
    NULL::VARCHAR                                                    AS model_code,
    dt.topic,
    dt.data,
    dt.total_active_power,
    dt.daily_energy,
    dt.work_state,
    dt.fault_code,
    dt.internal_temperature,
    dt.grid_frequency,
    dt.battery_soc,
    dt.battery_power,
    dt.pv_power,
    dt.time                                                           AS data_time,
    dt.created_at                                                     AS updated_at
FROM v_device_telemetry_compat dt
ORDER BY dt.device_sn, dt.time DESC;
