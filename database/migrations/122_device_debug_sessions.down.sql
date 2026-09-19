-- 122 down: 仅用于测试与未投产环境；线上遵循只增不改的迁移约定。
ALTER TABLE device_telemetry_3min DROP COLUMN IF EXISTS buck2_current;
ALTER TABLE device_telemetry_3min DROP COLUMN IF EXISTS buck1_current;
DROP INDEX IF EXISTS uq_device_debug_active_sn;
DROP INDEX IF EXISTS idx_device_debug_status_expires;
DROP INDEX IF EXISTS idx_device_debug_sn_created;
DROP TABLE IF EXISTS device_debug_sessions;
