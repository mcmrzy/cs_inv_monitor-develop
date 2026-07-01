-- =====================================================
-- Migration 006: 重构OTA系统 - device_upgrades 替代 ota_tasks
-- =====================================================

-- 1. 创建 device_upgrades 表
CREATE TABLE IF NOT EXISTS device_upgrades (
    id              BIGSERIAL PRIMARY KEY,
    device_sn       VARCHAR(50) NOT NULL,
    firmware_id     BIGINT NOT NULL REFERENCES firmware_versions(id),
    firmware_version VARCHAR(50) NOT NULL,
    target_chip     VARCHAR(50) NOT NULL DEFAULT '',
    old_version     VARCHAR(50) NOT NULL DEFAULT '',
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending / downloading / upgrading / success / failed / cancelled
    progress        INTEGER NOT NULL DEFAULT 0,
    error_message   TEXT NOT NULL DEFAULT '',
    retry_count     INTEGER NOT NULL DEFAULT 0,
    pushed_by       BIGINT,
    started_at      TIMESTAMP,
    completed_at    TIMESTAMP,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW(),

    -- UPSERT约束: 同一设备 + 同一固件 = 唯一记录
    CONSTRAINT uq_device_firmware UNIQUE (device_sn, firmware_id)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_du_device_sn ON device_upgrades(device_sn);
CREATE INDEX IF NOT EXISTS idx_du_firmware_id ON device_upgrades(firmware_id);
CREATE INDEX IF NOT EXISTS idx_du_status ON device_upgrades(status);
CREATE INDEX IF NOT EXISTS idx_du_created_at ON device_upgrades(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_du_device_status ON device_upgrades(device_sn, status);

-- 2. 数据迁移: 从 ota_task_devices 迁移最近的升级记录
-- 对每个 device_sn + firmware_id 组合, 只保留最新的一条记录
INSERT INTO device_upgrades (device_sn, firmware_id, firmware_version, target_chip,
    old_version, status, progress, error_message, retry_count,
    started_at, completed_at, created_at, updated_at)
SELECT DISTINCT ON (td.device_sn, t.firmware_id)
    td.device_sn,
    t.firmware_id,
    COALESCE(t.firmware_version, ''),
    COALESCE(f.target_chip, ''),
    COALESCE(td.old_version, ''),
    CASE
        WHEN td.status = 'success' THEN 'success'
        WHEN td.status = 'failed' THEN 'failed'
        WHEN td.status IN ('running', 'upgrading') THEN 'upgrading'
        ELSE 'pending'
    END,
    COALESCE(td.progress, 0),
    COALESCE(td.error_message, ''),
    0,
    td.started_at,
    td.completed_at,
    td.created_at,
    td.created_at
FROM ota_task_devices td
JOIN ota_tasks t ON td.task_id = t.id
LEFT JOIN firmware_versions f ON t.firmware_id = f.id
ORDER BY td.device_sn, t.firmware_id, td.id DESC
ON CONFLICT (device_sn, firmware_id) DO NOTHING;

-- 3. 重命名旧表(保留备份, 不立即删除)
DO $$
BEGIN
    -- 检查旧表是否存在再重命名
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ota_task_devices') THEN
        ALTER TABLE ota_task_devices RENAME TO ota_task_devices_backup;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ota_tasks') THEN
        ALTER TABLE ota_tasks RENAME TO ota_tasks_backup;
    END IF;
END $$;
