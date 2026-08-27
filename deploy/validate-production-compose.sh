#!/usr/bin/env bash

set -euo pipefail

compose_file="${1:-deploy/docker-compose.prod.yml}"
workflow_file="${2:-.github/workflows/cd.yml}"

if [[ ! -f "$compose_file" ]]; then
  echo "production compose file not found: $compose_file" >&2
  exit 1
fi

# Read only top-level service names so this check works without requiring a
# YAML parser on the developer workstation.
services="$(awk '
  /^services:[[:space:]]*$/ { in_services = 1; next }
  in_services && /^[^[:space:]]/ { in_services = 0 }
  in_services && /^  [A-Za-z0-9][A-Za-z0-9_-]*:[[:space:]]*$/ {
    name = $0
    sub(/^  /, "", name)
    sub(/:.*/, "", name)
    print name
  }
' "$compose_file")"

for required_service in kafka mqtt-kafka-bridge; do
  if ! grep -Fxq "$required_service" <<<"$services"; then
    echo "production compose must define service: $required_service" >&2
    exit 1
  fi
done

if ! grep -Eq 'KAFKA_BROKER:[[:space:]]*kafka:29092([[:space:]]|$)' "$compose_file"; then
  echo "inv-device-server must use the in-stack Kafka broker kafka:29092" >&2
  exit 1
fi

if [[ -f "$workflow_file" ]] && ! grep -Fq 'Build & Push mqtt-kafka-bridge' "$workflow_file"; then
  echo "CD workflow must build and push the mqtt-kafka-bridge image" >&2
  exit 1
fi

echo "production compose contains Kafka and mqtt-kafka-bridge"
