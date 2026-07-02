-- =====================================================
-- Migration 012: OTA 任务来源追踪与升级包发布增强
-- 1. upgrade_tasks 新增 source/triggered_by/notes
-- 2. device_upgrades 新增 source
-- 3. upgrade_packages 新增 user_version/user_changelog/rollout_type/rollout_targets/is_published
-- =====================================================

-- 1. 升级任务来源追踪
ALTER TABLE upgrade_tasks
    ADD COLUMN IF NOT EXISTS source       VARCHAR(20)  NOT NULL DEFAULT 'admin',
    ADD COLUMN IF NOT EXISTS triggered_by BIGINT,
    ADD COLUMN IF NOT EXISTS notes        TEXT         NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_ut_source ON upgrade_tasks(source);
CREATE INDEX IF NOT EXISTS idx_ut_triggered_by ON upgrade_tasks(triggered_by);

-- 2. 设备升级记录来源
ALTER TABLE device_upgrades
    ADD COLUMN IF NOT EXISTS source VARCHAR(20) NOT NULL DEFAULT 'admin';

CREATE INDEX IF NOT EXISTS idx_du_source ON device_upgrades(source);

-- 3. 升级包面向 App 的发布控制
ALTER TABLE upgrade_packages
    ADD COLUMN IF NOT EXISTS user_version    VARCHAR(50)  NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS user_changelog  TEXT         NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS rollout_type    VARCHAR(20)  NOT NULL DEFAULT 'all', -- 'all' | 'model' | 'user' | 'device'
    ADD COLUMN IF NOT EXISTS rollout_targets TEXT         NOT NULL DEFAULT '',     -- 逗号分隔的 model/user_id/sn
    ADD COLUMN IF NOT EXISTS is_published    BOOLEAN      NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_pkg_published ON upgrade_packages(is_published);
CREATE INDEX IF NOT EXISTS idx_pkg_rollout_type ON upgrade_packages(rollout_type);
