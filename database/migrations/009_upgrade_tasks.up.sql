-- =====================================================
-- Migration 009: OTA升级任务架构重构
-- 新增 upgrade_tasks 表，device_upgrades 新增 task_id
-- =====================================================

-- 1. 升级任务表
CREATE TABLE IF NOT EXISTS upgrade_tasks (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(200) NOT NULL DEFAULT '',
    task_type       VARCHAR(20) NOT NULL,               -- 'single' | 'package'
    firmware_id     BIGINT,                              -- 单芯片模式关联 firmware_versions
    package_id      BIGINT,                              -- 升级包模式关联 upgrade_packages
    model           VARCHAR(100) NOT NULL,
    target_version  VARCHAR(50) NOT NULL DEFAULT '',
    status          VARCHAR(20) NOT NULL DEFAULT 'draft', -- draft/pending/scheduled/running/completed/partial_success/failed/cancelled
    execute_mode    VARCHAR(20) NOT NULL DEFAULT 'manual', -- 'immediate' | 'scheduled' | 'manual'
    scheduled_at    TIMESTAMP,
    rollout_percent INTEGER NOT NULL DEFAULT 100,
    total_devices   INTEGER NOT NULL DEFAULT 0,
    success_count   INTEGER NOT NULL DEFAULT 0,
    failed_count    INTEGER NOT NULL DEFAULT 0,
    created_by      BIGINT,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    executed_at     TIMESTAMP,
    completed_at    TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ut_status ON upgrade_tasks(status);
CREATE INDEX IF NOT EXISTS idx_ut_model ON upgrade_tasks(model);
CREATE INDEX IF NOT EXISTS idx_ut_created ON upgrade_tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ut_type ON upgrade_tasks(task_type);

-- 2. device_upgrades 新增 task_id
ALTER TABLE device_upgrades ADD COLUMN IF NOT EXISTS task_id BIGINT;
CREATE INDEX IF NOT EXISTS idx_du_task_id ON device_upgrades(task_id);
