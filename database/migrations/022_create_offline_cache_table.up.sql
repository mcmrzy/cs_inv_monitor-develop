-- 遥测表增加常用索引列，避免连续聚合视图因 JSONB 抽取产生 NULL/0
ALTER TABLE device_telemetry ADD COLUMN IF NOT EXISTS grid_frequency   NUMERIC(6,2);   -- 电网频率 Hz
ALTER TABLE device_telemetry ADD COLUMN IF NOT EXISTS battery_soc      NUMERIC(4,1);   -- 电池 SOC %
ALTER TABLE device_telemetry ADD COLUMN IF NOT EXISTS battery_power    NUMERIC(10,2);  -- 电池功率 W
ALTER TABLE device_telemetry ADD COLUMN IF NOT EXISTS pv_power         NUMERIC(10,2);  -- PV 功率 W
