-- 遥测表增加常用索引列，避免连续聚合视图因 JSONB 抽取产生 NULL/0。
-- 新基线已经移除了 legacy device_telemetry；重放旧迁移时必须安全跳过。
DO $$
BEGIN
    IF to_regclass('public.device_telemetry') IS NOT NULL THEN
        ALTER TABLE public.device_telemetry ADD COLUMN IF NOT EXISTS grid_frequency NUMERIC(6,2);
        ALTER TABLE public.device_telemetry ADD COLUMN IF NOT EXISTS battery_soc NUMERIC(4,1);
        ALTER TABLE public.device_telemetry ADD COLUMN IF NOT EXISTS battery_power NUMERIC(10,2);
        ALTER TABLE public.device_telemetry ADD COLUMN IF NOT EXISTS pv_power NUMERIC(10,2);
    END IF;
END
$$;
