-- 新增字段：支持子主题数据 (data/ac, data/dc, data/status, data/energy, data/grid)
ALTER TABLE device_realtime_data
    ADD COLUMN IF NOT EXISTS ac_reactive DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS ac_apparent DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS daily_energy DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS total_energy DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS run_hours INTEGER,
    ADD COLUMN IF NOT EXISTS efficiency DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS state_code SMALLINT,
    ADD COLUMN IF NOT EXISTS dc_injection DECIMAL(10,2),
    ADD COLUMN IF NOT EXISTS thd_voltage DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS thd_current DECIMAL(5,2);
