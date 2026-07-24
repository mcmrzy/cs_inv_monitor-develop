-- Telemetry V2: three-minute typed samples, model capability registry, and command lifecycle.
-- The legacy device_telemetry/model tables remain readable during cutover.

CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS telemetry_field_catalog (
    field_key          VARCHAR(64) PRIMARY KEY,
    field_type         VARCHAR(20) NOT NULL CHECK (field_type IN ('float', 'integer', 'boolean', 'string', 'bitmask')),
    base_unit          VARCHAR(20),
    category           VARCHAR(32) NOT NULL,
    description        TEXT,
    is_timeseries      BOOLEAN NOT NULL DEFAULT TRUE,
    is_aggregatable    BOOLEAN NOT NULL DEFAULT TRUE,
    allowed_aggregates JSONB NOT NULL DEFAULT '[]'::jsonb,
    status             VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deprecated')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_protocol_versions (
    id            BIGSERIAL PRIMARY KEY,
    protocol_code VARCHAR(64) NOT NULL,
    version       SMALLINT NOT NULL CHECK (version > 0),
    schema_hash   VARCHAR(64) NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'released', 'retired')),
    released_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (protocol_code, version)
);

CREATE TABLE IF NOT EXISTS device_protocol_fields (
    id                  BIGSERIAL PRIMARY KEY,
    protocol_version_id BIGINT NOT NULL REFERENCES device_protocol_versions(id) ON DELETE RESTRICT,
    group_code          VARCHAR(16) NOT NULL,
    field_index         SMALLINT NOT NULL CHECK (field_index >= 0),
    field_key           VARCHAR(64) NOT NULL REFERENCES telemetry_field_catalog(field_key) ON DELETE RESTRICT,
    wire_type           VARCHAR(20) NOT NULL,
    scale               NUMERIC NOT NULL DEFAULT 1,
    minimum             NUMERIC,
    maximum             NUMERIC,
    nullable            BOOLEAN NOT NULL DEFAULT TRUE,
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deprecated')),
    UNIQUE (protocol_version_id, group_code, field_index),
    UNIQUE (protocol_version_id, group_code, field_key)
);

ALTER TABLE device_models ADD COLUMN IF NOT EXISTS heartbeat_protocol_id BIGINT REFERENCES device_protocol_versions(id);
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS rated_power_w INTEGER;
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS rated_voltage_v NUMERIC(8,2);
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS rated_frequency_hz NUMERIC(6,2);
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS battery_voltage_v NUMERIC(8,2);
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS battery_type VARCHAR(32);
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS cell_count SMALLINT;
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS mppt_count SMALLINT;
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS supports_parallel BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS specifications JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS lifecycle_status VARCHAR(20) NOT NULL DEFAULT 'draft';
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS lock_version BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS device_model_fields (
    id               BIGSERIAL PRIMARY KEY,
    model_id         BIGINT NOT NULL REFERENCES device_models(id) ON DELETE RESTRICT,
    field_key        VARCHAR(64) NOT NULL REFERENCES telemetry_field_catalog(field_key) ON DELETE RESTRICT,
    display_name_key VARCHAR(128),
    group_code       VARCHAR(32) NOT NULL,
    display_unit     VARCHAR(20),
    decimal_places   SMALLINT NOT NULL DEFAULT 1 CHECK (decimal_places BETWEEN 0 AND 6),
    sort_order       INTEGER NOT NULL DEFAULT 0,
    is_supported     BOOLEAN NOT NULL DEFAULT TRUE,
    is_visible       BOOLEAN NOT NULL DEFAULT TRUE,
    show_realtime    BOOLEAN NOT NULL DEFAULT TRUE,
    show_history     BOOLEAN NOT NULL DEFAULT TRUE,
    allow_compare    BOOLEAN NOT NULL DEFAULT FALSE,
    allow_alarm_rule BOOLEAN NOT NULL DEFAULT FALSE,
    default_chart    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (model_id, field_key)
);
CREATE INDEX IF NOT EXISTS idx_device_model_fields_model_sort ON device_model_fields(model_id, group_code, sort_order);

CREATE TABLE IF NOT EXISTS device_model_commands (
    id               BIGSERIAL PRIMARY KEY,
    model_id         BIGINT NOT NULL REFERENCES device_models(id) ON DELETE RESTRICT,
    command_code     VARCHAR(64) NOT NULL,
    display_name_key VARCHAR(128) NOT NULL,
    parameter_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
    response_schema  JSONB NOT NULL DEFAULT '{}'::jsonb,
    timeout_seconds  INTEGER NOT NULL DEFAULT 30 CHECK (timeout_seconds BETWEEN 1 AND 3600),
    risk_level       SMALLINT NOT NULL DEFAULT 1 CHECK (risk_level BETWEEN 1 AND 3),
    requires_online  BOOLEAN NOT NULL DEFAULT TRUE,
    is_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (model_id, command_code)
);

CREATE TABLE IF NOT EXISTS device_commands (
    id              BIGSERIAL PRIMARY KEY,
    task_id         UUID NOT NULL UNIQUE,
    device_sn       VARCHAR(50) NOT NULL,
    command_code    VARCHAR(64) NOT NULL,
    requested_args  JSONB NOT NULL DEFAULT '[]'::jsonb,
    response_data   JSONB NOT NULL DEFAULT '[]'::jsonb,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    result_code     VARCHAR(64),
    result_message  TEXT,
    requested_by    BIGINT,
    source          VARCHAR(20) NOT NULL DEFAULT 'web',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    queued_at       TIMESTAMPTZ,
    sent_at         TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    timeout_at      TIMESTAMPTZ NOT NULL,
    retry_count     SMALLINT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_device_commands_sn_created ON device_commands(device_sn, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_commands_pending ON device_commands(status, timeout_at)
    WHERE status IN ('pending', 'queued', 'sent', 'acknowledged', 'executing');

CREATE TABLE IF NOT EXISTS device_control_state (
    device_sn         VARCHAR(50) PRIMARY KEY,
    protocol_version  SMALLINT NOT NULL DEFAULT 1,
    desired           JSONB NOT NULL DEFAULT '{}'::jsonb,
    reported          JSONB NOT NULL DEFAULT '{}'::jsonb,
    desired_version   BIGINT NOT NULL DEFAULT 0,
    reported_revision BIGINT NOT NULL DEFAULT 0,
    sync_status       VARCHAR(20) NOT NULL DEFAULT 'unknown',
    desired_at        TIMESTAMPTZ,
    reported_at       TIMESTAMPTZ,
    last_task_id      UUID,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_control_events (
    id          BIGSERIAL PRIMARY KEY,
    device_sn   VARCHAR(50) NOT NULL,
    task_id     UUID,
    event_type  VARCHAR(32) NOT NULL,
    old_value   JSONB NOT NULL DEFAULT '{}'::jsonb,
    new_value   JSONB NOT NULL DEFAULT '{}'::jsonb,
    operator_id BIGINT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_control_events_sn_created ON device_control_events(device_sn, created_at DESC);

CREATE TABLE IF NOT EXISTS device_latest_state (
    device_sn VARCHAR(50) PRIMARY KEY,
    protocol_version SMALLINT NOT NULL,
    sequence_no BIGINT NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    ac_voltage REAL, ac_current REAL, ac_active_power REAL, ac_apparent_power REAL,
    ac_frequency REAL, ac_power_factor REAL, load_percent REAL, ac_voltage_thd REAL,
    battery_soc REAL, battery_soh REAL, battery_voltage REAL, battery_current REAL, battery_power REAL,
    battery_capacity_remain REAL, battery_capacity_total REAL, battery_cycle_count INTEGER,
    battery_temp_max REAL, battery_temp_min REAL, cell_voltage_max REAL, cell_voltage_min REAL,
    cell_voltage_diff REAL, battery_state SMALLINT, battery_protect_status BIGINT, bms_fault_code BIGINT,
    max_charge_current REAL, max_discharge_current REAL, charge_voltage_ref REAL,
    discharge_cutoff_voltage REAL, battery_temperature REAL,
    pv1_voltage REAL, pv1_current REAL, pv1_power REAL, pv1_voltage_max REAL, pv1_power_max REAL,
    pv2_voltage REAL, pv2_current REAL, pv2_power REAL, pv2_voltage_max REAL, pv2_power_max REAL,
    pv_total_power REAL, mppt_state SMALLINT,
    work_state SMALLINT, fault_code BIGINT, alarm_code BIGINT, inverter_temperature REAL,
    mos_temperature REAL, ambient_temperature REAL, dc_bus_voltage REAL, runtime_hours BIGINT,
    fan_speed_percent SMALLINT, efficiency REAL,
    daily_pv_energy DOUBLE PRECISION, total_pv_energy DOUBLE PRECISION,
    daily_charge_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    daily_discharge_energy DOUBLE PRECISION, total_discharge_energy DOUBLE PRECISION,
    daily_load_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_latest_state_event_time ON device_latest_state(event_time DESC);

CREATE TABLE IF NOT EXISTS device_telemetry_3min (
    device_sn VARCHAR(50) NOT NULL,
    protocol_version SMALLINT NOT NULL,
    sequence_no BIGINT NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    quality_flags INTEGER NOT NULL DEFAULT 0,
    ac_voltage REAL, ac_current REAL, ac_active_power REAL, ac_apparent_power REAL,
    ac_frequency REAL, ac_power_factor REAL, load_percent REAL, ac_voltage_thd REAL,
    battery_soc REAL, battery_soh REAL, battery_voltage REAL, battery_current REAL, battery_power REAL,
    battery_capacity_remain REAL, battery_capacity_total REAL, battery_cycle_count INTEGER,
    battery_temp_max REAL, battery_temp_min REAL, cell_voltage_max REAL, cell_voltage_min REAL,
    cell_voltage_diff REAL, battery_state SMALLINT, battery_protect_status BIGINT, bms_fault_code BIGINT,
    max_charge_current REAL, max_discharge_current REAL, charge_voltage_ref REAL,
    discharge_cutoff_voltage REAL, battery_temperature REAL,
    pv1_voltage REAL, pv1_current REAL, pv1_power REAL, pv1_voltage_max REAL, pv1_power_max REAL,
    pv2_voltage REAL, pv2_current REAL, pv2_power REAL, pv2_voltage_max REAL, pv2_power_max REAL,
    pv_total_power REAL, mppt_state SMALLINT,
    work_state SMALLINT, fault_code BIGINT, alarm_code BIGINT, inverter_temperature REAL,
    mos_temperature REAL, ambient_temperature REAL, dc_bus_voltage REAL, runtime_hours BIGINT,
    fan_speed_percent SMALLINT, efficiency REAL,
    daily_pv_energy DOUBLE PRECISION, total_pv_energy DOUBLE PRECISION,
    daily_charge_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    daily_discharge_energy DOUBLE PRECISION, total_discharge_energy DOUBLE PRECISION,
    daily_load_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    PRIMARY KEY (device_sn, event_time)
);
CREATE INDEX IF NOT EXISTS idx_device_telemetry_3min_sn_time ON device_telemetry_3min(device_sn, event_time DESC);

CREATE TABLE IF NOT EXISTS device_cell_samples (
    device_sn VARCHAR(50) NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    sequence_no BIGINT NOT NULL,
    voltages JSONB NOT NULL,
    temperatures JSONB NOT NULL,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    is_abnormal BOOLEAN NOT NULL DEFAULT FALSE,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_sn, event_time)
);

CREATE TABLE IF NOT EXISTS device_latest_cells (
    device_sn VARCHAR(50) PRIMARY KEY,
    event_time TIMESTAMPTZ NOT NULL,
    sequence_no BIGINT NOT NULL,
    voltages JSONB NOT NULL,
    temperatures JSONB NOT NULL,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_energy_day (
    device_sn VARCHAR(50) NOT NULL,
    stat_date DATE NOT NULL,
    timezone VARCHAR(64) NOT NULL,
    pv_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    charge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    discharge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    load_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_pv_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    total_discharge_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    max_pv_power REAL, max_ac_power REAL, max_charge_power REAL, max_discharge_power REAL,
    avg_battery_soc REAL, min_battery_soc REAL, max_battery_soc REAL,
    max_inverter_temperature REAL, max_mos_temperature REAL, max_battery_temperature REAL,
    sample_count INTEGER NOT NULL DEFAULT 0,
    online_minutes SMALLINT NOT NULL DEFAULT 0, run_minutes SMALLINT NOT NULL DEFAULT 0,
    alarm_count INTEGER NOT NULL DEFAULT 0, fault_count INTEGER NOT NULL DEFAULT 0,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_sn, stat_date)
);

CREATE TABLE IF NOT EXISTS device_energy_month (
    device_sn VARCHAR(50) NOT NULL,
    stat_month DATE NOT NULL,
    timezone VARCHAR(64) NOT NULL,
    pv_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    charge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    discharge_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    load_energy DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_pv_energy DOUBLE PRECISION, total_charge_energy DOUBLE PRECISION,
    total_discharge_energy DOUBLE PRECISION, total_load_energy DOUBLE PRECISION,
    online_minutes INTEGER NOT NULL DEFAULT 0, run_minutes INTEGER NOT NULL DEFAULT 0,
    alarm_count INTEGER NOT NULL DEFAULT 0, fault_count INTEGER NOT NULL DEFAULT 0,
    quality_flags INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (device_sn, stat_month)
);

INSERT INTO telemetry_field_catalog(field_key, field_type, base_unit, category, allowed_aggregates) VALUES
('ac_voltage','float','V','ac','["avg","min","max","last"]'),
('ac_current','float','A','ac','["avg","min","max","last"]'),
('ac_active_power','float','W','ac','["avg","min","max","last"]'),
('ac_apparent_power','float','VA','ac','["avg","min","max","last"]'),
('ac_frequency','float','Hz','ac','["avg","min","max","last"]'),
('ac_power_factor','float',NULL,'ac','["avg","min","max","last"]'),
('load_percent','float','%','ac','["avg","min","max","last"]'),
('ac_voltage_thd','float','%','ac','["avg","min","max","last"]'),
('battery_soc','float','%','battery','["avg","min","max","last"]'),
('battery_soh','float','%','battery','["avg","min","max","last"]'),
('battery_voltage','float','V','battery','["avg","min","max","last"]'),
('battery_current','float','A','battery','["avg","min","max","last"]'),
('battery_power','float','W','battery','["avg","min","max","last"]'),
('pv1_voltage','float','V','pv','["avg","min","max","last"]'),
('pv1_current','float','A','pv','["avg","min","max","last"]'),
('pv1_power','float','W','pv','["avg","min","max","last"]'),
('pv2_voltage','float','V','pv','["avg","min","max","last"]'),
('pv2_current','float','A','pv','["avg","min","max","last"]'),
('pv2_power','float','W','pv','["avg","min","max","last"]'),
('pv_total_power','float','W','pv','["avg","min","max","last"]'),
('inverter_temperature','float','C','system','["avg","min","max","last"]'),
('mos_temperature','float','C','system','["avg","min","max","last"]'),
('ambient_temperature','float','C','system','["avg","min","max","last"]'),
('daily_pv_energy','float','kWh','energy','["last","max"]'),
('total_pv_energy','float','kWh','energy','["last","max"]'),
('battery_capacity_remain','float','Ah','battery','["last"]'),
('battery_capacity_total','float','Ah','battery','["last"]'),
('battery_cycle_count','integer',NULL,'battery','["last","max"]'),
('battery_temp_max','float','C','battery','["max","last"]'),
('battery_temp_min','float','C','battery','["min","last"]'),
('cell_voltage_max','float','V','battery','["max","last"]'),
('cell_voltage_min','float','V','battery','["min","last"]'),
('cell_voltage_diff','float','V','battery','["max","last"]'),
('battery_state','integer',NULL,'battery','["last"]'),
('battery_protect_status','bitmask',NULL,'battery','["last"]'),
('bms_fault_code','integer',NULL,'battery','["last"]'),
('max_charge_current','float','A','battery','["last"]'),
('max_discharge_current','float','A','battery','["last"]'),
('charge_voltage_ref','float','V','battery','["last"]'),
('discharge_cutoff_voltage','float','V','battery','["last"]'),
('battery_temperature','float','C','battery','["avg","min","max","last"]'),
('pv1_voltage_max','float','V','pv','["max","last"]'),
('pv1_power_max','float','W','pv','["max","last"]'),
('pv2_voltage_max','float','V','pv','["max","last"]'),
('pv2_power_max','float','W','pv','["max","last"]'),
('mppt_state','integer',NULL,'pv','["last"]'),
('work_state','integer',NULL,'system','["last"]'),
('fault_code','integer',NULL,'system','["last"]'),
('alarm_code','integer',NULL,'system','["last"]'),
('dc_bus_voltage','float','V','system','["avg","min","max","last"]'),
('runtime_hours','integer','h','system','["last","max"]'),
('fan_speed_percent','integer','%','system','["avg","max","last"]'),
('efficiency','float','%','system','["avg","min","max","last"]'),
('daily_charge_energy','float','kWh','energy','["last","max"]'),
('total_charge_energy','float','kWh','energy','["last","max"]'),
('daily_discharge_energy','float','kWh','energy','["last","max"]'),
('total_discharge_energy','float','kWh','energy','["last","max"]'),
('daily_load_energy','float','kWh','energy','["last","max"]'),
('total_load_energy','float','kWh','energy','["last","max"]')
ON CONFLICT (field_key) DO NOTHING;

INSERT INTO device_protocol_versions(protocol_code, version, schema_hash, status, released_at)
VALUES ('heartbeat', 1, 'heartbeat-v1-csi10-6k2-20260713', 'released', NOW())
ON CONFLICT (protocol_code, version) DO NOTHING;

WITH protocol AS (
    SELECT id FROM device_protocol_versions WHERE protocol_code='heartbeat' AND version=1
), mapping(group_code, field_index, field_key, wire_type, minimum, maximum) AS (VALUES
('ac',0,'ac_voltage','float32',0,300), ('ac',1,'ac_current','float32',0,40),
('ac',2,'ac_active_power','float32',0,7500), ('ac',3,'ac_apparent_power','float32',0,7500),
('ac',4,'ac_frequency','float32',45,55), ('ac',5,'ac_power_factor','float32',0,1),
('ac',6,'load_percent','float32',0,120), ('ac',7,'ac_voltage_thd','float32',0,100),
('bat',0,'battery_soc','float32',0,100), ('bat',1,'battery_soh','float32',0,100),
('bat',2,'battery_voltage','float32',0,70), ('bat',3,'battery_current','float32',-150,150),
('bat',4,'battery_power','float32',-7500,7500), ('bat',5,'battery_capacity_remain','float32',0,1000),
('bat',6,'battery_capacity_total','float32',0,1000), ('bat',7,'battery_cycle_count','uint32',0,4294967295),
('bat',8,'battery_temp_max','float32',-40,100), ('bat',9,'battery_temp_min','float32',-40,100),
('bat',10,'cell_voltage_max','float32',0,5), ('bat',11,'cell_voltage_min','float32',0,5),
('bat',12,'cell_voltage_diff','float32',0,2), ('bat',13,'battery_state','uint8',0,3),
('bat',14,'battery_protect_status','uint32',0,4294967295), ('bat',15,'bms_fault_code','uint32',0,4294967295),
('bat',16,'max_charge_current','float32',0,150), ('bat',17,'max_discharge_current','float32',0,150),
('bat',18,'charge_voltage_ref','float32',0,70), ('bat',19,'discharge_cutoff_voltage','float32',0,70),
('bat',20,'battery_temperature','float32',-40,100),
('pv',0,'pv1_voltage','float32',0,150), ('pv',1,'pv1_current','float32',0,30),
('pv',2,'pv1_power','float32',0,4000), ('pv',3,'pv1_voltage_max','float32',0,150),
('pv',4,'pv1_power_max','float32',0,4000), ('pv',5,'pv2_voltage','float32',0,150),
('pv',6,'pv2_current','float32',0,30), ('pv',7,'pv2_power','float32',0,4000),
('pv',8,'pv2_voltage_max','float32',0,150), ('pv',9,'pv2_power_max','float32',0,4000),
('pv',10,'pv_total_power','float32',0,7500), ('pv',11,'mppt_state','uint8',0,2),
('sys',0,'work_state','uint8',0,4), ('sys',1,'fault_code','uint32',0,4294967295),
('sys',2,'alarm_code','uint32',0,4294967295), ('sys',3,'inverter_temperature','float32',-40,100),
('sys',4,'mos_temperature','float32',-40,120), ('sys',5,'ambient_temperature','float32',-40,100),
('sys',6,'dc_bus_voltage','float32',0,500), ('sys',7,'runtime_hours','uint32',0,4294967295),
('sys',8,'fan_speed_percent','uint8',0,100), ('sys',9,'efficiency','float32',0,100),
('eng',0,'daily_pv_energy','float64',0,1000000), ('eng',1,'total_pv_energy','float64',0,1000000000000),
('eng',2,'daily_charge_energy','float64',0,1000000), ('eng',3,'total_charge_energy','float64',0,1000000000000),
('eng',4,'daily_discharge_energy','float64',0,1000000), ('eng',5,'total_discharge_energy','float64',0,1000000000000),
('eng',6,'daily_load_energy','float64',0,1000000), ('eng',7,'total_load_energy','float64',0,1000000000000)
)
INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,minimum,maximum)
SELECT protocol.id,m.group_code,m.field_index,m.field_key,m.wire_type,m.minimum,m.maximum FROM protocol CROSS JOIN mapping m
ON CONFLICT (protocol_version_id,group_code,field_index) DO NOTHING;

INSERT INTO device_models(model_code,model_name,manufacturer,category,rated_power_kw,is_active)
VALUES('CS-I10-6k2','CS-I10-6k2 48V 离网逆变器','辰烁科技','inverter',6.2,TRUE)
ON CONFLICT(model_code) DO NOTHING;

UPDATE device_models dm SET
    heartbeat_protocol_id=p.id, rated_power_w=6200, rated_voltage_v=220,
    rated_frequency_hz=50, battery_voltage_v=51.2, battery_type='LiFePO4',
    cell_count=16, mppt_count=2, supports_parallel=TRUE, lifecycle_status='active'
FROM device_protocol_versions p
WHERE dm.model_code='CS-I10-6k2' AND p.protocol_code='heartbeat' AND p.version=1;

INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,decimal_places,sort_order,allow_compare,allow_alarm_rule,default_chart)
SELECT dm.id,c.field_key,'fields.'||c.field_key,c.category,c.base_unit,
       CASE WHEN c.field_type='integer' THEN 0 ELSE 2 END,
       ROW_NUMBER() OVER (PARTITION BY c.category ORDER BY c.field_key),
       c.field_key IN ('ac_active_power','pv_total_power','battery_power','battery_soc'),
       c.field_key IN ('battery_soc','battery_temperature','inverter_temperature','fault_code'),
       c.field_key IN ('ac_active_power','pv_total_power','battery_soc')
FROM device_models dm CROSS JOIN telemetry_field_catalog c
WHERE dm.model_code='CS-I10-6k2'
ON CONFLICT(model_id,field_key) DO NOTHING;

WITH commands(command_code,display_name_key,parameter_schema,timeout_seconds,risk_level) AS (VALUES
('ac_on','commands.ac_on','{"args":[]}'::jsonb,30,2),
('ac_off','commands.ac_off','{"args":[]}'::jsonb,30,2),
('set_power_limit','commands.set_power_limit','{"args":[{"key":"watts","type":"integer","min":0,"max":6200,"unit":"W"}]}'::jsonb,30,1),
('set_charge_limit','commands.set_charge_limit','{"args":[{"key":"watts","type":"integer","min":0,"max":6200,"unit":"W"}]}'::jsonb,30,1),
('set_discharge_limit','commands.set_discharge_limit','{"args":[{"key":"watts","type":"integer","min":0,"max":6200,"unit":"W"}]}'::jsonb,30,1),
('set_soc_window','commands.set_soc_window','{"args":[{"key":"low_x10","type":"integer","min":100,"max":500},{"key":"high_x10","type":"integer","min":500,"max":1000}],"rules":["low_x10 < high_x10","high_x10-low_x10 >= 50"]}'::jsonb,30,1),
('force_charge','commands.force_charge','{"args":[{"key":"enabled","type":"boolean"}],"mutex":"force_discharge"}'::jsonb,30,2),
('force_discharge','commands.force_discharge','{"args":[{"key":"enabled","type":"boolean"}],"mutex":"force_charge"}'::jsonb,30,2),
('restart','commands.restart','{"args":[]}'::jsonb,60,3),
('query_config','commands.query_config','{"args":[]}'::jsonb,30,1),
('query_telemetry','commands.query_telemetry','{"args":[]}'::jsonb,30,1),
('bms_set_enable','commands.bms_set_enable','{"args":[{"key":"charge","type":"boolean"},{"key":"discharge","type":"boolean"}]}'::jsonb,30,2),
('bms_set_charge_current','commands.bms_set_charge_current','{"args":[{"key":"amp_x10","type":"integer","min":0,"max":600}]}'::jsonb,30,2),
('bms_set_discharge_current','commands.bms_set_discharge_current','{"args":[{"key":"amp_x10","type":"integer","min":0,"max":1200}]}'::jsonb,30,2),
('bms_set_charge_voltage','commands.bms_set_charge_voltage','{"args":[{"key":"volt_x10","type":"integer","min":440,"max":584}]}'::jsonb,30,2),
('bms_set_discharge_voltage','commands.bms_set_discharge_voltage','{"args":[{"key":"volt_x10","type":"integer","min":400,"max":500}]}'::jsonb,30,2),
('parallel_enable','commands.parallel_enable','{"args":[{"key":"mode","type":"integer","enum":[1,2]}]}'::jsonb,60,3),
('parallel_set_role','commands.parallel_set_role','{"args":[{"key":"role","type":"integer","enum":[1,2]},{"key":"machine_id","type":"integer","min":0,"max":7}]}'::jsonb,60,3),
('parallel_set_phase','commands.parallel_set_phase','{"args":[{"key":"phase","type":"integer","enum":[1,2,3]}]}'::jsonb,60,3),
('parallel_disable','commands.parallel_disable','{"args":[]}'::jsonb,60,3)
)
INSERT INTO device_model_commands(model_id,command_code,display_name_key,parameter_schema,timeout_seconds,risk_level)
SELECT dm.id,c.command_code,c.display_name_key,c.parameter_schema,c.timeout_seconds,c.risk_level
FROM device_models dm CROSS JOIN commands c WHERE dm.model_code='CS-I10-6k2'
ON CONFLICT(model_id,command_code) DO NOTHING;

-- TimescaleDB objects are guarded because extension policy support varies by version.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        PERFORM create_hypertable('device_telemetry_3min', 'event_time', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);
        PERFORM create_hypertable('device_cell_samples', 'event_time', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);

        ALTER TABLE device_telemetry_3min SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'event_time DESC'
        );
        ALTER TABLE device_cell_samples SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'device_sn',
            timescaledb.compress_orderby = 'event_time DESC'
        );

        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_compression' AND hypertable_name = 'device_telemetry_3min') THEN
            PERFORM add_compression_policy('device_telemetry_3min', INTERVAL '3 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' AND hypertable_name = 'device_telemetry_3min') THEN
            PERFORM add_retention_policy('device_telemetry_3min', INTERVAL '90 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_compression' AND hypertable_name = 'device_cell_samples') THEN
            PERFORM add_compression_policy('device_cell_samples', INTERVAL '7 days');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'policy_retention' AND hypertable_name = 'device_cell_samples') THEN
            PERFORM add_retention_policy('device_cell_samples', INTERVAL '90 days');
        END IF;
    END IF;
END $$;

CREATE MATERIALIZED VIEW IF NOT EXISTS device_telemetry_hour
WITH (timescaledb.continuous) AS
SELECT
    time_bucket(INTERVAL '1 hour', event_time) AS bucket,
    device_sn,
    AVG(ac_active_power) AS avg_ac_power,
    MAX(ac_active_power) AS max_ac_power,
    AVG(pv_total_power) AS avg_pv_power,
    MAX(pv_total_power) AS max_pv_power,
    AVG(battery_power) AS avg_battery_power,
    AVG(battery_soc) AS avg_battery_soc,
    MIN(battery_soc) AS min_battery_soc,
    MAX(battery_soc) AS max_battery_soc,
    AVG(inverter_temperature) AS avg_inverter_temperature,
    MAX(inverter_temperature) AS max_inverter_temperature,
    LAST(daily_pv_energy, event_time) AS daily_pv_energy,
    LAST(total_pv_energy, event_time) AS total_pv_energy,
    LAST(work_state, event_time) AS work_state,
    LAST(fault_code, event_time) AS fault_code,
    COUNT(*) AS sample_count,
    LEAST(60, COUNT(*) * 3)::SMALLINT AS online_minutes,
    LEAST(60, COUNT(*) FILTER (WHERE ac_active_power > 0) * 3)::SMALLINT AS run_minutes,
    bit_or(quality_flags) AS quality_flags
FROM device_telemetry_3min
GROUP BY bucket, device_sn
WITH NO DATA;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.jobs
        WHERE proc_name='policy_refresh_continuous_aggregate' AND hypertable_name='device_telemetry_hour'
    ) THEN
        PERFORM add_continuous_aggregate_policy('device_telemetry_hour',
            start_offset => INTERVAL '2 days', end_offset => INTERVAL '10 minutes',
            schedule_interval => INTERVAL '10 minutes');
    END IF;
END $$;
