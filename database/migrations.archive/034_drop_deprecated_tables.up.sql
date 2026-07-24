-- =====================================================
-- Migration 034: Drop deprecated tables
-- =====================================================
-- Drops the following deprecated tables that have been superseded
-- by newer replacements:
--
--   1. ota_records            -> replaced by device_upgrades (migration 006)
--   2. device_model_protocol  -> replaced by device_protocol_versions (migration 023)
--   3. device_model_field     -> replaced by device_model_fields plural (migration 023)
--
-- Go code reference audit (grep results):
--   ota_records:
--     - tests/integration/db_migration_test.go (expected tables list only)
--     - NO production Go code references — SAFE TO DROP
--
--   device_model_protocol:
--     Go code has been fully migrated to device_protocol_versions /
--     device_protocol_fields via model_registry_repository.go.
--     model_repository.go and device_repository.go no longer reference
--     the legacy table — SAFE TO DROP
--
--   device_model_field (singular):
--     Go code has been fully migrated to device_model_fields (plural)
--     via model_registry_repository.go.
--     model_repository.go and device_repository.go no longer reference
--     the legacy table — SAFE TO DROP
--
-- NOTE: tests/integration/db_migration_test.go lists all three tables in its
--       expectedTables slice. Update that test after running this migration.
-- =====================================================

-- 1. Drop ota_records (safe — no production Go code references)
DROP TABLE IF EXISTS ota_records;

-- 2. device_model_protocol — Go code migrated to new tables, safe to DROP
DROP TABLE IF EXISTS device_model_protocol;

-- 3. device_model_field (singular) — Go code migrated to new tables, safe to DROP
DROP TABLE IF EXISTS device_model_field;
