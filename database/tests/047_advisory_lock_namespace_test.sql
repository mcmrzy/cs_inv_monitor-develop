\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    telemetry_def TEXT;
    cells_def TEXT;
BEGIN
    SELECT pg_get_functiondef('maintain_telemetry_v2_derived()'::regprocedure)
      INTO telemetry_def;
    SELECT pg_get_functiondef('maintain_latest_cells()'::regprocedure)
      INTO cells_def;

    IF position('telemetry:v1:' IN telemetry_def) = 0 THEN
        RAISE EXCEPTION 'telemetry trigger is missing its advisory-lock namespace';
    END IF;
    IF position('cells:v1:' IN cells_def) = 0 THEN
        RAISE EXCEPTION 'cell trigger is missing its advisory-lock namespace';
    END IF;
    IF hashtextextended('telemetry:v1:TEST-SN', 0) = hashtextextended('cells:v1:TEST-SN', 0) THEN
        RAISE EXCEPTION 'telemetry and cell lock keys unexpectedly collide';
    END IF;
    IF hashtextextended('telemetry:v1:TEST-SN', 0) = hashtextextended('alarm-lifecycle:v1:TEST-SN:0:1', 0) THEN
        RAISE EXCEPTION 'telemetry and alarm lock keys unexpectedly collide';
    END IF;
END;
$$;

ROLLBACK;
