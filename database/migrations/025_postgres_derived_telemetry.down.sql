DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='timescaledb') THEN
        PERFORM delete_job(job_id)
        FROM timescaledb_information.jobs
        WHERE proc_schema='public' AND proc_name='refresh_device_energy_month';
    END IF;
END $$;

DROP TRIGGER IF EXISTS trg_latest_cells ON device_cell_samples;
DROP TRIGGER IF EXISTS trg_telemetry_v2_derived ON device_telemetry_3min;
DROP FUNCTION IF EXISTS maintain_latest_cells();
DROP FUNCTION IF EXISTS maintain_telemetry_v2_derived();
DROP PROCEDURE IF EXISTS refresh_device_energy_month(INTEGER,JSONB);

DELETE FROM schema_migrations WHERE version=25;
