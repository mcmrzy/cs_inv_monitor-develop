-- 011: Extend the legacy (singular) model-field table when it is present.
--
-- Fresh canonical baselines use device_model_fields (plural). Its group_code
-- column replaces group_name, while command parameter_schema is the normalized
-- replacement for the legacy per-field control_params JSON. Adding the old
-- columns to the plural table would recreate a second, conflicting contract, so
-- that shape is deliberately a safe no-op.
DO $$
BEGIN
    IF to_regclass('device_model_field') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE device_model_field '
             || 'ADD COLUMN IF NOT EXISTS group_name VARCHAR(64) NOT NULL DEFAULT ''''';
        EXECUTE 'ALTER TABLE device_model_field '
             || 'ADD COLUMN IF NOT EXISTS control_params JSONB';
    ELSIF to_regclass('device_model_fields') IS NOT NULL THEN
        RAISE NOTICE 'migration 011: canonical device_model_fields already uses group_code and normalized command parameter_schema; no legacy columns added';
    ELSE
        RAISE NOTICE 'migration 011: no model-field table exists yet; skipping legacy extension';
    END IF;
END
$$;
