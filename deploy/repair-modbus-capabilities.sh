#!/usr/bin/env bash
# Fixed repair for the deployed Modbus source; stdin is a checked migration tarball.
set -Eeuo pipefail
source_sha=536d094df7a25eb46d3a800316adae81dab2aa3f
migration_sha=$1
version=${2:-138}
case "$version" in
  138) filename=138_modbus_panel_capabilities.up.sql ;;
  139) filename=139_modbus_panel_fields.up.sql ;;
  140) filename=140_modbus_panel_catalog.up.sql ;;
  *) echo 'Unsupported Modbus catalog migration.' >&2; exit 1 ;;
esac
[[ "$migration_sha" =~ ^[a-f0-9]{64}$ ]]
grep -Fxq "IMAGE_TAG=$source_sha" /opt/inv-mqtt/deploy/.env.prod
test "$(docker inspect --format '{{.State.Running}} {{.Config.Image}}' business-api)" = \
  "true ghcr.io/mcmrzy/inv-api-server:$source_sha"

query() {
  docker exec -i inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At "$@"' sh "$@"
}

recorded_name=$(query -c "SELECT name FROM schema_migrations WHERE version=$version")
if [ -n "$recorded_name" ] && [ "$recorded_name" != "$filename" ]; then
  echo "Migration version $version is already assigned to another file." >&2
  exit 1
fi

field_counts() {
  query <<'SQL'
SELECT m.model_code, count(f.field_key)
FROM device_models m LEFT JOIN device_model_fields f ON f.model_id = m.id
WHERE m.model_code IN ('PWR2KH12H1', '3KU', '6KU', '12KU')
  AND m.is_active AND m.lifecycle_status != 'retired'
GROUP BY m.model_code ORDER BY m.model_code;
SQL
}

# Report catalog data only.
if [ "$version" = 139 ] || [ "$version" = 140 ]; then
  fields_before=$(field_counts)
  printf 'Model field counts before repair:\n%s\n' "$fields_before"
else
  query <<'SQL'
SELECT m.model_code, count(c.id), COALESCE(string_agg(c.command_code || CASE WHEN c.is_enabled THEN '' ELSE ' (disabled)' END, ',' ORDER BY c.command_code),'')
FROM device_models m LEFT JOIN device_model_commands c ON c.model_id=m.id
WHERE m.model_code IN ('PWR2KH12H1','3KU','6KU','12KU')
GROUP BY m.model_code ORDER BY m.model_code;
SQL
fi

umask 077
backup=/opt/inv-mqtt/database-backups/modbus-catalog-$version-$(date -u +%Y%m%dT%H%M%SZ).dump
mkdir -p /opt/inv-mqtt/database-backups
docker exec inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup.partial"
test -s "$backup.partial"
docker exec -i inv-postgres pg_restore --list < "$backup.partial" > /dev/null
mv "$backup.partial" "$backup"
sha256sum "$backup" > "$backup.sha256"
echo 'Full database backup verified before catalog repair.'

incoming=$(mktemp -d /opt/inv-mqtt/.modbus-catalog-"$version".XXXXXX)
trap 'rm -rf "$incoming"' EXIT
tar xzf - -C "$incoming"
printf '%s  %s\n' "$migration_sha" "$incoming/$filename" | sha256sum -c -
target=/opt/inv-mqtt/database/migrations/$filename
if [ -e "$target" ]; then
  printf '%s  %s\n' "$migration_sha" "$target" | sha256sum -c -
else
  temporary=$(mktemp /opt/inv-mqtt/database/migrations/.modbus-catalog-"$version".XXXXXX)
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
recorded_name=$(query -c "SELECT name FROM schema_migrations WHERE version=$version")
test "$recorded_name" = "$filename"
query < "$incoming/verify.sql"

if [ "$version" = 139 ]; then
  fields_after=$(field_counts)
  printf 'Model field counts after repair:\n%s\n' "$fields_after"
  while IFS='|' read -r model_code field_count; do
    count_after=$(awk -F'|' -v model="$model_code" '$1 == model { print $2 }' <<< "$fields_after")
    expected_count=$field_count
    if [ "$field_count" = 0 ]; then
      expected_count=27
    fi
    if [ "$count_after" != "$expected_count" ]; then
      echo "Unexpected field count for $model_code: expected $expected_count, got ${count_after:-missing}." >&2
      exit 1
    fi
  done <<< "$fields_before"
fi
echo "Migration $version applied by API startup runner and production catalog verified."
