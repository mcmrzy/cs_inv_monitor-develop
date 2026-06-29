-- 005: 将 device_day_data 改为 JSONB 存储，实现日聚合数据的完全模块化
-- 从此增删字段只需在 device_model_field 表配置，零代码改动

-- 1. 添加 JSONB data 列
ALTER TABLE device_day_data ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}';

-- 2. 将现有结构化列数据迁移到 JSONB
UPDATE device_day_data SET data = jsonb_build_object(
    'energy_produce', COALESCE(energy_produce, 0),
    'daily_charge', COALESCE(daily_charge, 0),
    'daily_discharge', COALESCE(daily_discharge, 0),
    'daily_load', COALESCE(daily_load, 0),
    'run_minutes', COALESCE(run_minutes, 0)
) WHERE data = '{}'::jsonb;

-- 3. 删除旧的结构化列
ALTER TABLE device_day_data
    DROP COLUMN IF EXISTS energy_produce,
    DROP COLUMN IF EXISTS daily_charge,
    DROP COLUMN IF EXISTS daily_discharge,
    DROP COLUMN IF EXISTS daily_load,
    DROP COLUMN IF EXISTS run_minutes;
