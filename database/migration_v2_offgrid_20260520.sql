DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='devices' AND column_name='manufacturer') THEN
        ALTER TABLE devices ADD COLUMN manufacturer VARCHAR(50) DEFAULT '辰烁科技';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='devices' AND column_name='firmware_arm') THEN
        ALTER TABLE devices ADD COLUMN firmware_arm VARCHAR(50);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='devices' AND column_name='firmware_esp') THEN
        ALTER TABLE devices ADD COLUMN firmware_esp VARCHAR(50);
    END