-- =====================================================
-- Migration 015: 为 devices 表添加设备信息字段
-- 解决设备详情页设备信息显示为空的问题
-- 这些字段由设备通过 MQTT info 主题上报后写入
-- =====================================================

ALTER TABLE devices ADD COLUMN IF NOT EXISTS manufacturer VARCHAR(100) DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_arm VARCHAR(50) DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_esp VARCHAR(50) DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_type VARCHAR(50) DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_voltage DECIMAL(10,2) DEFAULT 0;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS rated_freq DECIMAL(5,2) DEFAULT 0;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_voltage DECIMAL(10,2) DEFAULT 0;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_type VARCHAR(50) DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS cell_count INTEGER DEFAULT 0;
