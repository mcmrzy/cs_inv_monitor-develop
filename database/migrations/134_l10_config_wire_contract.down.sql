UPDATE device_config_schema SET min=0,max=2,
    enum_map='{"0":"solar_first","1":"utility_first","2":"solar_utility"}'::jsonb
WHERE param_key IN ('set_output_priority','set_charge_priority');
UPDATE device_config_schema SET min=0,max=2,enum_map='{"0":"appliance","1":"ups"}'::jsonb
WHERE param_key='set_ac_volt_range';
UPDATE device_config_schema SET min=0,max=2,enum_map='{"0":"LiFePO4","1":"NCM","2":"LeadAcid"}'::jsonb
WHERE param_key='set_battery_type';
UPDATE device_config_schema SET min=0,max=2,enum_map='{"0":"battery_first","1":"utility_first","2":"hybrid"}'::jsonb
WHERE param_key='set_ac_output_mode';
UPDATE device_config_schema SET max=60,step=0.1 WHERE param_key='set_max_charge_current';
UPDATE device_config_schema SET visibility='{"param":"set_battery_type","ne":2}'::jsonb WHERE param_key='set_li_bat_material';
UPDATE device_config_schema SET visibility='{"param":"set_battery_type","eq":0}'::jsonb WHERE param_key='set_cell_serial_lifepo4';
UPDATE device_config_schema SET visibility='{"param":"set_battery_type","eq":1}'::jsonb WHERE param_key='set_cell_serial_li_nmc';
UPDATE device_config_schema SET visibility='{"param":"set_battery_type","eq":2}'::jsonb
WHERE param_key IN ('set_equalize_enable','set_equalize_voltage','set_equalize_time',
                    'set_equalize_timeout','set_equalize_interval','set_equalize_activate');
UPDATE device_config_schema SET validation='{"gte":"set_gen_stop_voltage"}'::jsonb WHERE param_key='set_gen_start_voltage';
UPDATE device_config_schema SET validation='{"lte":"set_gen_start_voltage"}'::jsonb WHERE param_key='set_gen_stop_voltage';
UPDATE device_config_schema SET validation='{"lte":"set_soc_back_gen"}'::jsonb WHERE param_key='set_soc_back_utl';
UPDATE device_config_schema SET validation='{"gte":"set_soc_back_utl"}'::jsonb WHERE param_key='set_soc_back_gen';
UPDATE device_config_schema SET validation=NULL WHERE param_key='set_soc_close_gen';
UPDATE device_model_commands c SET param_schema=jsonb_set(c.param_schema,'{args,0}',
    (c.param_schema->'args'->0) || '{"min":0,"max":2,"enum":[0,1,2]}'::jsonb)
FROM device_models m
WHERE c.model_id=m.id AND m.model_code='CS-L10-6K2'
  AND c.command_code IN ('set_output_priority','set_ac_volt_range','set_battery_type','set_charge_priority','set_ac_output_mode')
  AND jsonb_typeof(c.param_schema->'args')='array' AND jsonb_array_length(c.param_schema->'args')=1;
UPDATE device_model_commands c SET param_schema=jsonb_set(c.param_schema,'{args,0}',
    (c.param_schema->'args'->0) || '{"max":60}'::jsonb)
FROM device_models m
WHERE c.model_id=m.id AND m.model_code='CS-L10-6K2' AND c.command_code='set_max_charge_current'
  AND jsonb_typeof(c.param_schema->'args')='array' AND jsonb_array_length(c.param_schema->'args')=1;
