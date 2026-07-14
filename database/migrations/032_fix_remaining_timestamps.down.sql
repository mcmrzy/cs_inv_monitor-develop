-- =====================================================
-- Migration 032 (DOWN): 回滚为 TIMESTAMP（无时区）
-- 将 TIMESTAMPTZ 转回 TIMESTAMP，使用 AT TIME ZONE 'UTC' 提取 UTC 时间
-- =====================================================

-- 1. 回滚 device_upgrades 表
ALTER TABLE device_upgrades
    ALTER COLUMN started_at TYPE TIMESTAMP USING started_at AT TIME ZONE 'UTC',
    ALTER COLUMN completed_at TYPE TIMESTAMP USING completed_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at TYPE TIMESTAMP USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN updated_at TYPE TIMESTAMP USING updated_at AT TIME ZONE 'UTC';

-- 2. 回滚 upgrade_packages 表
ALTER TABLE upgrade_packages
    ALTER COLUMN created_at TYPE TIMESTAMP USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN updated_at TYPE TIMESTAMP USING updated_at AT TIME ZONE 'UTC';

-- 3. upgrade_package_items 表无时间戳列，无需回滚

-- 4. 回滚 upgrade_tasks 表
ALTER TABLE upgrade_tasks
    ALTER COLUMN scheduled_at TYPE TIMESTAMP USING scheduled_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at TYPE TIMESTAMP USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN executed_at TYPE TIMESTAMP USING executed_at AT TIME ZONE 'UTC',
    ALTER COLUMN completed_at TYPE TIMESTAMP USING completed_at AT TIME ZONE 'UTC',
    ALTER COLUMN updated_at TYPE TIMESTAMP USING updated_at AT TIME ZONE 'UTC';
