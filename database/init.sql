-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Run base schema
\i /docker-entrypoint-initdb.d/01-schema.sql

-- Run TimescaleDB hypertable setup
\i /docker-entrypoint-initdb.d/02-timescaledb.sql

-- Run architecture upgrade (RBAC + model fields)
\i /docker-entrypoint-initdb.d/03-upgrade.sql
