-- 增强 device_cmd_logs 表：支持命令全生命周期追踪
-- 新增字段：task_id（唯一标识）、params（命令参数）、status（执行状态）、data（返回数据）

-- 1. 新增列
ALTER TABLE device_cmd_logs ADD COLUMN IF NOT EXISTS task_id VARCHAR(64);
ALTER TABLE device_cmd_logs ADD COLUMN IF NOT EXISTS params JSONB DEFAULT '{}';
ALTER TABLE device_cmd_logs ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'pending';
ALTER TABLE device_cmd_logs ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}';

-- 2. 索引
CREATE INDEX IF NOT EXISTS idx_cmd_logs_task_id ON device_cmd_logs(task_id);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_status ON device_cmd_logs(status);
CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn_created ON device_cmd_logs(device_sn, sent_at DESC);

-- 3. 回填已有记录的 status（旧数据 result 不为空视为 success）
UPDATE device_cmd_logs SET status = CASE
    WHEN result = 'ok' OR result = 'success' THEN 'success'
    WHEN result = 'failed' OR result = 'error' THEN 'failed'
    ELSE 'completed'
END WHERE status IS NULL AND result IS NOT NULL;
