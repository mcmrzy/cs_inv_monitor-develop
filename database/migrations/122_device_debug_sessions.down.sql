-- 122 down: 仅用于测试与未投产环境；线上遵循只增不改的迁移约定。
-- 注意：不回滚 buck1_current/buck2_current 列——它们由迁移 091 引入（122 仅幂等补齐），
-- 无条件 DROP 会误删存量库中 091 的列。
DROP INDEX IF EXISTS uq_device_debug_active_sn;
DROP INDEX IF EXISTS idx_device_debug_status_expires;
DROP INDEX IF EXISTS idx_device_debug_sn_created;
DROP TABLE IF EXISTS device_debug_sessions;
