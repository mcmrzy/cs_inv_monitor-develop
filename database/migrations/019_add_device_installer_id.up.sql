-- 设备表添加安装商ID字段
-- installer_id 表示负责该设备的安装商ID

ALTER TABLE devices ADD COLUMN IF NOT EXISTS installer_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_devices_installer ON devices(installer_id);

COMMENT ON COLUMN devices.installer_id IS '安装商ID，用于设备分配';
