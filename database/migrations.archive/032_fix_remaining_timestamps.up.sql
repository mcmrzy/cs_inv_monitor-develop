-- =====================================================
-- Migration 032: 修复剩余表的 TIMESTAMP（无时区）列
-- 补充迁移 016 未覆盖的 OTA 升级相关表
-- 使用 AT TIME ZONE 'UTC' 将无时区时间戳解释为 UTC 时间
-- =====================================================

-- 1. 修复 device_upgrades 表（migration 006 创建）
--    started_at, completed_at: 可为 NULL，USING ... AT TIME ZONE 对 NULL 自动返回 NULL
--    created_at, updated_at:   NOT NULL DEFAULT NOW()
ALTER TABLE device_upgrades
    ALTER COLUMN started_at TYPE TIMESTAMPTZ USING started_at AT TIME ZONE 'UTC',
    ALTER COLUMN completed_at TYPE TIMESTAMPTZ USING completed_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';

-- 2. 修复 upgrade_packages 表（migration 008 创建）
ALTER TABLE upgrade_packages
    ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';

-- 3. upgrade_package_items 表（migration 008 创建）
--    该表仅有 id, package_id, firmware_id, target_chip, firmware_version 列，
--    不含任何时间戳列，无需修复。

-- 4. 修复 upgrade_tasks 表（migration 009 创建）
--    scheduled_at, executed_at, completed_at: 可为 NULL
--    created_at, updated_at:                  NOT NULL DEFAULT NOW()
ALTER TABLE upgrade_tasks
    ALTER COLUMN scheduled_at TYPE TIMESTAMPTZ USING scheduled_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN executed_at TYPE TIMESTAMPTZ USING executed_at AT TIME ZONE 'UTC',
    ALTER COLUMN completed_at TYPE TIMESTAMPTZ USING completed_at AT TIME ZONE 'UTC',
    ALTER COLUMN updated_at TYPE TIMESTAMPTZ USING updated_at AT TIME ZONE 'UTC';
