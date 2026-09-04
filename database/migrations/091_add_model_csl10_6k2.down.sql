--
-- 回滚迁移 091：移除 CS-L10-6K2 型号配置与 V2 协议（逆序）。
-- 幂等可重放：DELETE 无匹配行不报错；DROP COLUMN 使用 IF EXISTS。

-- 1. 移除遥测新列（先 device_latest_state，再 device_telemetry_3min）
ALTER TABLE device_latest_state
    DROP COLUMN IF EXISTS sys_status,
    DROP COLUMN IF EXISTS warning,
    DROP COLUMN IF EXISTS bms_warning,
    DROP COLUMN IF EXISTS battery_overcharge,
    DROP COLUMN IF EXISTS boost_temperature,
    DROP COLUMN IF EXISTS transformer_temperature,
    DROP COLUMN IF EXISTS pv_temperature,
    DROP COLUMN IF EXISTS buck1_current,
    DROP COLUMN IF EXISTS buck2_current,
    DROP COLUMN IF EXISTS grid_voltage,
    DROP COLUMN IF EXISTS grid_frequency,
    DROP COLUMN IF EXISTS ac_input_power,
    DROP COLUMN IF EXISTS ac_input_apparent_power,
    DROP COLUMN IF EXISTS ac_charge_power,
    DROP COLUMN IF EXISTS ac_charge_apparent_power,
    DROP COLUMN IF EXISTS ac_charge_current,
    DROP COLUMN IF EXISTS ac_bypass_power,
    DROP COLUMN IF EXISTS ac_bypass_apparent_power,
    DROP COLUMN IF EXISTS battery_charge_power,
    DROP COLUMN IF EXISTS battery_discharge_power,
    DROP COLUMN IF EXISTS gen_energy_daily,
    DROP COLUMN IF EXISTS gen_energy_total,
    DROP COLUMN IF EXISTS ac_charge_energy_daily,
    DROP COLUMN IF EXISTS ac_charge_energy_total,
    DROP COLUMN IF EXISTS ac_bypass_energy_daily,
    DROP COLUMN IF EXISTS ac_bypass_energy_total,
    DROP COLUMN IF EXISTS output_energy_daily,
    DROP COLUMN IF EXISTS output_energy_total;

ALTER TABLE device_telemetry_3min
    DROP COLUMN IF EXISTS sys_status,
    DROP COLUMN IF EXISTS warning,
    DROP COLUMN IF EXISTS bms_warning,
    DROP COLUMN IF EXISTS battery_overcharge,
    DROP COLUMN IF EXISTS boost_temperature,
    DROP COLUMN IF EXISTS transformer_temperature,
    DROP COLUMN IF EXISTS pv_temperature,
    DROP COLUMN IF EXISTS buck1_current,
    DROP COLUMN IF EXISTS buck2_current,
    DROP COLUMN IF EXISTS grid_voltage,
    DROP COLUMN IF EXISTS grid_frequency,
    DROP COLUMN IF EXISTS ac_input_power,
    DROP COLUMN IF EXISTS ac_input_apparent_power,
    DROP COLUMN IF EXISTS ac_charge_power,
    DROP COLUMN IF EXISTS ac_charge_apparent_power,
    DROP COLUMN IF EXISTS ac_charge_current,
    DROP COLUMN IF EXISTS ac_bypass_power,
    DROP COLUMN IF EXISTS ac_bypass_apparent_power,
    DROP COLUMN IF EXISTS battery_charge_power,
    DROP COLUMN IF EXISTS battery_discharge_power,
    DROP COLUMN IF EXISTS gen_energy_daily,
    DROP COLUMN IF EXISTS gen_energy_total,
    DROP COLUMN IF EXISTS ac_charge_energy_daily,
    DROP COLUMN IF EXISTS ac_charge_energy_total,
    DROP COLUMN IF EXISTS ac_bypass_energy_daily,
    DROP COLUMN IF EXISTS ac_bypass_energy_total,
    DROP COLUMN IF EXISTS output_energy_daily,
    DROP COLUMN IF EXISTS output_energy_total;

-- 2. 删除控制命令与显示配置
DELETE FROM device_model_commands
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2');

DELETE FROM device_model_fields
WHERE model_id = (SELECT id FROM device_models WHERE model_code = 'CS-L10-6K2');

-- 3. 删除型号（先解除协议引用）
UPDATE device_models SET heartbeat_protocol_id = NULL WHERE model_code = 'CS-L10-6K2';
DELETE FROM device_models WHERE model_code = 'CS-L10-6K2';

-- 4. 删除 V2 协议版本与字段定义
DELETE FROM device_protocol_fields
WHERE protocol_version_id = (SELECT id FROM device_protocol_versions WHERE protocol_code = 'heartbeat' AND version = 2);
DELETE FROM device_protocol_versions WHERE protocol_code = 'heartbeat' AND version = 2;

-- 5. 删除新增字段目录（仅删除本次迁移实际新增且无其他型号引用的字段；
--    091 之前已存在的 catalog 字段如 grid_frequency 被 INV-5000-TL 引用，保留）
DELETE FROM telemetry_field_catalog c WHERE c.field_key IN (
    'sys_status','warning','bms_warning','boost_temperature','transformer_temperature',
    'pv_temperature','battery_overcharge','buck1_current','buck2_current',
    'grid_voltage','grid_frequency','ac_input_power','ac_input_apparent_power',
    'ac_charge_power','ac_charge_apparent_power','ac_charge_current',
    'ac_bypass_power','ac_bypass_apparent_power',
    'battery_charge_power','battery_discharge_power',
    'gen_energy_daily','gen_energy_total',
    'ac_charge_energy_daily','ac_charge_energy_total',
    'ac_bypass_energy_daily','ac_bypass_energy_total',
    'output_energy_daily','output_energy_total'
) AND NOT EXISTS (
    SELECT 1 FROM device_model_fields dmf WHERE dmf.field_key = c.field_key
);
