--
-- 背景：接入辰烁 CS-L10-6K2 48V 离网逆变器（GD32F30x 系统，ARM↔ESP32 采集器协议）。
-- 协议设计见 docs/CS-L10-6K2_MQTT_上报协议设计.md：
--   1. 心跳协议新增 V2 版本（位置数组 50 值：sys[11]/pv[5]/ac[11]/chr[3]/bat[6]/eng[14]）；
--   2. telemetry_field_catalog 新增 28 个字段（CS-L10-6K2 运行参数特有：Buck 电流、
--      变压器/PV 温度、AC 充电、发电机、旁路放电、输出放电等）；
--   3. device_models 注册 CS-L10-6K2，配置显示字段与 27 个控制命令
--      （映射采集器协议控制参数地址 0x0000-0x0053 / UTC 时间 0x00CA-0x00CB）；
--   4. device_telemetry_3min + device_latest_state 新增 28 列。
--
-- 幂等可重放：所有 INSERT 使用 ON CONFLICT DO NOTHING，ALTER 使用 IF NOT EXISTS。

-- ============================================================
-- 1. telemetry_field_catalog 新增字段（28 个）
-- ============================================================
INSERT INTO telemetry_field_catalog(field_key, field_type, base_unit, category, description, allowed_aggregates) VALUES
-- system
('sys_status','bitmask',NULL,'system','系统状态位（12 位：StandBy/Fault/Charge/Discharging/PVCharging/ACCharging/GenCharging/ACBypass/ToLoad/Pvinput/AcInput/GeInput）','["last"]'),
('warning','bitmask',NULL,'system','告警位（64 位）','["last"]'),
('bms_warning','bitmask',NULL,'system','BMS 告警','["last"]'),
('boost_temperature','float','C','system','Boost 温度','["avg","min","max","last"]'),
('transformer_temperature','float','C','system','变压器温度','["avg","min","max","last"]'),
('pv_temperature','float','C','system','PV 温度','["avg","min","max","last"]'),
('battery_overcharge','integer',NULL,'system','过充标志（0/1）','["last"]'),
-- pv
('buck1_current','float','A','pv','Buck1 电流','["avg","min","max","last"]'),
('buck2_current','float','A','pv','Buck2 电流','["avg","min","max","last"]'),
-- ac
('grid_voltage','float','V','ac','电网电压','["avg","min","max","last"]'),
('grid_frequency','float','Hz','ac','电网频率','["avg","min","max","last"]'),
('ac_input_power','float','W','ac','AC 输入有功功率','["avg","min","max","last"]'),
('ac_input_apparent_power','float','VA','ac','AC 输入视在功率','["avg","min","max","last"]'),
('ac_charge_power','float','W','ac','AC 充电功率','["avg","min","max","last"]'),
('ac_charge_apparent_power','float','VA','ac','AC 充电视在功率','["avg","min","max","last"]'),
('ac_charge_current','float','A','ac','AC 充电电流','["avg","min","max","last"]'),
('ac_bypass_power','float','W','ac','AC 旁路放电功率','["avg","min","max","last"]'),
('ac_bypass_apparent_power','float','VA','ac','AC 旁路放电视在功率','["avg","min","max","last"]'),
-- battery
('battery_charge_power','float','W','battery','电池充电功率','["avg","min","max","last"]'),
('battery_discharge_power','float','W','battery','电池放电功率','["avg","min","max","last"]'),
-- energy
('gen_energy_daily','float','kWh','energy','发电机今日发电','["last","max"]'),
('gen_energy_total','float','kWh','energy','发电机总发电','["last","max"]'),
('ac_charge_energy_daily','float','kWh','energy','AC 今日充电','["last","max"]'),
('ac_charge_energy_total','float','kWh','energy','AC 总充电','["last","max"]'),
('ac_bypass_energy_daily','float','kWh','energy','AC 旁路今日放电','["last","max"]'),
('ac_bypass_energy_total','float','kWh','energy','AC 旁路总放电','["last","max"]'),
('output_energy_daily','float','kWh','energy','输出今日放电','["last","max"]'),
('output_energy_total','float','kWh','energy','输出总放电','["last","max"]')
ON CONFLICT (field_key) DO NOTHING;

-- ============================================================
-- 2. device_protocol_versions 新增 heartbeat v2
-- ============================================================
INSERT INTO device_protocol_versions(protocol_code, version, schema_hash, status, released_at)
VALUES ('heartbeat', 2, 'heartbeat-v2-csl10-6k2-20260802', 'released', NOW())
ON CONFLICT (protocol_code, version) DO NOTHING;

-- ============================================================
-- 3. device_protocol_fields：V2 位置数组定义（50 个位置值）
--    wire_type：float32/float64/uint8/uint32/uint64
--    scale：协议原始量纲 → 物理量 缩放系数（如 0.1 = 原始值×0.1）
--    min/max：物理量范围（bounded 校验用）
-- ============================================================
WITH protocol AS (
    SELECT id FROM device_protocol_versions WHERE protocol_code='heartbeat' AND version=2
), mapping(group_code, field_index, field_key, wire_type, scale, minimum, maximum) AS (VALUES
-- sys（11）
('sys',0,'sys_status','uint32',1,0,4095),
('sys',1,'fault_code','uint32',1,0,4294967295),
('sys',2,'warning','uint64',1,0,18446744073709551615),
('sys',3,'bms_warning','uint32',1,0,4294967295),
('sys',4,'inverter_temperature','float32',0.1,-40,100),
('sys',5,'boost_temperature','float32',0.1,-40,120),
('sys',6,'transformer_temperature','float32',0.1,-40,120),
('sys',7,'pv_temperature','float32',0.1,-40,120),
('sys',8,'dc_bus_voltage','float32',0.01,0,500),
('sys',9,'load_percent','float32',0.1,0,120),
('sys',10,'battery_overcharge','uint8',1,0,1),
-- pv（5）
('pv',0,'pv1_voltage','float32',0.1,0,150),
('pv',1,'buck1_current','float32',0.1,0,30),
('pv',2,'pv2_voltage','float32',0.1,0,150),
('pv',3,'buck2_current','float32',0.1,0,30),
('pv',4,'pv_total_power','float32',0.1,0,7500),
-- ac（11）
('ac',0,'ac_voltage','float32',0.1,0,250),
('ac',1,'ac_frequency','float32',0.01,0,55),
('ac',2,'ac_active_power','float32',0.1,0,7500),
('ac',3,'ac_apparent_power','float32',0.1,0,7500),
('ac',4,'ac_current','float32',0.1,0,100),
('ac',5,'grid_voltage','float32',0.1,0,300),
('ac',6,'grid_frequency','float32',0.01,0,55),
('ac',7,'ac_input_power','float32',0.1,0,7500),
('ac',8,'ac_input_apparent_power','float32',0.1,0,7500),
('ac',9,'ac_bypass_power','float32',0.1,0,7500),
('ac',10,'ac_bypass_apparent_power','float32',0.1,0,7500),
-- chr（3）
('chr',0,'ac_charge_power','float32',0.1,0,7500),
('chr',1,'ac_charge_apparent_power','float32',0.1,0,7500),
('chr',2,'ac_charge_current','float32',0.1,0,150),
-- bat（6）
('bat',0,'battery_voltage','float32',0.01,0,70),
('bat',1,'battery_soc','float32',0.1,0,100),
('bat',2,'battery_current','float32',0.1,-150,150),
('bat',3,'battery_charge_power','float32',0.1,0,7500),
('bat',4,'battery_discharge_power','float32',0.1,0,7500),
('bat',5,'battery_overcharge','uint8',1,0,1),
-- eng（14）
('eng',0,'gen_energy_daily','float64',0.1,0,1000000),
('eng',1,'gen_energy_total','float64',0.1,0,1000000000000),
('eng',2,'daily_pv_energy','float64',0.1,0,1000000),
('eng',3,'total_pv_energy','float64',0.1,0,1000000000000),
('eng',4,'ac_charge_energy_daily','float64',0.1,0,1000000),
('eng',5,'ac_charge_energy_total','float64',0.1,0,1000000000000),
('eng',6,'daily_discharge_energy','float64',0.1,0,1000000),
('eng',7,'total_discharge_energy','float64',0.1,0,1000000000000),
('eng',8,'daily_charge_energy','float64',0.1,0,1000000),
('eng',9,'total_charge_energy','float64',0.1,0,1000000000000),
('eng',10,'ac_bypass_energy_daily','float64',0.1,0,1000000),
('eng',11,'ac_bypass_energy_total','float64',0.1,0,1000000000000),
('eng',12,'output_energy_daily','float64',0.1,0,1000000),
('eng',13,'output_energy_total','float64',0.1,0,1000000000000)
)
INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,scale,minimum,maximum)
SELECT protocol.id,m.group_code,m.field_index,m.field_key,m.wire_type,m.scale,m.minimum,m.maximum FROM protocol CROSS JOIN mapping m
ON CONFLICT (protocol_version_id,group_code,field_index) DO NOTHING;

-- ============================================================
-- 4. device_models 注册 CS-L10-6K2
-- ============================================================
INSERT INTO device_models(model_code, model_name, manufacturer, category, rated_power_kw, description, is_active)
VALUES('CS-L10-6K2', 'CS-L10-6K2 48V 离网逆变器', '辰烁科技', 'inverter', 6.2,
       'GD32F30x 系统，ARM↔ESP32 采集器协议（PPP 帧 + TEA 加密），V2 心跳协议', TRUE)
ON CONFLICT(model_code) DO NOTHING;

UPDATE device_models dm SET
    heartbeat_protocol_id=p.id, rated_power_w=6200, rated_voltage_v=220,
    rated_frequency_hz=50, battery_voltage_v=51.2, battery_type='LiFePO4',
    cell_count=NULL, mppt_count=2, supports_parallel=FALSE,
    specifications=jsonb_build_object('phase','single','grid_mode','off_grid','uart_protocol','collector_v1'),
    lifecycle_status='active'
FROM device_protocol_versions p
WHERE dm.model_code='CS-L10-6K2' AND p.protocol_code='heartbeat' AND p.version=2;

-- ============================================================
-- 5. device_model_fields 显示配置（仅 V2 协议涉及的字段）
-- ============================================================
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
WHERE dm.model_code='CS-L10-6K2'
ON CONFLICT(model_id,field_key) DO NOTHING;

-- ============================================================
-- 6. device_model_commands 控制命令（映射采集器协议控制参数地址）
--    parameter_schema 驱动前端动态表单（integer 为协议原始量纲）
-- ============================================================
WITH commands(command_code,display_name_key,parameter_schema,timeout_seconds,risk_level) AS (VALUES
-- 通用
('set_output_priority','commands.set_output_priority','{"args":[{"key":"priority","type":"integer","min":0,"max":2,"unit":""}]}'::jsonb,30,1),
('set_max_charge_current','commands.set_max_charge_current','{"args":[{"key":"current_x10","type":"integer","min":0,"max":600,"unit":"0.1A"}]}'::jsonb,30,1),
('set_battery_capacity','commands.set_battery_capacity','{"args":[{"key":"capacity_ah","type":"integer","min":0,"max":2000,"unit":"Ah"}]}'::jsonb,30,1),
('set_battery_type','commands.set_battery_type','{"args":[{"key":"battery_type","type":"integer","min":0,"max":2,"unit":""}]}'::jsonb,30,1),
('set_output_voltage','commands.set_output_voltage','{"args":[{"key":"voltage_v","type":"integer","min":200,"max":250,"unit":"V"}]}'::jsonb,30,1),
('set_output_frequency','commands.set_output_frequency','{"args":[{"key":"freq_hz","type":"integer","enum":[50,60],"unit":"Hz"}]}'::jsonb,30,1),
('set_master_slave','commands.set_master_slave','{"args":[{"key":"mode","type":"integer","enum":[0,1],"unit":""}]}'::jsonb,30,1),
('set_ac_charge_current','commands.set_ac_charge_current','{"args":[{"key":"current_x10","type":"integer","min":0,"max":1500,"unit":"0.1A"}]}'::jsonb,30,1),
('set_ac_output_mode','commands.set_ac_output_mode','{"args":[{"key":"mode","type":"integer","enum":[0,1,2],"unit":""}]}'::jsonb,30,2),
('set_charge_priority','commands.set_charge_priority','{"args":[{"key":"priority","type":"integer","enum":[0,1,2],"unit":""}]}'::jsonb,30,2),
('set_low_volt_return_utl','commands.set_low_volt_return_utl','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}'::jsonb,30,2),
('set_high_volt_return_bat','commands.set_high_volt_return_bat','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}'::jsonb,30,2),
-- 充放电
('set_soc_cutoff','commands.set_soc_cutoff','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,30,2),
('set_charge_cutoff','commands.set_charge_cutoff','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"},{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}'::jsonb,30,2),
-- 均衡
('set_equalize_enable','commands.set_equalize_enable','{"args":[{"key":"enable","type":"boolean"}]}'::jsonb,30,2),
('set_equalize_voltage','commands.set_equalize_voltage','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":650,"unit":"0.1V"}]}'::jsonb,30,2),
('set_equalize_time','commands.set_equalize_time','{"args":[{"key":"time_min","type":"integer","min":0,"max":720,"unit":"min"}]}'::jsonb,30,2),
-- 发电机 / SOC 策略
('set_gen_start_voltage','commands.set_gen_start_voltage','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}'::jsonb,30,2),
('set_gen_stop_voltage','commands.set_gen_stop_voltage','{"args":[{"key":"voltage_x10","type":"integer","min":400,"max":600,"unit":"0.1V"}]}'::jsonb,30,2),
('set_soc_back_utl','commands.set_soc_back_utl','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,30,2),
('set_soc_back_bat','commands.set_soc_back_bat','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,30,2),
('set_soc_back_gen','commands.set_soc_back_gen','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,30,2),
('set_soc_close_gen','commands.set_soc_close_gen','{"args":[{"key":"soc","type":"integer","min":0,"max":100,"unit":"%"}]}'::jsonb,30,2),
('set_gen_rate_watt','commands.set_gen_rate_watt','{"args":[{"key":"watt","type":"integer","min":0,"max":10000,"unit":"W"}]}'::jsonb,30,2),
-- 其他
('set_alarm_control','commands.set_alarm_control','{"args":[{"key":"alarm_ctrl","type":"integer","min":0,"max":255,"unit":""}]}'::jsonb,30,2),
('set_buzzer','commands.set_buzzer','{"args":[{"key":"enable","type":"boolean"}]}'::jsonb,30,1),
('set_utc_time','commands.set_utc_time','{"args":[{"key":"utc","type":"integer","min":0,"max":4102444800,"unit":"s"}]}'::jsonb,30,1)
)
INSERT INTO device_model_commands(model_id,command_code,display_name_key,parameter_schema,timeout_seconds,risk_level)
SELECT dm.id,c.command_code,c.display_name_key,c.parameter_schema,c.timeout_seconds,c.risk_level
FROM device_models dm CROSS JOIN commands c WHERE dm.model_code='CS-L10-6K2'
ON CONFLICT(model_id,command_code) DO NOTHING;

-- ============================================================
-- 7. device_telemetry_3min + device_latest_state 新增列（28 列）
-- ============================================================
ALTER TABLE device_telemetry_3min
    ADD COLUMN IF NOT EXISTS sys_status BIGINT,
    ADD COLUMN IF NOT EXISTS warning BIGINT,
    ADD COLUMN IF NOT EXISTS bms_warning BIGINT,
    ADD COLUMN IF NOT EXISTS battery_overcharge SMALLINT,
    ADD COLUMN IF NOT EXISTS boost_temperature REAL,
    ADD COLUMN IF NOT EXISTS transformer_temperature REAL,
    ADD COLUMN IF NOT EXISTS pv_temperature REAL,
    ADD COLUMN IF NOT EXISTS buck1_current REAL,
    ADD COLUMN IF NOT EXISTS buck2_current REAL,
    ADD COLUMN IF NOT EXISTS grid_voltage REAL,
    ADD COLUMN IF NOT EXISTS grid_frequency REAL,
    ADD COLUMN IF NOT EXISTS ac_input_power REAL,
    ADD COLUMN IF NOT EXISTS ac_input_apparent_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_apparent_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_current REAL,
    ADD COLUMN IF NOT EXISTS ac_bypass_power REAL,
    ADD COLUMN IF NOT EXISTS ac_bypass_apparent_power REAL,
    ADD COLUMN IF NOT EXISTS battery_charge_power REAL,
    ADD COLUMN IF NOT EXISTS battery_discharge_power REAL,
    ADD COLUMN IF NOT EXISTS gen_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS gen_energy_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_charge_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_charge_energy_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_bypass_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_bypass_energy_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS output_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS output_energy_total DOUBLE PRECISION;

ALTER TABLE device_latest_state
    ADD COLUMN IF NOT EXISTS sys_status BIGINT,
    ADD COLUMN IF NOT EXISTS warning BIGINT,
    ADD COLUMN IF NOT EXISTS bms_warning BIGINT,
    ADD COLUMN IF NOT EXISTS battery_overcharge SMALLINT,
    ADD COLUMN IF NOT EXISTS boost_temperature REAL,
    ADD COLUMN IF NOT EXISTS transformer_temperature REAL,
    ADD COLUMN IF NOT EXISTS pv_temperature REAL,
    ADD COLUMN IF NOT EXISTS buck1_current REAL,
    ADD COLUMN IF NOT EXISTS buck2_current REAL,
    ADD COLUMN IF NOT EXISTS grid_voltage REAL,
    ADD COLUMN IF NOT EXISTS grid_frequency REAL,
    ADD COLUMN IF NOT EXISTS ac_input_power REAL,
    ADD COLUMN IF NOT EXISTS ac_input_apparent_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_apparent_power REAL,
    ADD COLUMN IF NOT EXISTS ac_charge_current REAL,
    ADD COLUMN IF NOT EXISTS ac_bypass_power REAL,
    ADD COLUMN IF NOT EXISTS ac_bypass_apparent_power REAL,
    ADD COLUMN IF NOT EXISTS battery_charge_power REAL,
    ADD COLUMN IF NOT EXISTS battery_discharge_power REAL,
    ADD COLUMN IF NOT EXISTS gen_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS gen_energy_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_charge_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_charge_energy_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_bypass_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ac_bypass_energy_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS output_energy_daily DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS output_energy_total DOUBLE PRECISION;
