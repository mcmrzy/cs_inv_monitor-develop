DO $$
BEGIN
    RAISE NOTICE 'Creating TimescaleDB extension...';
END $$;
CREATE EXTENSION IF NOT EXISTS timescaledb;
