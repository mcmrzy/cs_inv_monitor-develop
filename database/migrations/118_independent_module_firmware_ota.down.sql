-- Migration 118 down: 回滚独立模块固件数据约束
-- 只移除本次新增对象；绝不删除 OTA 历史明细。

-- 1. 幂等表
DROP TABLE IF EXISTS ota_idempotency_requests;

-- 2. device_upgrades 新索引
DROP INDEX IF EXISTS uq_du_task_device_chip;
DROP INDEX IF EXISTS idx_du_history_filter;

-- 恢复覆盖型唯一索引前检测重复尝试；存在重复则明确失败，禁止删除历史。
DO $$
DECLARE
    dup_count bigint;
BEGIN
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT device_sn, firmware_id, COALESCE(upgrade_package_id, 0)
        FROM device_upgrades
        GROUP BY device_sn, firmware_id, COALESCE(upgrade_package_id, 0)
        HAVING COUNT(*) > 1
    ) d;
    IF dup_count > 0 THEN
        RAISE EXCEPTION 'cannot restore uq_du_device_firmware_package: % duplicate groups exist; refuse to delete history', dup_count;
    END IF;

    CREATE UNIQUE INDEX IF NOT EXISTS uq_du_device_firmware_package
        ON device_upgrades (device_sn, firmware_id, COALESCE(upgrade_package_id, 0));
END $$;

-- 3. firmware_versions 发布生命周期
DROP INDEX IF EXISTS idx_firmware_release_published;
DROP INDEX IF EXISTS uq_firmware_model_target_version;

-- 恢复 114 的部分唯一索引（仅约束启用行）
CREATE UNIQUE INDEX IF NOT EXISTS uq_firmware_versions_model_chip_version
    ON firmware_versions (model, target_chip, version)
    WHERE status = 1;

ALTER TABLE firmware_versions
    DROP CONSTRAINT IF EXISTS ck_firmware_release_status;

ALTER TABLE firmware_versions
    DROP COLUMN IF EXISTS release_status,
    DROP COLUMN IF EXISTS published_at;
