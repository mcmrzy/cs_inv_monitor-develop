--
-- 背景：CS-L10-6K2 协议升级 V2.1（协议设计见 docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md）：
--   1. 修正 091 偏差：ac[0]-ac[4] 键名统一为文档键名（ac_output_voltage 等）、删除 bat[5] 冗余位、
--      battery_soc scale 0.1→1（catalog 无 scale 列，仅 protocol_fields 层修正）；
--   2. 心跳 49→57 值：新增 fan[2]/diag[3]/sock[3] 共 8 个位置（schema_hash 更新）；
--   3. info 17 字段透传：devices 新增 phase/inverter_module/bootloader_version/rated_power_w/info_reported_at；
--   4. config v2 语义键值对：新表 device_config_schema（42 键）+ device_config_changes 审计；
--   5. 利用层：新表 device_diagnostics + device_health_history；device_models 开启并机与诊断阈值；
--   6. 命令补齐：18 条控制参数命令（工程单位）+ 3 条查询命令；既有 24 条命令 schema 统一为工程单位。
--
-- 幂等可重放：INSERT 使用 ON CONFLICT DO NOTHING，ALTER 使用 IF NOT EXISTS / IF EXISTS。
-- 顺序约束：catalog 被 protocol_fields/model_fields 外键 RESTRICT 引用 → 先 INSERT 新键，再 UPDATE/DELETE 引用，最后清理。
-- 092-095 已被占用（sort_order/station_country/notify_prefs/alias），本次全部变更并入 096。

-- ============================================================
-- 1. telemetry_field_catalog 新增字段（30 个：5 ac + 8 心跳 + 17 info）
-- ============================================================
INSERT INTO telemetry_field_catalog(field_key, field_type, base_unit, category, description, is_timeseries, is_aggregatable, allowed_aggregates) VALUES
-- ac（文档键名，与 V1 通用键 ac_voltage 等并存，V2 协议使用）
('ac_output_voltage','float','V','ac','AC 输出电压','TRUE','TRUE','["avg","min","max","last"]'),
('ac_output_frequency','float','Hz','ac','AC 输出频率','TRUE','TRUE','["avg","min","max","last"]'),
('output_power','float','W','ac','输出有功功率','TRUE','TRUE','["avg","min","max","last"]'),
('output_apparent_power','float','VA','ac','输出视在功率','TRUE','TRUE','["avg","min","max","last"]'),
('output_current','float','A','ac','输出电流','TRUE','TRUE','["avg","min","max","last"]'),
-- fan / diag / sock（V2.1 心跳新组）
('mppt_fan_speed','float','%','fan','MPPT 风扇转速百分比','TRUE','TRUE','["avg","min","max","last"]'),
('inv_fan_speed','float','%','fan','逆变风扇转速百分比','TRUE','TRUE','["avg","min","max","last"]'),
('inv_current','float','A','diag','逆变器输出电流','TRUE','TRUE','["avg","min","max","last"]'),
('parallel_charge_current','float','A','diag','并机充电电流','TRUE','TRUE','["avg","min","max","last"]'),
('work_time_total','float','s','diag','累计运行时长（秒）','TRUE','TRUE','["last","max"]'),
('paired_socket','integer',NULL,'sock','已配对插座位掩码（u16）','TRUE','TRUE','["last"]'),
('online_socket','integer',NULL,'sock','在线插座位掩码（u16）','TRUE','TRUE','["last"]'),
('on_socket','integer',NULL,'sock','运行中插座位掩码（u16）','TRUE','TRUE','["last"]'),
-- info（静态只读，非时序）
('model','string',NULL,'info','设备型号编码','FALSE','FALSE','[]'),
('manufacturer','string',NULL,'info','制造商','FALSE','FALSE','[]'),
('firmware_arm','string',NULL,'info','ARM 主控固件版本','FALSE','FALSE','[]'),
('firmware_esp','string',NULL,'info','ESP32 采集器固件版本','FALSE','FALSE','[]'),
('firmware_dsp','string',NULL,'info','DSP 固件版本','FALSE','FALSE','[]'),
('firmware_bms','string',NULL,'info','BMS 固件版本（L10 无直连）','FALSE','FALSE','[]'),
('device_type','string',NULL,'info','设备类别（off_grid_inverter）','FALSE','FALSE','[]'),
('phase','string',NULL,'info','相数（single）','FALSE','FALSE','[]'),
('inverter_module','string',NULL,'info','模块号（BCD 转字符串，出厂追溯）','FALSE','FALSE','[]'),
('hardware_version','string',NULL,'info','硬件版本','FALSE','FALSE','[]'),
('bootloader_version','string',NULL,'info','Bootloader 版本','FALSE','FALSE','[]'),
('rated_power_w','integer','W','info','额定功率（协议原值 W）','FALSE','FALSE','[]'),
('rated_voltage','float','V','info','额定电压','FALSE','FALSE','[]'),
('rated_frequency','float','Hz','info','额定频率','FALSE','FALSE','[]'),
('battery_type','string',NULL,'info','电池类型（LiFePO4/NCM/LeadAcid/Other）','FALSE','FALSE','[]'),
('cell_count','integer','节','info','电池电芯节数','FALSE','FALSE','[]'),
('temp_sensor_count','integer','个','info','温度传感器数量','FALSE','FALSE','[]')
ON CONFLICT (field_key) DO NOTHING;

-- ============================================================
-- 1.1 兼容修复：device_protocol_versions / device_protocol_fields
--     建表迁移未定义 updated_at 列（schema.sql 仅 created_at），
--     本节及后续 UPDATE 依赖该列；IF NOT EXISTS 对全新库幂等跳过
-- ============================================================
ALTER TABLE device_protocol_versions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE device_protocol_fields   ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- ============================================================
-- 2. device_protocol_versions：V2 心跳 schema_hash 更新
-- ============================================================
UPDATE device_protocol_versions
SET schema_hash = 'heartbeat-v2-csl10-6k2-v2.1-20260805', updated_at = NOW()
WHERE protocol_code = 'heartbeat' AND version = 2;

-- ============================================================
-- 3. device_protocol_fields：键名修正 + bat[5] 删除 + 新增 8 位置（57 值）
-- ============================================================
-- 3.1 ac[0]-ac[4] 键名统一为文档键名（091 误用 V1 通用键名）
UPDATE device_protocol_fields pf
SET field_key = v.field_key, updated_at = NOW()
FROM device_protocol_versions pv,
(VALUES
    (0, 'ac_output_voltage'),
    (1, 'ac_output_frequency'),
    (2, 'output_power'),
    (3, 'output_apparent_power'),
    (4, 'output_current')
) AS v(field_index, field_key)
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code='ac' AND pf.field_index = v.field_index;

-- 3.2 battery_soc scale 0.1 → 1（ARM 上报整数 %）
UPDATE device_protocol_fields pf
SET scale = 1, updated_at = NOW()
FROM device_protocol_versions pv
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code='bat' AND pf.field_index = 1;

-- 3.3 删除 bat[5] 冗余位（battery_overcharge 仅 sys[10] 一处）
DELETE FROM device_protocol_fields pf
USING device_protocol_versions pv
WHERE pv.protocol_code='heartbeat' AND pv.version=2
  AND pf.protocol_version_id = pv.id AND pf.group_code='bat' AND pf.field_index = 5;

-- 3.4 新增 fan[2]/diag[3]/sock[3] 共 8 个位置（组尾追加，纯 additive）
WITH protocol AS (
    SELECT id FROM device_protocol_versions WHERE protocol_code='heartbeat' AND version=2
), mapping(group_code, field_index, field_key, wire_type, scale, minimum, maximum) AS (VALUES
('fan',0,'mppt_fan_speed','float32',1,0,100),
('fan',1,'inv_fan_speed','float32',1,0,100),
('diag',0,'inv_current','float32',0.1,0,100),
('diag',1,'parallel_charge_current','float32',1,0,600),
('diag',2,'work_time_total','float64',1,0,4294967295),
('sock',0,'paired_socket','uint32',1,0,65535),
('sock',1,'online_socket','uint32',1,0,65535),
('sock',2,'on_socket','uint32',1,0,65535)
)
INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,scale,minimum,maximum)
SELECT protocol.id,m.group_code,m.field_index,m.field_key,m.wire_type,m.scale,m.minimum,m.maximum FROM protocol CROSS JOIN mapping m
ON CONFLICT (protocol_version_id,group_code,field_index) DO NOTHING;

-- ============================================================
-- 4. device_models：开启并机 + 诊断/健康度阈值（14.5，待厂家签字）
-- ============================================================
UPDATE device_models
SET supports_parallel = TRUE,
    specifications = specifications || '{"diagnostics":{"fan_speed_low_percent":30,"fan_abnormal_temp_c":70,"overheat_temp_c":85,"health_temp_high_c":75,"maintenance_hours":5000,"deduct_fault":30,"deduct_warning":10,"deduct_temp_high":15,"deduct_fan_abnormal":15,"deduct_low_soc":10,"deduct_parallel_offline":5}}'::jsonb,
    updated_at = NOW()
WHERE model_code = 'CS-L10-6K2';

-- ============================================================
-- 5. device_model_fields：ac 键名修正（DELETE+INSERT，UNIQUE(model_id,field_key)）+ 新增 8 心跳 + 17 info 字段
-- ============================================================
-- 5.1 删除 091 误注册的 V1 通用 ac 键（仅 L10 型号）
DELETE FROM device_model_fields
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2')
  AND field_key IN ('ac_voltage','ac_frequency','ac_active_power','ac_apparent_power','ac_current');

-- 5.2 注册新 ac 键（与 protocol_fields 键名一致）
INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,decimal_places,sort_order,allow_compare,allow_alarm_rule,default_chart)
SELECT dm.id, pf.field_key, 'fields.'||pf.field_key, pf.group_code, c.base_unit,
       CASE WHEN c.field_type IN ('integer','bitmask') THEN 0 ELSE 2 END,
       pf.field_index,
       pf.field_key IN ('output_power','pv_total_power','battery_voltage','battery_soc'),
       pf.field_key IN ('battery_soc','inverter_temperature','boost_temperature','transformer_temperature','fault_code'),
       pf.field_key IN ('output_power','pv_total_power','battery_soc')
FROM device_models dm
JOIN device_protocol_versions pv ON pv.protocol_code='heartbeat' AND pv.version=2
JOIN device_protocol_fields pf ON pf.protocol_version_id=pv.id AND pf.group_code='ac' AND pf.field_index BETWEEN 0 AND 4
JOIN telemetry_field_catalog c ON c.field_key=pf.field_key
WHERE dm.model_code='CS-L10-6K2'
ON CONFLICT(model_id,field_key) DO NOTHING;

-- 5.3 注册 fan/diag/sock 新 8 遥测字段
INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,decimal_places,sort_order,allow_compare,allow_alarm_rule,default_chart)
SELECT dm.id, pf.field_key, 'fields.'||pf.field_key, pf.group_code, c.base_unit,
       CASE WHEN c.field_type IN ('integer','bitmask') THEN 0 ELSE 2 END,
       pf.field_index,
       FALSE,
       pf.field_key IN ('inv_fan_speed','mppt_fan_speed','inv_current','work_time_total','paired_socket'),
       FALSE
FROM device_models dm
JOIN device_protocol_versions pv ON pv.protocol_code='heartbeat' AND pv.version=2
JOIN device_protocol_fields pf ON pf.protocol_version_id=pv.id AND pf.group_code IN ('fan','diag','sock')
JOIN telemetry_field_catalog c ON c.field_key=pf.field_key
WHERE dm.model_code='CS-L10-6K2'
ON CONFLICT(model_id,field_key) DO NOTHING;

-- 5.4 注册 info 组静态字段（group_code='info'、非实时——App 端 _normalizeGroupName 已支持 info→device_info 渲染）
INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,decimal_places,sort_order,is_supported,is_visible,show_realtime,show_history,allow_compare,allow_alarm_rule,default_chart)
SELECT dm.id, c.field_key, 'fields.'||c.field_key, 'info', c.base_unit,
       CASE WHEN c.field_type IN ('string') THEN 0 ELSE 2 END,
       ROW_NUMBER() OVER (ORDER BY c.field_key),
       TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE
FROM device_models dm
CROSS JOIN telemetry_field_catalog c
WHERE dm.model_code='CS-L10-6K2' AND c.category='info'
ON CONFLICT(model_id,field_key) DO NOTHING;

-- ============================================================
-- 6. device_model_commands：加列 + 既有命令 schema 工程单位化 + 补 18 控制命令 + 3 查询命令
-- ============================================================
ALTER TABLE device_model_commands
    ADD COLUMN IF NOT EXISTS config_domain VARCHAR(32),
    ADD COLUMN IF NOT EXISTS permission_code VARCHAR(64) NOT NULL DEFAULT 'device:control',
    ADD COLUMN IF NOT EXISTS confirmation_mode VARCHAR(20),
    ADD COLUMN IF NOT EXISTS operation_kind VARCHAR(20) NOT NULL DEFAULT 'write';

-- 6.1 既有 24 条控制参数命令：parameter_schema 统一为工程单位（与 device_config_schema / config v2 一致），
--     并标注 config_domain（四分组）；set_master_slave 提升为危险参数（risk 3 + modal 确认）。
--     set_charge_cutoff/set_gen_rate_watt/set_utc_time 不在 42 键内，保持原 schema（config_domain=NULL）。
WITH cmd(domain, command_code, parameter_schema) AS (VALUES
('general','set_output_priority','{"args":[{"key":"value","type":"integer","enum":[0,1,2],"unit":""}]}'),
('hybrid','set_max_charge_current','{"args":[{"key":"value","type":"number","min":0,"max":60,"unit":"A"}]}'),
('general','set_battery_capacity','{"args":[{"key":"value","type":"number","min":0,"max":2000,"unit":"Ah"}]}'),
('general','set_battery_type','{"args":[{"key":"value","type":"integer","enum":[0,1,2],"unit":""}]}'),
('application','set_output_voltage','{"args":[{"key":"value","type":"number","min":200,"max":250,"unit":"V"}]}'),
('application','set_output_frequency','{"args":[{"key":"value","type":"number","min":45,"max":55,"unit":"Hz"}]}'),
('parallel','set_master_slave','{"args":[{"key":"value","type":"integer","enum":[0,1],"unit":""}]}'),
('hybrid','set_ac_charge_current','{"args":[{"key":"value","type":"number","min":0,"max":150,"unit":"A"}]}'),
('application','set_ac_output_mode','{"args":[{"key":"value","type":"integer","enum":[0,1,2],"unit":""}]}'),
('hybrid','set_charge_priority','{"args":[{"key":"value","type":"integer","enum":[0,1,2],"unit":""}]}'),
('application','set_low_volt_return_utl','{"args":[{"key":"value","type":"number","min":40,"max":60,"unit":"V"}]}'),
('application','set_high_volt_return_bat','{"args":[{"key":"value","type":"number","min":40,"max":60,"unit":"V"}]}'),
('hybrid','set_soc_cutoff','{"args":[{"key":"value","type":"number","min":0,"max":100,"unit":"%"}]}'),
('hybrid','set_equalize_enable','{"args":[{"key":"value","type":"boolean"}]}'),
('hybrid','set_equalize_voltage','{"args":[{"key":"value","type":"number","min":40,"max":65,"unit":"V"}]}'),
('hybrid','set_equalize_time','{"args":[{"key":"value","type":"number","min":0,"max":720,"unit":"min"}]}'),
('hybrid','set_gen_start_voltage','{"args":[{"key":"value","type":"number","min":40,"max":60,"unit":"V"}]}'),
('hybrid','set_gen_stop_voltage','{"args":[{"key":"value","type":"number","min":40,"max":60,"unit":"V"}]}'),
('hybrid','set_soc_back_utl','{"args":[{"key":"value","type":"number","min":0,"max":100,"unit":"%"}]}'),
('hybrid','set_soc_back_bat','{"args":[{"key":"value","type":"number","min":0,"max":100,"unit":"%"}]}'),
('hybrid','set_soc_back_gen','{"args":[{"key":"value","type":"number","min":0,"max":100,"unit":"%"}]}'),
('hybrid','set_soc_close_gen','{"args":[{"key":"value","type":"number","min":0,"max":100,"unit":"%"}]}'),
('general','set_alarm_control','{"args":[{"key":"value","type":"integer","min":0,"max":255,"unit":""}]}'),
('general','set_buzzer','{"args":[{"key":"value","type":"boolean"}]}')
)
UPDATE device_model_commands dmc
SET config_domain = c.domain,
    parameter_schema = c.parameter_schema::jsonb,
    operation_kind = 'write',
    updated_at = NOW()
FROM device_models dm, cmd c
WHERE dm.model_code='CS-L10-6K2' AND dmc.model_id=dm.id AND dmc.command_code=c.command_code;

-- set_master_slave：危险参数（主从模式切换影响整机供电拓扑），提升风险等级并要求二次确认
UPDATE device_model_commands dmc
SET risk_level = 3, confirmation_mode = 'modal', updated_at = NOW()
FROM device_models dm
WHERE dm.model_code='CS-L10-6K2' AND dmc.model_id=dm.id AND dmc.command_code='set_master_slave';

-- 6.2 补 18 条控制参数命令（9.2 表 42 键中缺失部分，parameter_schema 为工程单位）
WITH commands(command_code,display_name_key,parameter_schema,risk_level,config_domain) AS (VALUES
('set_ac_volt_range','commands.set_ac_volt_range','{"args":[{"key":"value","type":"integer","enum":[0,1,2],"unit":""}]}'::jsonb,1,'application'),
('set_overload_restart','commands.set_overload_restart','{"args":[{"key":"value","type":"boolean"}]}'::jsonb,2,'general'),
('set_high_temp_restart','commands.set_high_temp_restart','{"args":[{"key":"value","type":"boolean"}]}'::jsonb,2,'general'),
('set_backlight_ctrl','commands.set_backlight_ctrl','{"args":[{"key":"value","type":"integer","enum":[0,1,2,3],"unit":""}]}'::jsonb,1,'general'),
('set_power_shutdown_alarm','commands.set_power_shutdown_alarm','{"args":[{"key":"value","type":"boolean"}]}'::jsonb,2,'general'),
('set_overload_use_city_power','commands.set_overload_use_city_power','{"args":[{"key":"value","type":"boolean"}]}'::jsonb,2,'application'),
('set_max_discharge_current','commands.set_max_discharge_current','{"args":[{"key":"value","type":"number","min":0,"max":150,"unit":"A"}]}'::jsonb,2,'hybrid'),
('set_max_chg_curr','commands.set_max_chg_curr','{"args":[{"key":"value","type":"number","min":0,"max":150,"unit":"A"}]}'::jsonb,2,'hybrid'),
('set_recover_threshold_volt','commands.set_recover_threshold_volt','{"args":[{"key":"value","type":"number","min":40,"max":60,"unit":"V"}]}'::jsonb,2,'application'),
('set_solar_power_balance','commands.set_solar_power_balance','{"args":[{"key":"value","type":"boolean"}]}'::jsonb,2,'hybrid'),
('set_li_bat_material','commands.set_li_bat_material','{"args":[{"key":"value","type":"integer","enum":[0,1],"unit":""}]}'::jsonb,1,'general'),
('set_cell_serial_lifepo4','commands.set_cell_serial_lifepo4','{"args":[{"key":"value","type":"number","min":4,"max":32,"unit":"节"}]}'::jsonb,1,'general'),
('set_cell_serial_li_nmc','commands.set_cell_serial_li_nmc','{"args":[{"key":"value","type":"number","min":4,"max":32,"unit":"节"}]}'::jsonb,1,'general'),
('set_equalize_timeout','commands.set_equalize_timeout','{"args":[{"key":"value","type":"number","min":0,"max":1440,"unit":"min"}]}'::jsonb,2,'hybrid'),
('set_equalize_interval','commands.set_equalize_interval','{"args":[{"key":"value","type":"number","min":0,"max":90,"unit":"day"}]}'::jsonb,2,'hybrid'),
('set_equalize_activate','commands.set_equalize_activate','{"args":[{"key":"value","type":"boolean"}]}'::jsonb,2,'hybrid'),
('set_charge_time','commands.set_charge_time','{"args":[{"key":"value","type":"number","min":0,"max":1440,"unit":"min"}]}'::jsonb,2,'hybrid'),
('set_close_charge_time','commands.set_close_charge_time','{"args":[{"key":"value","type":"number","min":0,"max":1440,"unit":"min"}]}'::jsonb,2,'hybrid')
)
INSERT INTO device_model_commands(model_id,command_code,display_name_key,parameter_schema,timeout_seconds,risk_level,config_domain,operation_kind)
SELECT dm.id,c.command_code,c.display_name_key,c.parameter_schema,30,c.risk_level,c.config_domain,'write'
FROM device_models dm CROSS JOIN commands c WHERE dm.model_code='CS-L10-6K2'
ON CONFLICT(model_id,command_code) DO NOTHING;

-- 6.3 补 3 条查询命令（驱动"刷新设备信息/刷新数据/刷新配置"按钮）
INSERT INTO device_model_commands(model_id,command_code,display_name_key,parameter_schema,timeout_seconds,risk_level,config_domain,operation_kind)
SELECT dm.id,c.command_code,c.display_name_key,'[]'::jsonb,10,1,NULL,'query'
FROM device_models dm CROSS JOIN (VALUES
    ('query_telemetry','commands.query_telemetry'),
    ('query_info','commands.query_info'),
    ('query_config','commands.query_config')
) AS c(command_code, display_name_key)
WHERE dm.model_code='CS-L10-6K2'
ON CONFLICT(model_id,command_code) DO NOTHING;

-- ============================================================
-- 7. device_telemetry_3min + device_latest_state 新增 8 列 + health_score
-- ============================================================
ALTER TABLE device_telemetry_3min
    ADD COLUMN IF NOT EXISTS mppt_fan_speed REAL,
    ADD COLUMN IF NOT EXISTS inv_fan_speed REAL,
    ADD COLUMN IF NOT EXISTS inv_current REAL,
    ADD COLUMN IF NOT EXISTS parallel_charge_current REAL,
    ADD COLUMN IF NOT EXISTS work_time_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS paired_socket INTEGER,
    ADD COLUMN IF NOT EXISTS online_socket INTEGER,
    ADD COLUMN IF NOT EXISTS on_socket INTEGER;

ALTER TABLE device_latest_state
    ADD COLUMN IF NOT EXISTS mppt_fan_speed REAL,
    ADD COLUMN IF NOT EXISTS inv_fan_speed REAL,
    ADD COLUMN IF NOT EXISTS inv_current REAL,
    ADD COLUMN IF NOT EXISTS parallel_charge_current REAL,
    ADD COLUMN IF NOT EXISTS work_time_total DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS paired_socket INTEGER,
    ADD COLUMN IF NOT EXISTS online_socket INTEGER,
    ADD COLUMN IF NOT EXISTS on_socket INTEGER,
    ADD COLUMN IF NOT EXISTS health_score REAL;

-- ============================================================
-- 8. devices 新增设备信息列 + 索引
-- ============================================================
ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS phase VARCHAR(20) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS inverter_module VARCHAR(64) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS bootloader_version VARCHAR(50) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS rated_power_w INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS info_reported_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_devices_model ON devices(model) WHERE deleted_at IS NULL;

-- ============================================================
-- 9. 新表：诊断 / 健康度 / config schema / 配置审计
-- ============================================================
CREATE TABLE IF NOT EXISTS device_diagnostics (
    device_sn  VARCHAR(50) NOT NULL,
    rule_code  VARCHAR(64) NOT NULL,
    level      VARCHAR(16) NOT NULL CHECK (level IN ('fault','warning','info')),
    status     VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active','resolved')),
    detail     JSONB NOT NULL DEFAULT '{}'::jsonb,
    first_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    count      INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (device_sn, rule_code)
);
CREATE INDEX IF NOT EXISTS idx_device_diagnostics_sn_status ON device_diagnostics(device_sn, status);

CREATE TABLE IF NOT EXISTS device_health_history (
    id         BIGSERIAL PRIMARY KEY,
    device_sn  VARCHAR(50) NOT NULL,
    event_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    score      REAL NOT NULL,
    level      VARCHAR(16) NOT NULL,
    factors    JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_device_health_history_sn_time ON device_health_history(device_sn, event_time DESC);

CREATE TABLE IF NOT EXISTS device_config_schema (
    param_key          VARCHAR(64) PRIMARY KEY,
    group_code         VARCHAR(32) NOT NULL CHECK (group_code IN ('general','application','hybrid','parallel')),
    sub_group          VARCHAR(32),
    control_type       VARCHAR(16) NOT NULL CHECK (control_type IN ('number','enum','boolean')),
    scale              NUMERIC NOT NULL DEFAULT 1,
    unit               VARCHAR(20),
    min                NUMERIC,
    max                NUMERIC,
    enum_map           JSONB,
    step               NUMERIC,
    permission_code    VARCHAR(64) NOT NULL DEFAULT 'device:control',
    confirmation_mode  VARCHAR(20),
    display_name_key   VARCHAR(128) NOT NULL,
    sort_order         INTEGER NOT NULL DEFAULT 0,
    visibility         JSONB,
    validation         JSONB,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE device_config_schema IS 'config v2 参数 schema（42 键），驱动 SchemaGroupPanel 分组渲染与服务端校验；visibility 描述条件联动（如 battery_type 驱动铅酸/锂电参数显示）';

CREATE TABLE IF NOT EXISTS device_config_changes (
    id         BIGSERIAL PRIMARY KEY,
    device_sn  VARCHAR(50) NOT NULL,
    param_key  VARCHAR(64) NOT NULL,
    old_value  JSONB NOT NULL DEFAULT '{}'::jsonb,
    new_value  JSONB NOT NULL DEFAULT '{}'::jsonb,
    source     VARCHAR(20) NOT NULL DEFAULT 'reported' CHECK (source IN ('reported','desired','system')),
    rev        BIGINT NOT NULL DEFAULT 0,
    task_id    UUID,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_config_changes_sn_time ON device_config_changes(device_sn, changed_at DESC);

-- ============================================================
-- 10. device_config_schema 42 键（参数序号 0x0000-0x0029，group_code 对齐 V1 界面四分组；
--     visibility：battery_type 驱动铅酸/锂电参数显示，set_master_slave 需 modal 二次确认）
-- ============================================================
INSERT INTO device_config_schema(param_key, group_code, sub_group, control_type, scale, unit, min, max, enum_map, step, confirmation_mode, display_name_key, sort_order, visibility, validation) VALUES
('set_output_priority','general',NULL,'enum',1,'',0,2,'{"0":"solar_first","1":"utility_first","2":"solar_utility"}'::jsonb,1,NULL,'config.set_output_priority',0,NULL,NULL),
('set_max_charge_current','hybrid','charge','number',0.1,'A',0,60,NULL,0.1,NULL,'config.set_max_charge_current',1,NULL,NULL),
('set_ac_volt_range','application',NULL,'enum',1,'',0,2,'{"0":"appliance","1":"ups"}'::jsonb,1,NULL,'config.set_ac_volt_range',2,NULL,NULL),
('set_battery_capacity','general',NULL,'number',1,'Ah',0,2000,NULL,1,NULL,'config.set_battery_capacity',3,NULL,NULL),
('set_battery_type','general',NULL,'enum',1,'',0,2,'{"0":"LiFePO4","1":"NCM","2":"LeadAcid"}'::jsonb,1,NULL,'config.set_battery_type',4,NULL,NULL),
('set_overload_restart','general',NULL,'boolean',1,'',0,1,NULL,NULL,NULL,'config.set_overload_restart',5,NULL,NULL),
('set_high_temp_restart','general',NULL,'boolean',1,'',0,1,NULL,NULL,NULL,'config.set_high_temp_restart',6,NULL,NULL),
('set_output_voltage','application',NULL,'number',0.1,'V',200,250,NULL,0.1,NULL,'config.set_output_voltage',7,NULL,NULL),
('set_output_frequency','application',NULL,'number',0.01,'Hz',45,55,NULL,0.01,NULL,'config.set_output_frequency',8,NULL,NULL),
('set_master_slave','parallel',NULL,'enum',1,'',0,1,'{"0":"slave","1":"master"}'::jsonb,1,'modal','config.set_master_slave',9,NULL,NULL),
('set_ac_charge_current','hybrid','charge','number',0.1,'A',0,150,NULL,0.1,NULL,'config.set_ac_charge_current',10,NULL,NULL),
('set_low_volt_return_utl','application',NULL,'number',0.1,'V',40,60,NULL,0.1,NULL,'config.set_low_volt_return_utl',11,NULL,'{"lte":"set_high_volt_return_bat"}'),
('set_high_volt_return_bat','application',NULL,'number',0.1,'V',40,60,NULL,0.1,NULL,'config.set_high_volt_return_bat',12,NULL,'{"gte":"set_low_volt_return_utl"}'),
('set_charge_priority','hybrid','charge','enum',1,'',0,2,'{"0":"solar_first","1":"utility_first","2":"solar_utility"}'::jsonb,1,NULL,'config.set_charge_priority',13,NULL,NULL),
('set_alarm_control','general',NULL,'number',1,'',0,255,NULL,1,NULL,'config.set_alarm_control',14,NULL,NULL),
('set_backlight_ctrl','general',NULL,'enum',1,'',0,3,'{"0":"off","1":"on","2":"auto","3":"dim"}'::jsonb,1,NULL,'config.set_backlight_ctrl',15,NULL,NULL),
('set_power_shutdown_alarm','general',NULL,'boolean',1,'',0,1,NULL,NULL,NULL,'config.set_power_shutdown_alarm',16,NULL,NULL),
('set_overload_use_city_power','application',NULL,'boolean',1,'',0,1,NULL,NULL,NULL,'config.set_overload_use_city_power',17,NULL,NULL),
('set_max_discharge_current','hybrid','discharge','number',0.1,'A',0,150,NULL,0.1,NULL,'config.set_max_discharge_current',18,NULL,NULL),
('set_max_chg_curr','hybrid','charge','number',0.1,'A',0,150,NULL,0.1,NULL,'config.set_max_chg_curr',19,NULL,NULL),
('set_recover_threshold_volt','application',NULL,'number',0.1,'V',40,60,NULL,0.1,NULL,'config.set_recover_threshold_volt',20,NULL,NULL),
('set_solar_power_balance','hybrid',NULL,'boolean',1,'',0,1,NULL,NULL,NULL,'config.set_solar_power_balance',21,NULL,NULL),
('set_ac_output_mode','application',NULL,'enum',1,'',0,2,'{"0":"battery_first","1":"utility_first","2":"hybrid"}'::jsonb,1,NULL,'config.set_ac_output_mode',22,NULL,NULL),
('set_li_bat_material','general',NULL,'enum',1,'',0,1,'{"0":"LiFePO4","1":"NCM"}'::jsonb,1,NULL,'config.set_li_bat_material',23,'{"param":"set_battery_type","ne":2}',NULL),
('set_cell_serial_lifepo4','general',NULL,'number',1,'节',4,32,NULL,1,NULL,'config.set_cell_serial_lifepo4',24,'{"param":"set_battery_type","eq":0}',NULL),
('set_cell_serial_li_nmc','general',NULL,'number',1,'节',4,32,NULL,1,NULL,'config.set_cell_serial_li_nmc',25,'{"param":"set_battery_type","eq":1}',NULL),
('set_equalize_enable','hybrid','equalize','boolean',1,'',0,1,NULL,NULL,NULL,'config.set_equalize_enable',26,'{"param":"set_battery_type","eq":2}',NULL),
('set_equalize_voltage','hybrid','equalize','number',0.1,'V',40,65,NULL,0.1,NULL,'config.set_equalize_voltage',27,'{"param":"set_battery_type","eq":2}',NULL),
('set_equalize_time','hybrid','equalize','number',1,'min',0,720,NULL,1,NULL,'config.set_equalize_time',28,'{"param":"set_battery_type","eq":2}',NULL),
('set_equalize_timeout','hybrid','equalize','number',1,'min',0,1440,NULL,1,NULL,'config.set_equalize_timeout',29,'{"param":"set_battery_type","eq":2}',NULL),
('set_equalize_interval','hybrid','equalize','number',1,'day',0,90,NULL,1,NULL,'config.set_equalize_interval',30,'{"param":"set_battery_type","eq":2}',NULL),
('set_equalize_activate','hybrid','equalize','boolean',1,'',0,1,NULL,NULL,NULL,'config.set_equalize_activate',31,'{"param":"set_battery_type","eq":2}',NULL),
('set_charge_time','hybrid','charge','number',1,'min',0,1440,NULL,1,NULL,'config.set_charge_time',32,NULL,NULL),
('set_close_charge_time','hybrid','charge','number',1,'min',0,1440,NULL,1,NULL,'config.set_close_charge_time',33,NULL,NULL),
('set_gen_start_voltage','hybrid','gen','number',0.1,'V',40,60,NULL,0.1,NULL,'config.set_gen_start_voltage',34,NULL,'{"gte":"set_gen_stop_voltage"}'),
('set_gen_stop_voltage','hybrid','gen','number',0.1,'V',40,60,NULL,0.1,NULL,'config.set_gen_stop_voltage',35,NULL,'{"lte":"set_gen_start_voltage"}'),
('set_soc_back_utl','hybrid','soc','number',1,'%',0,100,NULL,1,NULL,'config.set_soc_back_utl',36,NULL,'{"lte":"set_soc_back_gen"}'),
('set_soc_back_bat','hybrid','soc','number',1,'%',0,100,NULL,1,NULL,'config.set_soc_back_bat',37,NULL,NULL),
('set_soc_back_gen','hybrid','soc','number',1,'%',0,100,NULL,1,NULL,'config.set_soc_back_gen',38,NULL,'{"gte":"set_soc_back_utl"}'),
('set_soc_close_gen','hybrid','soc','number',1,'%',0,100,NULL,1,NULL,'config.set_soc_close_gen',39,NULL,NULL),
('set_soc_cutoff','hybrid','soc','number',1,'%',0,100,NULL,1,NULL,'config.set_soc_cutoff',40,NULL,'{"lte":"set_soc_back_utl"}'),
('set_buzzer','general',NULL,'boolean',1,'',0,1,NULL,NULL,NULL,'config.set_buzzer',41,NULL,NULL)
ON CONFLICT (param_key) DO NOTHING;
