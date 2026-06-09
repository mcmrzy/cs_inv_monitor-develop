-- 修复 alarms 表缺失列（API 代码期望的列名）
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS user_id BIGINT;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS station_id BIGINT;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS alarm_level SMALLINT;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS fault_code VARCHAR(50);
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS fault_message VARCHAR(500);
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS fault_detail TEXT;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMP;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS recovered_at TIMESTAMP;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS handled_at TIMESTAMP;
ALTER TABLE alarms ADD COLUMN IF NOT EXISTS handled_by BIGINT;

-- 回填已有数据的 user_id（从 devices 表关联）
UPDATE alarms a SET user_id = d.user_id
FROM devices d WHERE a.device_sn = d.sn AND a.user_id IS NULL;

-- 回填 occurred_at（用 created_at）
UPDATE alarms SET occurred_at = created_at WHERE occurred_at IS NULL;

-- 回填 alarm_level（用 level）
UPDATE alarms SET alarm_level = level WHERE alarm_level IS NULL;

-- 回填 fault_message（用 message）
UPDATE alarms SET fault_message = message WHERE fault_message IS NULL;

CREATE INDEX IF NOT EXISTS idx_alarms_user ON alarms(user_id);
CREATE INDEX IF NOT EXISTS idx_alarms_occurred ON alarms(occurred_at DESC);

SELECT 'Alarms columns fixed' AS result;
