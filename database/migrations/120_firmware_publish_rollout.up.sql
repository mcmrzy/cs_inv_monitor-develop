-- Migration 120: 固件发布支持范围/灰度/回退目标
-- 1. firmware_versions 增加发布策略字段
-- 2. 设备侧可见性按 scope + 确定性灰度过滤

ALTER TABLE firmware_versions
    ADD COLUMN IF NOT EXISTS rollout_percent INTEGER NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS rollout_type VARCHAR(16) NOT NULL DEFAULT 'all',
    ADD COLUMN IF NOT EXISTS rollout_targets TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS rollback_to_firmware_id BIGINT;

ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS ck_firmware_rollout_percent;
ALTER TABLE firmware_versions
    ADD CONSTRAINT ck_firmware_rollout_percent
    CHECK (rollout_percent BETWEEN 0 AND 100);

ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS ck_firmware_rollout_type;
ALTER TABLE firmware_versions
    ADD CONSTRAINT ck_firmware_rollout_type
    CHECK (rollout_type IN ('all', 'device'));

CREATE INDEX IF NOT EXISTS idx_firmware_versions_rollout
    ON firmware_versions (model, target_chip, release_status, rollout_type);
