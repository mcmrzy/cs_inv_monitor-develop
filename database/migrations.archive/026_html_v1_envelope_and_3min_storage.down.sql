-- Rollback intentionally keeps telemetry columns and data. Remove only objects
-- that have no predecessor and restore the original two-column uniqueness.
DROP TABLE IF EXISTS device_ingest_errors;
DROP INDEX IF EXISTS uq_device_cell_samples_message;
DROP INDEX IF EXISTS uq_device_telemetry_3min_message;
ALTER TABLE device_cell_samples ADD CONSTRAINT device_cell_samples_pkey PRIMARY KEY(device_sn,event_time);
ALTER TABLE device_telemetry_3min ADD CONSTRAINT device_telemetry_3min_pkey PRIMARY KEY(device_sn,event_time);
DELETE FROM schema_migrations WHERE version=26;

