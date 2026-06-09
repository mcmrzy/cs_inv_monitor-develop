#!/bin/bash
# ============================================================
# PostgreSQL Backup Script
# - Full logical backup with pg_dump
# - Retention: keep last 7 daily, 4 weekly, 3 monthly
# Run via cron: 0 3 * * * /scripts/backup.sh
# ============================================================

set -euo pipefail

PGHOST="${DB_HOST:-postgres}"
PGPORT="${DB_PORT:-5432}"
PGUSER="${DB_USER:-postgres}"
PGPASSWORD="${DB_PASSWORD}"
PGDATABASE="${DB_NAME:-inv_mqtt}"
export PGPASSWORD

BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=3

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DAY_OF_WEEK=$(date +%u)
DAY_OF_MONTH=$(date +%d)

mkdir -p "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly" "$BACKUP_DIR/monthly"

echo "[$(date)] Starting backup of $PGDATABASE..."

DUMP_FILE="$BACKUP_DIR/daily/${PGDATABASE}_${TIMESTAMP}.sql.gz"

pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
  --format=plain --no-owner --no-privileges | gzip > "$DUMP_FILE"

DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
echo "[$(date)] Backup saved: $DUMP_FILE ($DUMP_SIZE)"

if [ "$DAY_OF_WEEK" = "7" ]; then
  cp "$DUMP_FILE" "$BACKUP_DIR/weekly/"
  echo "[$(date)] Weekly backup created"
fi

if [ "$DAY_OF_MONTH" = "01" ]; then
  cp "$DUMP_FILE" "$BACKUP_DIR/monthly/"
  echo "[$(date)] Monthly backup created"
fi

echo "[$(date)] Cleaning old backups..."
find "$BACKUP_DIR/daily" -name "*.sql.gz" -mtime +$RETENTION_DAILY -delete
find "$BACKUP_DIR/weekly" -name "*.sql.gz" -mtime +$((RETENTION_WEEKLY * 7)) -delete
find "$BACKUP_DIR/monthly" -name "*.sql.gz" -mtime +$((RETENTION_MONTHLY * 30)) -delete

echo "[$(date)] Backup completed successfully"
