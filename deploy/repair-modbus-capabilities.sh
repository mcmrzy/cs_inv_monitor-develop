#!/usr/bin/env bash
# Fixed repair for the deployed Modbus source; stdin is a checked migration tarball.
set -Eeuo pipefail
source_sha=536d094df7a25eb46d3a800316adae81dab2aa3f
migration_sha=$1
[[ "$migration_sha" =~ ^[a-f0-9]{64}$ ]]
grep -Fxq "IMAGE_TAG=$source_sha" /opt/inv-mqtt/deploy/.env.prod
test "$(docker inspect --format '{{.State.Running}} {{.Config.Image}}' business-api)" = \
  "true ghcr.io/mcmrzy/inv-api-server:$source_sha"

# Report catalog grants only; device identifiers and configuration secrets stay private.
docker exec -i inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' <<'SQL'
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM schema_migrations WHERE version=138
      AND name IS DISTINCT FROM '138_modbus_panel_capabilities.up.sql') THEN
    RAISE EXCEPTION 'Migration version 138 is already assigned to another file';
  END IF;
END $$;
SELECT m.model_code, count(c.id), COALESCE(string_agg(c.command_code || CASE WHEN c.is_enabled THEN '' ELSE ' (disabled)' END, ',' ORDER BY c.command_code),'')
FROM device_models m LEFT JOIN device_model_commands c ON c.model_id=m.id
WHERE m.model_code IN ('PWR2KH12H1','3KU','6KU','12KU')
GROUP BY m.model_code ORDER BY m.model_code;
SQL

umask 077
backup=/opt/inv-mqtt/database-backups/modbus-capabilities-138-$(date -u +%Y%m%dT%H%M%SZ).dump
mkdir -p /opt/inv-mqtt/database-backups
docker exec inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup.partial"
test -s "$backup.partial"
docker exec -i inv-postgres pg_restore --list < "$backup.partial" > /dev/null
mv "$backup.partial" "$backup"
sha256sum "$backup" > "$backup.sha256"
echo 'Full database backup verified before capability repair.'

incoming=$(mktemp -d /opt/inv-mqtt/.capabilities-138.XXXXXX)
trap 'rm -rf "$incoming"' EXIT
tar xzf - -C "$incoming"
filename=138_modbus_panel_capabilities.up.sql
printf '%s  %s\n' "$migration_sha" "$incoming/$filename" | sha256sum -c -
target=/opt/inv-mqtt/database/migrations/$filename
if [ -e "$target" ]; then
  printf '%s  %s\n' "$migration_sha" "$target" | sha256sum -c -
else
  temporary=$(mktemp /opt/inv-mqtt/database/migrations/.capabilities-138.XXXXXX)
  cp "$incoming/$filename" "$temporary"
  chmod 644 "$temporary"
  printf '%s  %s\n' "$migration_sha" "$temporary" | sha256sum -c -
  mv -n "$temporary" "$target"
  printf '%s  %s\n' "$migration_sha" "$target" | sha256sum -c -
fi

# Startup migrations are a barrier before the API can become healthy.
docker restart business-api > /dev/null
healthy=0
for attempt in $(seq 1 60); do
  if [ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' business-api)" = healthy ]; then
    healthy=1
    break
  fi
  sleep 2
done
test "$healthy" = 1
docker exec -i inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version=138 AND name='138_modbus_panel_capabilities.up.sql') THEN
    RAISE EXCEPTION 'Modbus capability migration 138 is missing';
  END IF;
END $$;
SQL
docker exec -i inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' < "$incoming/verify.sql"
echo 'Migration 138 applied by API startup runner and production catalog verified.'
