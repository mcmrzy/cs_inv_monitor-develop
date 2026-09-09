-- 112: CS-L10-6K2 心跳 V2 新增储能 BMS 扩展组（bms，45 值，additive）
--
-- 背景：接入辰烁储能电池（BBM-5K-48P）后，心跳追加 bms 组（组尾 additive，既有 57 位置冻结不动）：
--   数据链路：储能 BMS PC485 协议 → ARM batterySum1 → 采集器寄存器 0x0440-0x046E → 心跳 bms[45]。
--   协议定义：docs/design/储能BMS遥测扩展协议设计.md §7.7；
--   解析：device-communication/internal/telemetry/heartbeat_v2.go（缺组 = 旧固件/未接电池，QualityPartial，合法）。
-- 变更：
--   1. telemetry_field_catalog 新增 45 个 bms_* 键（全局唯一，bms_ 前缀避免与 V1 cell_voltage_* 冲突）；
--   2. device_protocol_fields 注册 heartbeat v2 组 'bms' 45 个位置；
--   3. schema_hash 更新为 heartbeat-v2-csl10-6k2-v2.2-bms-20260907。
-- 幂等可重放：INSERT ON CONFLICT DO NOTHING。
-- 顺序约束：先 catalog 后 protocol_fields（外键 RESTRICT）。

-- ============================================================
-- 1. telemetry_field_catalog 新增 45 个 bms 字段
-- ============================================================
INSERT INTO telemetry_field_catalog(field_key, field_type, base_unit, category, description, is_timeseries, is_aggregatable, allowed_aggregates) VALUES
('bms_online','integer',NULL,'bms','BMS 在线标志（1=在线，0=离线/未接电池）','TRUE','TRUE','["last","max"]'),
('bms_soc','float','%','bms','BMS 电量 SOC（BMS 口径，区别于 bat 组 DSP 估算）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_soh','float','%','bms','电池健康度 SOH','TRUE','TRUE','["avg","min","max","last"]'),
('bms_capacity_remain','float','Ah','bms','剩余容量','TRUE','TRUE','["avg","min","max","last"]'),
('bms_capacity_full','float','Ah','bms','满充容量 FCC','TRUE','TRUE','["avg","min","max","last"]'),
('bms_capacity_design','float','Ah','bms','额定容量','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cycle_count','integer','次','bms','循环次数','TRUE','TRUE','["last","max"]'),
('bms_cell_voltage_max','float','mV','bms','最高单体电压','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_min','float','mV','bms','最低单体电压','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_diff','float','mV','bms','单体压差','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_max_index','integer',NULL,'bms','最高单体电压序号（0 起）','TRUE','TRUE','["last"]'),
('bms_cell_voltage_min_index','integer',NULL,'bms','最低单体电压序号（0 起）','TRUE','TRUE','["last"]'),
('bms_cell_temp_max','float','°C','bms','电芯温度上限','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_temp_min','float','°C','bms','电芯温度下限','TRUE','TRUE','["avg","min","max","last"]'),
('bms_mos_temp','float','°C','bms','MOS 温度','TRUE','TRUE','["avg","min","max","last"]'),
('bms_env_temp','float','°C','bms','环境温度','TRUE','TRUE','["avg","min","max","last"]'),
('bms_pcb_temp','float','°C','bms','PCB 温度','TRUE','TRUE','["avg","min","max","last"]'),
('bms_battery_work_mode','integer',NULL,'bms','电池工作模式（0静置/1充电/2放电/3初始化/4回充）','TRUE','TRUE','["last"]'),
('bms_mos_status','bitmask',NULL,'bms','MOS 状态（bit0 充MOS bit1 放MOS bit2 预放 bit3 预充）','TRUE','TRUE','["last"]'),
('bms_system_mode','integer',NULL,'bms','BMS 系统状态机编号','TRUE','TRUE','["last"]'),
('bms_chg_request_current','float','A','bms','BMS 请求充电电流（限流）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_chg_request_voltage','float','V','bms','BMS 请求充电电压（限压）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_fault_status','bitmask',NULL,'bms','BMS 故障位图 u32（bit0 短路 bit1 反接 bit2 NTC断线 bit3 采样线断 bit4 AFE通信…）','TRUE','TRUE','["last"]'),
('bms_alarm_w0','bitmask',NULL,'bms','告警等级字 0（告警 0~7 各 2bit：0单体过压 1总压过高 2充电过流 3充电高温 4充电低温 5单体欠压 6总压过低 7放电过流）','TRUE','TRUE','["last"]'),
('bms_alarm_w1','bitmask',NULL,'bms','告警等级字 1（告警 8~15 各 2bit：8放电高温 9放电低温 10SOC过低 11环境高温 12环境低温 13PCB高温 14PCB低温 15MOS高温）','TRUE','TRUE','["last"]'),
('bms_alarm_w2','bitmask',NULL,'bms','告警等级字 2（告警 16~19 各 2bit：16MOS低温 17压差 18温差 19预留）','TRUE','TRUE','["last"]'),
('bms_total_chg_capacity','float','Ah','bms','累计充电容量','TRUE','TRUE','["last","max"]'),
('bms_total_dsg_capacity','float','Ah','bms','累计放电容量','TRUE','TRUE','["last","max"]'),
('bms_cell_voltage_00','float','mV','bms','单体 1 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_01','float','mV','bms','单体 2 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_02','float','mV','bms','单体 3 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_03','float','mV','bms','单体 4 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_04','float','mV','bms','单体 5 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_05','float','mV','bms','单体 6 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_06','float','mV','bms','单体 7 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_07','float','mV','bms','单体 8 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_08','float','mV','bms','单体 9 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_09','float','mV','bms','单体 10 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_10','float','mV','bms','单体 11 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_11','float','mV','bms','单体 12 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_12','float','mV','bms','单体 13 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_13','float','mV','bms','单体 14 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_14','float','mV','bms','单体 15 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_cell_voltage_15','float','mV','bms','单体 16 电压（bit15=均衡）','TRUE','TRUE','["avg","min","max","last"]'),
('bms_balance_bitmap','bitmask',NULL,'bms','均衡位图（每芯 1bit）','TRUE','TRUE','["last"]')
ON CONFLICT (field_key) DO NOTHING;

-- ============================================================
-- 2. device_protocol_fields：注册 heartbeat v2 组 'bms'（45 位置）
-- ============================================================
WITH protocol AS (
    SELECT id FROM device_protocol_versions WHERE protocol_code='heartbeat' AND version=2
), mapping(group_code, field_index, field_key, wire_type, scale, minimum, maximum) AS (VALUES
('bms',0,'bms_online','uint32',1,0,1),
('bms',1,'bms_soc','float32',0.1,0,100),
('bms',2,'bms_soh','float32',0.1,0,100),
('bms',3,'bms_capacity_remain','float32',0.1,0,6553.5),
('bms',4,'bms_capacity_full','float32',0.1,0,6553.5),
('bms',5,'bms_capacity_design','float32',0.1,0,6553.5),
('bms',6,'bms_cycle_count','uint32',1,0,65535),
('bms',7,'bms_cell_voltage_max','uint32',1,0,8191),
('bms',8,'bms_cell_voltage_min','uint32',1,0,8191),
('bms',9,'bms_cell_voltage_diff','uint32',1,0,8191),
('bms',10,'bms_cell_voltage_max_index','uint32',1,0,15),
('bms',11,'bms_cell_voltage_min_index','uint32',1,0,15),
('bms',12,'bms_cell_temp_max','float32',1,-60,150),
('bms',13,'bms_cell_temp_min','float32',1,-60,150),
('bms',14,'bms_mos_temp','float32',1,-40,150),
('bms',15,'bms_env_temp','float32',1,-40,85),
('bms',16,'bms_pcb_temp','float32',1,-40,150),
('bms',17,'bms_battery_work_mode','uint32',1,0,7),
('bms',18,'bms_mos_status','uint32',1,0,15),
('bms',19,'bms_system_mode','uint32',1,0,255),
('bms',20,'bms_chg_request_current','float32',0.1,0,500),
('bms',21,'bms_chg_request_voltage','float32',0.1,0,1000),
('bms',22,'bms_fault_status','uint32',1,0,4294967295),
('bms',23,'bms_alarm_w0','uint32',1,0,65535),
('bms',24,'bms_alarm_w1','uint32',1,0,65535),
('bms',25,'bms_alarm_w2','uint32',1,0,65535),
('bms',26,'bms_total_chg_capacity','float64',1,0,4294967295),
('bms',27,'bms_total_dsg_capacity','float64',1,0,4294967295),
('bms',28,'bms_cell_voltage_00','uint32',1,0,8191),
('bms',29,'bms_cell_voltage_01','uint32',1,0,8191),
('bms',30,'bms_cell_voltage_02','uint32',1,0,8191),
('bms',31,'bms_cell_voltage_03','uint32',1,0,8191),
('bms',32,'bms_cell_voltage_04','uint32',1,0,8191),
('bms',33,'bms_cell_voltage_05','uint32',1,0,8191),
('bms',34,'bms_cell_voltage_06','uint32',1,0,8191),
('bms',35,'bms_cell_voltage_07','uint32',1,0,8191),
('bms',36,'bms_cell_voltage_08','uint32',1,0,8191),
('bms',37,'bms_cell_voltage_09','uint32',1,0,8191),
('bms',38,'bms_cell_voltage_10','uint32',1,0,8191),
('bms',39,'bms_cell_voltage_11','uint32',1,0,8191),
('bms',40,'bms_cell_voltage_12','uint32',1,0,8191),
('bms',41,'bms_cell_voltage_13','uint32',1,0,8191),
('bms',42,'bms_cell_voltage_14','uint32',1,0,8191),
('bms',43,'bms_cell_voltage_15','uint32',1,0,8191),
('bms',44,'bms_balance_bitmap','uint32',1,0,65535)
)
INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,scale,minimum,maximum)
SELECT protocol.id,m.group_code,m.field_index,m.field_key,m.wire_type,m.scale,m.minimum,m.maximum FROM protocol CROSS JOIN mapping m
ON CONFLICT (protocol_version_id,group_code,field_index) DO NOTHING;

-- ============================================================
-- 3. schema_hash 更新（V2.2：57+45=102 值）
-- ============================================================
UPDATE device_protocol_versions
SET schema_hash = 'heartbeat-v2-csl10-6k2-v2.2-bms-20260907', updated_at = NOW()
WHERE protocol_code = 'heartbeat' AND version = 2;
