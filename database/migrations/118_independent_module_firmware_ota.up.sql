-- Migration 118: 独立模块固件升级数据约束
--
-- 将 OTA 从「升级包」切换为「按设备、按模块独立发布/升级」：
--   1. firmware_versions 增加发布生命周期（draft/published/disabled）
--   2. device_upgrades 支持同一固件多次手动尝试（按任务区分，禁止同任务同模块重复）
--   3. ota_idempotency_requests 支持批量触发幂等
--   4. 收口未运行的旧 package 任务（历史明细保留）
--
-- 幂等：所有对象 IF NOT EXISTS / 条件创建。

-- 1. firmware_versions 发布生命周期
ALTER TABLE firmware_versions
    ADD COLUMN IF NOT EXISTS release_status VARCHAR(16) NOT NULL DEFAULT 'draft',
    ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;

-- 旧行回填：status=1 → published（published_at=created_at），status=0 → disabled
UPDATE firmware_versions
SET release_status = CASE WHEN status = 1 THEN 'published' ELSE 'disabled' END,
    published_at   = CASE WHEN status = 1 THEN created_at ELSE NULL END
WHERE release_status = 'draft' AND status IN (0, 1);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_firmware_release_status'
    ) THEN
        ALTER TABLE firmware_versions ADD CONSTRAINT ck_firmware_release_status
            CHECK (release_status IN ('draft', 'published', 'disabled'));
    END IF;
END $$;

-- 唯一性：同 model + target_chip + version 不得重复（含软删行）。
-- 若存在历史重复组则显式失败，禁止自动挑选赢家或删除历史。
DO $$
DECLARE
    dup_text text;
BEGIN
    SELECT string_agg(
               format('%s/%s/%s (count=%s)', model, target_chip, version, cnt),
               '; '
           )
    INTO dup_text
    FROM (
        SELECT model, COALESCE(target_chip, '') AS target_chip, version, COUNT(*) AS cnt
        FROM firmware_versions
        GROUP BY model, COALESCE(target_chip, ''), version
        HAVING COUNT(*) > 1
    ) d;
    IF dup_text IS NOT NULL THEN
        RAISE EXCEPTION 'firmware_versions duplicate (model,target_chip,version) groups: %', dup_text;
    END IF;

    DROP INDEX IF EXISTS uq_firmware_versions_model_chip_version;
    CREATE UNIQUE INDEX IF NOT EXISTS uq_firmware_model_target_version
        ON firmware_versions (model, target_chip, version);
END $$;

-- 发布查询索引
CREATE INDEX IF NOT EXISTS idx_firmware_release_published
    ON firmware_versions (model, target_chip, release_status, published_at DESC, id DESC);

-- 2. device_upgrades：允许同一固件多次尝试
-- 删除覆盖型唯一索引（它把同一 firmware 钉死为一行，阻碍重复手动升级）
DROP INDEX IF EXISTS uq_du_device_firmware_package;

-- 同一任务同一设备同一模块最多一条
CREATE UNIQUE INDEX IF NOT EXISTS uq_du_task_device_chip
    ON device_upgrades (task_id, device_sn, target_chip)
    WHERE task_id IS NOT NULL;

-- 历史筛选索引
CREATE INDEX IF NOT EXISTS idx_du_history_filter
    ON device_upgrades (created_at DESC, device_sn, target_chip, status);

-- 3. 幂等请求存储
CREATE TABLE IF NOT EXISTS ota_idempotency_requests (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL,
    device_sn       VARCHAR(50) NOT NULL,
    idempotency_key VARCHAR(64) NOT NULL,
    operation       VARCHAR(32) NOT NULL,          -- trigger | rollback
    payload_hash    VARCHAR(64) NOT NULL,
    task_ids        JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ota_idem_user_device_op_key
    ON ota_idempotency_requests (user_id, device_sn, operation, idempotency_key);

CREATE INDEX IF NOT EXISTS idx_ota_idem_created
    ON ota_idempotency_requests (created_at DESC);

-- 4. 收口未运行的旧 package 任务（不改历史明细）
UPDATE upgrade_tasks
SET status = 'cancelled',
    completed_at = COALESCE(completed_at, NOW()),
    notes = CASE
        WHEN notes = '' THEN 'legacy package retired by migration 118'
        ELSE notes || ' | legacy package retired by migration 118'
    END
WHERE task_type = 'package'
  AND status IN ('pending', 'scheduled');
