-- 005: 将 device_day_data 改为 JSONB 存储，实现日聚合数据的完全模块化
-- 从此增删字段只需在 device_model_field 表配置，零代码改动

-- 1. 添加 JSONB data 列
DO $$
BEGIN
    IF to_regclass('public.device_day_data') IS NOT NULL THEN
        ALTER TABLE device_day_data ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}';
    END IF;
END $$;

-- 2. 将旧结构化列数据迁移到 JSONB。新 schema 已直接使用 JSONB，需跳过此步骤。
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'device_day_data' AND column_name = 'energy_produce'
    ) THEN
        EXECUTE $sql$
            UPDATE device_day_data SET data = jsonb_build_object(
                'energy_produce', COALESCE(energy_produce, 0),
                'daily_charge', COALESCE(daily_charge, 0),
                'daily_discharge', COALESCE(daily_discharge, 0),
                'daily_load', COALESCE(daily_load, 0),
                'run_minutes', COALESCE(run_minutes, 0)
            ) WHERE data = '{}'::jsonb
        $sql$;
    END IF;
END $$;

-- 3. 删除旧的结构化列
DO $$
BEGIN
    IF to_regclass('public.device_day_data') IS NOT NULL THEN
        ALTER TABLE device_day_data
            DROP COLUMN IF EXISTS energy_produce,
            DROP COLUMN IF EXISTS daily_charge,
            DROP COLUMN IF EXISTS daily_discharge,
            DROP COLUMN IF EXISTS daily_load,
            DROP COLUMN IF EXISTS run_minutes;
    END IF;
END $$;
