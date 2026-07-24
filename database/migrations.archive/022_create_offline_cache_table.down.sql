-- 022 down: remove the cached telemetry columns added by the up migration.
DO $$
BEGIN
    IF to_regclass('public.device_telemetry') IS NOT NULL THEN
        ALTER TABLE public.device_telemetry DROP COLUMN IF EXISTS grid_frequency;
        ALTER TABLE public.device_telemetry DROP COLUMN IF EXISTS battery_soc;
        ALTER TABLE public.device_telemetry DROP COLUMN IF EXISTS battery_power;
        ALTER TABLE public.device_telemetry DROP COLUMN IF EXISTS pv_power;
    END IF;
END
$$;
