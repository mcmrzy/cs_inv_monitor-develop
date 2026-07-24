-- devices 表增加 DSP 和 BMS 固件版本字段
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_dsp VARCHAR(50) DEFAULT '';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware_bms VARCHAR(50) DEFAULT '';
