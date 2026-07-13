-- 004: 为 device_day_data 表新增充电/放电/用电量字段
-- 这些字段由设备通过 data/energy 主题上报，之前只存储了 energy_produce (daily_pv)

DO $$
BEGIN
    IF to_regclass('public.device_day_data') IS NOT NULL THEN
        ALTER TABLE device_day_data
            ADD COLUMN IF NOT EXISTS daily_charge DECIMAL(12,4) DEFAULT 0,
            ADD COLUMN IF NOT EXISTS daily_discharge DECIMAL(12,4) DEFAULT 0,
            ADD COLUMN IF NOT EXISTS daily_load DECIMAL(12,4) DEFAULT 0;
    END IF;
END $$;
