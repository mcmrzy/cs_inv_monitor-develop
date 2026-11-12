#!/usr/bin/env bash
# Invoked over SSH by Release Android; stdin is the checked release tarball.
set -Eeuo pipefail
source_sha=$1
apk_sha256=$2
[[ "$source_sha" =~ ^[a-f0-9]{40}$ && "$apk_sha256" =~ ^[a-f0-9]{64}$ ]]
grep -Fxq "IMAGE_TAG=$source_sha" /opt/inv-mqtt/deploy/.env.prod
incoming=$(mktemp -d /opt/inv-mqtt/.app-release.XXXXXX)
trap 'rm -rf "$incoming"' EXIT
tar xzf - -C "$incoming"
cd "$incoming"
printf '%s  %s\n' "$apk_sha256" app-release.apk | sha256sum -c -
filename=$(cat filename)
[[ "$filename" =~ ^com\.csergy\.app1-1\.1\.16-44-[a-f0-9]{12}\.apk$ ]]

# Verify the live registry and bindings, rather than inferring migration success from container health.
docker exec -i inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' < verify.sql

umask 077
backup=/opt/inv-mqtt/database-backups/app-versions-$(date -u +%Y%m%dT%H%M%SZ)-44.dump
mkdir -p /opt/inv-mqtt/database-backups
docker exec inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t app_versions -Fc' > "$backup.partial"
test -s "$backup.partial"
docker exec -i inv-postgres pg_restore --list < "$backup.partial" > /dev/null
mv "$backup.partial" "$backup"

docker exec -u root business-api mkdir -p /data/firmware/apps/android
docker cp app-release.apk "business-api:/data/firmware/apps/android/$filename.partial"
docker exec -u root business-api sh -c '
  set -eu
  cd /data/firmware/apps/android
  printf "%s  %s\n" "$2" "$1.partial" | sha256sum -c -
  if [ -f "$1" ]; then
    printf "%s  %s\n" "$2" "$1" | sha256sum -c -
    rm "$1.partial"
  else
    chmod 644 "$1.partial"
    chown app:app "$1.partial"
    mv "$1.partial" "$1"
  fi
' _ "$filename" "$apk_sha256"

# The file is durable and verified before the update becomes visible to users.
docker exec -i inv-postgres sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At' < publish.sql
echo "Published Android 1.1.16+44; previous version rows and installation packages retained."
