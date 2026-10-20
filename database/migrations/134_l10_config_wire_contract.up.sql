-- Collector.c ReadConfigParam and direct_poll.c collector_value use the same
-- 1-based wire enums. Migration 096 incorrectly treated them as 0-based enums.
-- Do not rewrite reported values: their numeric values already match the wire.
UPDATE device_config_schema SET min=1, max=4,
    enum_map='{"1":"solar_first","2":"utility_first","3":"solar_battery_utility","4":"solar_utility_battery"}'::jsonb
WHERE param_key='set_output_priority';
UPDATE device_config_schema SET min=1, max=3,
    enum_map='{"1":"appliance","2":"ups","3":"generator"}'::jsonb
WHERE param_key='set_ac_volt_range';
-- Collector battery order differs from native DSP: User Pb and Lithium swap.
UPDATE device_config_schema SET min=1, max=5,
    enum_map='{"1":"agm","2":"flooded","3":"lithium","4":"user_lead_acid","5":"user_lithium"}'::jsonb
WHERE param_key='set_battery_type';
UPDATE device_config_schema SET min=1, max=3,
    enum_map='{"1":"solar_first","2":"solar_utility","3":"solar_only"}'::jsonb
WHERE param_key='set_charge_priority';
-- AC output mode is parallel/phase topology, not battery/utility priority.
-- Original OutputForm.c: SIG=1, PAL=2, 3P1=3, 3P2=4, 3P3=5.
UPDATE device_config_schema SET min=1, max=5,
    enum_map='{"1":"ac_single_phase","2":"ac_parallel","3":"ac_three_phase_l1","4":"ac_three_phase_l2","5":"ac_three_phase_l3"}'::jsonb
WHERE param_key='set_ac_output_mode';

-- 140 A is the L10 original ARM default maximum total charging current.
UPDATE device_config_schema SET max=140, step=1 WHERE param_key='set_max_charge_current';
UPDATE device_config_schema SET visibility='{"param":"set_battery_type","eq":5}'::jsonb
WHERE param_key IN ('set_li_bat_material','set_cell_serial_lifepo4','set_cell_serial_li_nmc');
-- eq=2 preserves the safe legacy-client filter; newer clients use in first.
UPDATE device_config_schema SET visibility='{"param":"set_battery_type","eq":2,"in":[2,4]}'::jsonb
WHERE param_key IN ('set_equalize_enable','set_equalize_voltage','set_equalize_time',
                    'set_equalize_timeout','set_equalize_interval','set_equalize_activate');

-- Start generator at LOW voltage and stop at HIGH voltage. The reversed
-- constraints discarded both values in otherwise valid reports (48/56 V).
UPDATE device_config_schema SET validation='{"lte":"set_gen_stop_voltage"}'::jsonb
WHERE param_key='set_gen_start_voltage';
UPDATE device_config_schema SET validation='{"gte":"set_gen_start_voltage"}'::jsonb
WHERE param_key='set_gen_stop_voltage';
-- Utility and generator thresholds are independent strategies. Original ARM
-- defaults utility=50%, generator=20%; do not reject them against each other.
UPDATE device_config_schema SET validation='{"lte":"set_soc_back_bat"}'::jsonb
WHERE param_key='set_soc_back_utl';
UPDATE device_config_schema SET validation='{"lte":"set_soc_close_gen"}'::jsonb
WHERE param_key='set_soc_back_gen';
UPDATE device_config_schema SET validation='{"gte":"set_soc_back_gen"}'::jsonb
WHERE param_key='set_soc_close_gen';

-- Command validation must accept the same enums/range as config rendering and
-- ingestion. Scope command changes to L10 and preserve unrelated model commands.
UPDATE device_model_commands c SET param_schema=jsonb_set(c.param_schema,'{args,0}',
    (c.param_schema->'args'->0) || jsonb_build_object('min',s.min,'max',s.max,'enum',
        (SELECT jsonb_agg(k::integer ORDER BY k::integer) FROM jsonb_object_keys(s.enum_map) AS keys(k))))
FROM device_config_schema s, device_models m
WHERE c.model_id=m.id AND m.model_code='CS-L10-6K2' AND c.command_code=s.param_key
  AND s.param_key IN ('set_output_priority','set_ac_volt_range','set_battery_type','set_charge_priority','set_ac_output_mode')
  AND jsonb_typeof(c.param_schema->'args')='array' AND jsonb_array_length(c.param_schema->'args')=1;
UPDATE device_model_commands c SET param_schema=jsonb_set(c.param_schema,'{args,0}',
    (c.param_schema->'args'->0) || '{"max":140}'::jsonb)
FROM device_models m
WHERE c.model_id=m.id AND m.model_code='CS-L10-6K2' AND c.command_code='set_max_charge_current'
  AND jsonb_typeof(c.param_schema->'args')='array' AND jsonb_array_length(c.param_schema->'args')=1;
