--
-- 回滚迁移 096：CS-L10-6K2 v2.1 协议升级（逆序，幂等可重放）。
-- 顺序：先删新表 → 删列 → 删命令/字段配置 → 还原型号/协议 → 最后删 catalog 键（带 NOT EXISTS 保护）。
-- catalog 的 V1 键（ac_voltage 等）被 V1 型号引用，只删 096 新增的 30 键。

-- 0. 兼容修复：回滚前确保 updated_at 列存在（与 up 对应，幂等）
ALTER TABLE device_protocol_versions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE device_protocol_fields   ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- 1. 删除新表（诊断 / 健康度 / config schema / 配置审计）
DROP TABLE IF EXISTS device_config_changes;
DROP TABLE IF EXISTS device_config_schema;
DROP TABLE IF EXISTS device_health_history;
DROP TABLE IF EXISTS device_diagnostics;

-- 2. devices 删除设备信息列与索引
DROP INDEX IF EXISTS idx_devices_model;
ALTER TABLE devices
    DROP COLUMN IF EXISTS phase,
    DROP COLUMN IF EXISTS inverter_module,
    DROP COLUMN IF EXISTS bootloader_version,
    DROP COLUMN IF EXISTS rated_power_w,
    DROP COLUMN IF EXISTS info_reported_at;

-- 3. 遥测新列（先 device_latest_state，再 device_telemetry_3min）
ALTER TABLE device_latest_state
    DROP COLUMN IF EXISTS mppt_fan_speed,
    DROP COLUMN IF EXISTS inv_fan_speed,
    DROP COLUMN IF EXISTS inv_current,
    DROP COLUMN IF EXISTS parallel_charge_current,
    DROP COLUMN IF EXISTS work_time_total,
    DROP COLUMN IF EXISTS paired_socket,
    DROP COLUMN IF EXISTS online_socket,
    DROP COLUMN IF EXISTS on_socket,
    DROP COLUMN IF EXISTS health_score;

ALTER TABLE device_telemetry_3min
    DROP COLUMN IF EXISTS mppt_fan_speed,
    DROP COLUMN IF EXISTS inv_fan_speed,
    DROP COLUMN IF EXISTS inv_current,
    DROP COLUMN IF EXISTS parallel_charge_current,
    DROP COLUMN IF EXISTS work_time_total,
    DROP COLUMN IF EXISTS paired_socket,
    DROP COLUMN IF EXISTS online_socket,
    DROP COLUMN IF EXISTS on_socket;

-- 4. 命令：删除 096 新增的 18 条控制命令 + 3 条查询命令
DELETE FROM device_model_commands
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND command_code IN (
    'set_ac_volt_range','set_overload_restart','set_high_temp_restart','set_backlight_ctrl',
    'set_power_shutdown_alarm','set_overload_use_city_power','set_max_discharge_current',
    'set_max_chg_curr','set_recover_threshold_volt','set_solar_power_balance','set_li_bat_material',
    'set_cell_serial_lifepo4','set_cell_serial_li_nmc','set_equalize_timeout','set_equalize_interval',
    'set_equalize_activate','set_charge_time','set_close_charge_time',
    'query_info','query_telemetry','query_config'
);

-- 4.1 还原 091 既有 24 条命令的 parameter_schema（原始量纲）与风险等级，并清除 config_domain
WITH cmd(command_code, parameter_schema, risk_level) AS (VALUES
('set_output_priority','{"args":[{"key":"priority","type":"integer","min":0,"max":2,"unit":""}]}',1),
('set_max_charge_current','{"args":[{"key":"current_x10","type":"integer","min":0,"max":600,"unit":"0.1A"}]}',1),
('set_battery_capacity','{"args":[{"key":"capacity_ah","type":"integer","min":0,"max":2000,"unit":"Ah"}]}',1),
('set_battery_type','{"args":[{"key":"battery_type","type":"integer","min":0,"max":2,"unit":""}]}',1),
('set_output_voltage','{"args":[{"key":"voltage_v","type":"integer","min":200,"max":250,"unit":"V"}]}',1),
('set_output_frequency','{"args":[{"key":"freq_hz","type":"integer","enum":[50,60],"unit":"Hz"}]}',1),
('set_master_slave','{"args":[{"key":"mode","type":"integer","enum":[0,1],"unit":""}]}',1),
('set_ac_charge_current','{"args":[{"key":"current_x10","type":"integer","min":0,"max":1500,"unit":"0.1A"}]}',1),
('set_ac_output_mode','{"args":[{"key":"mode","type":"integer","enum":[0,1,2],"unit":""}]}',2),
('set_charge_priority','{"args":[{"key":"priority","type":"integer","enum":[0,1,2],"unit":""}]}',2),
('set_low_volt_return_utl','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}',2),
('set_high_volt_return_bat','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}',2),
('set_soc_cutoff','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}',2),
('set_equalize_enable','{"args":[{"key":"enable","type":"boolean"}]}',2),
('set_equalize_voltage','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":650,"unit":"0.1V"}]}',2),
('set_equalize_time','{"args":[{"key":"time_min","type":"integer","min":0,"max":720,"unit":"min"}]}',2),
('set_gen_start_voltage','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}',2),
('set_gen_stop_voltage','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}',2),
('set_soc_back_utl','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}',2),
('set_soc_back_bat','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}',2),
('set_soc_back_gen','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}',2),
('set_soc_close_gen','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}',2),
('set_alarm_control','{"args":[{"key":"alarm_ctrl","type":"integer","min":0,"max":255,"unit":""}]}',2),
('set_buzzer','{"args":[{"key":"enable","type":"boolean"}]}',1)
)
UPDATE device_model_commands dmc
SET config_domain = NULL,
    confirmation_mode = NULL,
    risk_level = c.risk_level,
    parameter_schema = c.parameter_schema::jsonb,
    updated_at = NOW()
FROM device_models dm, cmd c
WHERE dm.model_code='CS-L10-6K2' AND dmc.model_id=dm.id AND dmc.command_code=c.command_code;

-- 4.2 删除命令表扩展列
ALTER TABLE device_model_commands
    DROP COLUMN IF EXISTS config_domain,
    DROP COLUMN IF EXISTS permission_code,
    DROP COLUMN IF EXISTS confirmation_mode,
    DROP COLUMN IF EXISTS operation_kind;

-- 5. device_model_fields：删除新注册字段，恢复 091 的 V1 通用 ac 键（仅 L10 型号）
DELETE FROM device_model_fields
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND (field_key IN ('ac_output_voltage','ac_output_frequency','output_power','output_apparent_power','output_current')
       OR field_key IN ('mppt_fan_speed','inv_fan_speed','inv_current','parallel_charge_current','work_time_total',
                        'paired_socket','online_socket','on_socket')
       OR group_code = 'info');

INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,decimal_places,sort_order,allow_compare,allow_alarm_rule,default_chart)
SELECT dm.id,pf.field_key,'fields.'||pf.field_key,pf.group_code,c.base_unit,
       CASE WHEN c.field_type IN ('integer','bitmask') THEN 0 ELSE 2 END,
       ROW_NUMBER() OVER (PARTITION BY pf.group_code ORDER BY pf.field_index),
       pf.field_key IN ('ac_active_power','pv_total_power','battery_voltage','battery_soc'),
       pf.field_key IN ('battery_soc','inverter_temperature','boost_temperature','transformer_temperature','fault_code'),
       pf.field_key IN ('ac_active_power','pv_total_power','battery_soc')
FROM device_models dm
JOIN device_protocol_versions pv ON pv.protocol_code='heartbeat' AND pv.version=2
JOIN device_protocol_fields pf ON pf.protocol_version_id=pv.id
JOIN telemetry_field_catalog c ON c.field_key=pf.field_key
WHERE dm.model_code='CS-L10-6K2' AND pf.group_code='ac' AND pf.field_index BETWEEN 0 AND 4
ON CONFLICT(model_id,field_key) DO NOTHING;

-- 6. device_models：关闭并机，移除诊断阈值
UPDATE device_models
SET supports_parallel = FALSE,
    specifications = specifications - 'diagnostics',
    updated_at = NOW()
WHERE model_code = 'CS-L10-6K2';

-- 7. device_protocol_fields：删除 8 个新位置，恢复 bat[5] 冗余位与 battery_soc scale
DELETE FROM device_protocol_fields pf
USING device_protocol_versions pv
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code IN ('fan','diag','sock');

INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,scale,minimum,maximum)
SELECT pv.id,'bat',5,'battery_overcharge','uint8',1,0,1
FROM device_protocol_versions pv WHERE pv.protocol_code='heartbeat' AND pv.version=2
ON CONFLICT (protocol_version_id,group_code,field_index) DO NOTHING;

UPDATE device_protocol_fields pf
SET scale = 0.1, updated_at = NOW()
FROM device_protocol_versions pv
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code='bat' AND pf.field_index = 1;

UPDATE device_protocol_fields pf
SET field_key = v.field_key, updated_at = NOW()
FROM device_protocol_versions pv,
(VALUES
    (0, 'ac_voltage'),
    (1, 'ac_frequency'),
    (2, 'ac_active_power'),
    (3, 'ac_apparent_power'),
    (4, 'ac_current')
) AS v(field_index, field_key)
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code='ac' AND pf.field_index = v.field_index;

-- 8. device_protocol_versions：schema_hash 还原 V2.0
UPDATE device_protocol_versions
SET schema_hash = 'heartbeat-v2-csl10-6k2-20260802', updated_at = NOW()
WHERE protocol_code = 'heartbeat' AND version = 2;

-- 9. 删除 096 新增 catalog 字段（仅删除本次迁移实际新增且无其他型号引用的字段）
DELETE FROM telemetry_field_catalog c WHERE c.field_key IN (
    'ac_output_voltage','ac_output_frequency','output_power','output_apparent_power','output_current',
    'mppt_fan_speed','inv_fan_speed','inv_current','parallel_charge_current','work_time_total',
    'paired_socket','online_socket','on_socket',
    'model','manufacturer','firmware_arm','firmware_esp','firmware_dsp','firmware_bms','device_type',
    'phase','inverter_module','hardware_version','bootloader_version','rated_power_w','rated_voltage',
    'rated_frequency','battery_type','cell_count','temp_sensor_count'
) AND NOT EXISTS (
    SELECT 1 FROM device_model_fields dmf WHERE dmf.field_key = c.field_key
) AND NOT EXISTS (
    SELECT 1 FROM device_protocol_fields dpf WHERE dpf.field_key = c.field_key
);
