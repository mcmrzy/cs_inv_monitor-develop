-- 061 down: remove the explicit channel backfill control plane.

DROP INDEX IF EXISTS idx_channel_migration_quarantine_last_run_fk;
DROP INDEX IF EXISTS idx_channel_migration_quarantine_first_run_fk;
ALTER TABLE channel_migration_quarantine
    DROP COLUMN IF EXISTS occurrence_count,
    DROP COLUMN IF EXISTS last_seen_run_id,
    DROP COLUMN IF EXISTS first_run_id;

DROP TABLE IF EXISTS channel_migration_shadow_diffs;
DROP TABLE IF EXISTS channel_migration_entity_map;
DROP TABLE IF EXISTS channel_migration_items;
DROP TABLE IF EXISTS channel_migration_checkpoints;
DROP TABLE IF EXISTS channel_migration_runs;
