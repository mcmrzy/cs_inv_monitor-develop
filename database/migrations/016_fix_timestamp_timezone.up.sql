-- 修复时间字段类型：TIMESTAMP -> TIMESTAMPTZ
-- 确保所有时间字段存储带时区的时间，统一使用UTC

-- 1. users 表
ALTER TABLE users 
  ALTER COLUMN last_login_at TYPE TIMESTAMPTZ USING last_login_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN deleted_at TYPE TIMESTAMPTZ USING deleted_at AT TIME ZONE 'UTC';

-- 2. verification_codes 表
ALTER TABLE verification_codes
  ALTER COLUMN expires_at TYPE TIMESTAMPTZ USING expires_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 3. stations 表
ALTER TABLE stations
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN deleted_at TYPE TIMESTAMPTZ USING deleted_at AT TIME ZONE 'UTC';

-- 4. devices 表
ALTER TABLE devices
  ALTER COLUMN last_online_at TYPE TIMESTAMPTZ USING last_online_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN deleted_at TYPE TIMESTAMPTZ USING deleted_at AT TIME ZONE 'UTC';

-- 5. alarms 表
ALTER TABLE alarms
  ALTER COLUMN occurred_at TYPE TIMESTAMPTZ USING occurred_at AT TIME ZONE 'UTC',
  ALTER COLUMN recovered_at TYPE TIMESTAMPTZ USING recovered_at AT TIME ZONE 'UTC',
  ALTER COLUMN handled_at TYPE TIMESTAMPTZ USING handled_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 6. notifications 表
ALTER TABLE notifications
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 7. firmware_versions 表
ALTER TABLE firmware_versions
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 8. system_configs 表
ALTER TABLE system_configs
  ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';

-- 9. device_telemetry 表 (TimescaleDB超表)
-- 先删除依赖视图
DROP VIEW IF EXISTS v_device_latest;

-- 修改字段类型
ALTER TABLE device_telemetry
  ALTER COLUMN time TYPE TIMESTAMPTZ USING time AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 重建视图
CREATE OR REPLACE VIEW v_device_latest AS
SELECT DISTINCT ON (dt.device_sn)
    dt.device_sn,
    dt.model_code,
    dt.topic,
    dt.data,
    dt.total_active_power,
    dt.daily_energy,
    dt.work_state,
    dt.fault_code,
    dt.internal_temperature,
    dt.time as data_time,
    dt.created_at as updated_at
FROM device_telemetry dt
ORDER BY dt.device_sn, dt.time DESC;

-- 10. device_models 表
ALTER TABLE device_models
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';

-- 11. device_alarms 表
ALTER TABLE device_alarms
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 12. device_cmd_logs 表
ALTER TABLE device_cmd_logs
  ALTER COLUMN sent_at TYPE TIMESTAMPTZ USING sent_at AT TIME ZONE 'UTC';

-- 13. device_day_data 表
ALTER TABLE device_day_data
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 14. station_day_data 表
ALTER TABLE station_day_data
  ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 更新update_updated_at_column函数，确保使用UTC时间
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ language 'plpgsql';

COMMENT ON TABLE device_telemetry IS '设备遥测数据表 - 时间字段已修复为TIMESTAMPTZ，统一存储UTC时间';
