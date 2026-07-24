-- 026: align Heartbeat V1 and storage with the HTML final specification.
-- Sampling is every three minutes. Cell voltages and temperature points stay
-- as arrays in one row per device/sample; no one-minute aggregate is created.

ALTER TABLE devices ADD COLUMN IF NOT EXISTS temp_sensor_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE device_models ADD COLUMN IF NOT EXISTS temp_sensor_count SMALLINT;

ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS topic VARCHAR(64) NOT NULL DEFAULT 'heartbeat';
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS data_hash VARCHAR(64);
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS raw_envelope JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS charge_request_current_x10 BIGINT;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS charge_request_voltage_x10 BIGINT;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS system_mode BIGINT;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS total_charge_capacity DOUBLE PRECISION;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS total_discharge_capacity DOUBLE PRECISION;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS total_charge_time BIGINT;
ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS total_discharge_time BIGINT;

UPDATE device_telemetry_3min
SET data_hash = encode(sha256(convert_to(device_sn || '|' || event_time::text || '|' || sequence_no::text, 'UTF8')), 'hex')
WHERE data_hash IS NULL;
ALTER TABLE device_telemetry_3min ALTER COLUMN data_hash SET NOT NULL;
ALTER TABLE device_telemetry_3min DROP CONSTRAINT IF EXISTS device_telemetry_3min_pkey;
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_telemetry_3min_message
    ON device_telemetry_3min(device_sn, event_time, data_hash);

ALTER TABLE device_cell_samples ADD COLUMN IF NOT EXISTS data_hash VARCHAR(64);
UPDATE device_cell_samples
SET data_hash = encode(sha256(convert_to(device_sn || '|' || event_time::text || '|' || sequence_no::text, 'UTF8')), 'hex')
WHERE data_hash IS NULL;
ALTER TABLE device_cell_samples ALTER COLUMN data_hash SET NOT NULL;
ALTER TABLE device_cell_samples DROP CONSTRAINT IF EXISTS device_cell_samples_pkey;
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_cell_samples_message
    ON device_cell_samples(device_sn, event_time, data_hash);

ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS topic VARCHAR(64) NOT NULL DEFAULT 'heartbeat';
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS data_hash VARCHAR(64) NOT NULL DEFAULT '';
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS raw_envelope JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS charge_request_current_x10 BIGINT;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS charge_request_voltage_x10 BIGINT;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS system_mode BIGINT;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS total_charge_capacity DOUBLE PRECISION;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS total_discharge_capacity DOUBLE PRECISION;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS total_charge_time BIGINT;
ALTER TABLE device_latest_state ADD COLUMN IF NOT EXISTS total_discharge_time BIGINT;

CREATE TABLE IF NOT EXISTS device_ingest_errors (
    id           BIGSERIAL PRIMARY KEY,
    device_sn    VARCHAR(50),
    topic        VARCHAR(128) NOT NULL,
    raw_payload  BYTEA NOT NULL,
    error_code   VARCHAR(64) NOT NULL,
    error_detail TEXT,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_ingest_errors_sn_received
    ON device_ingest_errors(device_sn, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_device_ingest_errors_received
    ON device_ingest_errors(received_at DESC);

INSERT INTO telemetry_field_catalog(field_key,field_type,base_unit,category,allowed_aggregates) VALUES
('charge_request_current_x10','integer','0.1A','battery','["last"]'),
('charge_request_voltage_x10','integer','0.1V','battery','["last"]'),
('system_mode','integer',NULL,'system','["last"]'),
('total_charge_capacity','float','Ah','energy','["last","max"]'),
('total_discharge_capacity','float','Ah','energy','["last","max"]'),
('total_charge_time','integer','s','energy','["last","max"]'),
('total_discharge_time','integer','s','energy','["last","max"]')
ON CONFLICT(field_key) DO UPDATE SET
    field_type=EXCLUDED.field_type,base_unit=EXCLUDED.base_unit,category=EXCLUDED.category,
    allowed_aggregates=EXCLUDED.allowed_aggregates,updated_at=NOW();

DELETE FROM device_protocol_fields
WHERE protocol_version_id=(SELECT id FROM device_protocol_versions WHERE protocol_code='heartbeat' AND version=1);

WITH protocol AS (
    SELECT id FROM device_protocol_versions WHERE protocol_code='heartbeat' AND version=1
), mapping(group_code,field_index,field_key,wire_type,minimum,maximum) AS (VALUES
('ac',0,'ac_voltage','float32',0,250),('ac',1,'ac_current','float32',0,28.2),
('ac',2,'ac_active_power','float32',0,6200),('ac',3,'ac_apparent_power','float32',0,6200),
('ac',4,'ac_frequency','float32',0,50.5),('ac',5,'ac_power_factor','float32',0,1),
('ac',6,'load_percent','float32',0,100),('ac',7,'ac_voltage_thd','float32',0,5),
('bat',0,'battery_soc','float32',0,100),('bat',1,'battery_soh','float32',0,100),
('bat',2,'battery_voltage','float32',40,60),('bat',3,'battery_current','float32',-150,150),
('bat',4,'battery_power','float32',-7500,7500),('bat',5,'battery_capacity_remain','float32',0,1000),
('bat',6,'battery_capacity_total','float32',0,1000),('bat',7,'battery_cycle_count','uint32',0,4294967295),
('bat',8,'battery_temp_max','float32',-20,85),('bat',9,'battery_temp_min','float32',-20,85),
('bat',10,'cell_voltage_max','float32',0,5),('bat',11,'cell_voltage_min','float32',0,5),
('bat',12,'cell_voltage_diff','float32',0,2),('bat',13,'battery_state','uint8',0,3),
('bat',14,'battery_protect_status','uint32',0,4294967295),('bat',15,'bms_fault_code','uint32',0,4294967295),
('bat',16,'max_charge_current','float32',0,150),('bat',17,'max_discharge_current','float32',0,150),
('bat',18,'charge_voltage_ref','float32',40,60),('bat',19,'discharge_cutoff_voltage','float32',40,60),
('bat',20,'battery_temperature','float32',-20,85),('bat',21,'charge_request_current_x10','uint32',0,1500),
('bat',22,'charge_request_voltage_x10','uint32',0,600),
('pv',0,'pv1_voltage','float32',0,150),('pv',1,'pv1_current','float32',0,30),
('pv',2,'pv1_power','float32',0,6200),('pv',3,'pv2_voltage','float32',0,150),
('pv',4,'pv2_current','float32',0,30),('pv',5,'pv2_power','float32',0,6200),
('pv',6,'mppt_state','uint8',0,2),
('sys',0,'work_state','uint8',0,4),('sys',1,'fault_code','uint32',0,4294967295),
('sys',2,'alarm_code','uint32',0,4294967295),('sys',3,'inverter_temperature','float32',-20,85),
('sys',4,'mos_temperature','float32',-20,85),('sys',5,'ambient_temperature','float32',-20,85),
('sys',6,'dc_bus_voltage','float32',0,450),('sys',7,'runtime_hours','uint32',0,4294967295),
('sys',8,'fan_speed_percent','uint8',0,100),('sys',9,'efficiency','float32',0,100),
('sys',10,'system_mode','uint16',0,65535),
('eng',0,'daily_pv_energy','float64',0,1000000),('eng',1,'total_pv_energy','float64',0,1000000000000),
('eng',2,'daily_charge_energy','float64',0,1000000),('eng',3,'total_charge_energy','float64',0,1000000000000),
('eng',4,'daily_discharge_energy','float64',0,1000000),('eng',5,'total_discharge_energy','float64',0,1000000000000),
('eng',6,'daily_load_energy','float64',0,1000000),('eng',7,'total_load_energy','float64',0,1000000000000),
('eng',8,'total_charge_capacity','float64',0,1000000000000),('eng',9,'total_discharge_capacity','float64',0,1000000000000),
('eng',10,'total_charge_time','uint32',0,4294967295),('eng',11,'total_discharge_time','uint32',0,4294967295)
)
INSERT INTO device_protocol_fields(protocol_version_id,group_code,field_index,field_key,wire_type,minimum,maximum)
SELECT protocol.id,m.group_code,m.field_index,m.field_key,m.wire_type,m.minimum,m.maximum
FROM protocol CROSS JOIN mapping m;

UPDATE device_protocol_versions p
SET schema_hash=(
    SELECT encode(sha256(convert_to(string_agg(
        f.group_code||':'||f.field_index||':'||f.field_key||':'||f.wire_type||':'||
        COALESCE(f.minimum::text,'')||':'||COALESCE(f.maximum::text,''),',' ORDER BY f.group_code,f.field_index
    ),'UTF8')),'hex')
    FROM device_protocol_fields f WHERE f.protocol_version_id=p.id
), status='released', released_at=COALESCE(released_at,NOW())
WHERE p.protocol_code='heartbeat' AND p.version=1;

UPDATE device_models dm SET temp_sensor_count=4,lock_version=lock_version+1,updated_at=NOW()
WHERE dm.model_code='CS-I10-6k2';

INSERT INTO device_model_fields(model_id,field_key,display_name_key,group_code,display_unit,decimal_places,sort_order)
SELECT dm.id,c.field_key,'fields.'||c.field_key,c.category,c.base_unit,
       CASE WHEN c.field_type='integer' THEN 0 ELSE 2 END,1000+ROW_NUMBER() OVER(ORDER BY c.field_key)
FROM device_models dm CROSS JOIN telemetry_field_catalog c
WHERE dm.model_code='CS-I10-6k2' AND c.field_key IN (
    'charge_request_current_x10','charge_request_voltage_x10','system_mode',
    'total_charge_capacity','total_discharge_capacity','total_charge_time','total_discharge_time')
ON CONFLICT(model_id,field_key) DO UPDATE SET is_supported=TRUE,updated_at=NOW();

-- Migration 025 used the former OUT_OF_ORDER/BACKFILL bit. V1 defines it as 0x0008.
DO $$
DECLARE definition TEXT;
BEGIN
    SELECT pg_get_functiondef('maintain_telemetry_v2_derived()'::regprocedure) INTO definition;
    EXECUTE replace(definition,'(NEW.quality_flags & 64)','(NEW.quality_flags & 8)');
    SELECT pg_get_functiondef('maintain_latest_cells()'::regprocedure) INTO definition;
    EXECUTE replace(definition,'(NEW.quality_flags & 64)','(NEW.quality_flags & 8)');
END $$;

COMMENT ON TABLE device_telemetry_3min IS 'HTML V1 Heartbeat: one typed row per 3-minute sample with the complete raw envelope';
COMMENT ON TABLE device_cell_samples IS 'One row per device/3-minute sample; voltages and temperature points are stored as separate JSON arrays';
COMMENT ON TABLE device_ingest_errors IS 'Structurally invalid MQTT payloads excluded from normal telemetry';

