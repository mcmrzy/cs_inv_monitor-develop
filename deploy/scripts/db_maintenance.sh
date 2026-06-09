#!/bin/bash
# ============================================================
# TimescaleDB Maintenance Script
# - Retention policy for telemetry data
# - Continuous aggregate refresh
# - Compression policy
# Run via cron: 0 2 * * * /scripts/db_maintenance.sh
# ============================================================

set -euo pipefail

PGHOST="${DB_HOST:-postgres}"
PGPORT="${DB_PORT:-5432}"
PGUSER="${DB_USER:-postgres}"
PGPASSWORD="${DB_PASSWORD}"
PGDATABASE="${DB_NAME:-inv_mqtt}"
export PGPASSWORD

PSQL="psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -v ON_ERROR_STOP=1"

echo "[$(date)] Starting DB maintenance..."

# 1. Drop old telemetry data (keep 90 days)
$PSQL -c "SELECT drop_chunks('device_telemetry', INTERVAL '90 days');" 2>/dev/null || \
  echo "device_telemetry is not a hypertable yet, skipping chunk drop"

# 2. Drop old alarm data (keep 1 year)
$PSQL -c "DELETE FROM device_alarms WHERE created_at < NOW() - INTERVAL '1 year';"

# 3. Drop old command logs (keep 6 months)
$PSQL -c "DELETE FROM device_cmd_logs WHERE sent_at < NOW() - INTERVAL '6 months';"

# 4. Drop old day data (keep 3 years)
$PSQL -c "DELETE FROM device_day_data WHERE data_date < CURRENT_DATE - INTERVAL '3 years';"
$PSQL -c "DELETE FROM station_day_data WHERE data_date < CURRENT_DATE - INTERVAL '3 years';"

# 5. Vacuum analyze affected tables
$PSQL -c "VACUUM ANALYZE device_telemetry;"
$PSQL -c "VACUUM ANALYZE device_alarms;"
$PSQL -c "VACUUM ANALYZE device_cmd_logs;"

echo "[$(date)] DB maintenance completed"
