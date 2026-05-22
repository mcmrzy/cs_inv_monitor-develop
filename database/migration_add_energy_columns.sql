-- 为 device_realtime_data 添加能量统计字段
ALTER TABLE device_realtime_data 
ADD COLUMN IF NOT EXISTS daily_power_yields DECIMAL(14,4) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_power_yields DECIMAL(14,4) DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_active_power DECIMAL(12,2) DEFAULT 0;
