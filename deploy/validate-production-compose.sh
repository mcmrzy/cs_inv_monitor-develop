#!/usr/bin/env bash

set -euo pipefail

compose_file="${1:-deploy/docker-compose.prod.yml}"
workflow_file="${2:-.github/workflows/cd.yml}"
nginx_file="${3:-deploy/nginx-proxy.conf}"

if [[ ! -f "$compose_file" ]]; then
  echo "production compose file not found: $compose_file" >&2
  exit 1
fi
if [[ ! -r "$workflow_file" ]]; then
  echo "CD workflow file not found: $workflow_file" >&2
  exit 1
fi
if [[ ! -r "$nginx_file" ]]; then
  echo "nginx config file not found: $nginx_file" >&2
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

service_block() {
  local service_name="$1"
  awk -v service="$service_name" '
    $0 ~ "^  " service ":[[:space:]]*$" { in_service = 1 }
    in_service && $0 ~ "^  [A-Za-z0-9][A-Za-z0-9_-]*:[[:space:]]*$" && $0 !~ "^  " service ":[[:space:]]*$" { exit }
    in_service { print }
  ' "$compose_file"
}

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

if ! grep -Fq 'Build & Push mqtt-kafka-bridge' "$workflow_file"; then
  echo "CD workflow must build and push the mqtt-kafka-bridge image" >&2
  exit 1
fi

device_block="$(service_block inv-device-server)"
if ! grep -Fq 'http://localhost:8081/metrics' <<<"$device_block"; then
  echo "inv-device-server container healthcheck must use the liveness endpoint /metrics" >&2
  exit 1
fi

frontend_block="$(service_block inv-admin-frontend)"
if ! grep -Fq 'http://127.0.0.1:8080/' <<<"$frontend_block"; then
  echo "inv-admin-frontend healthcheck must use its IPv4 listener at 127.0.0.1:8080" >&2
  exit 1
fi
if grep -Fq 'http://localhost:8080/' <<<"$frontend_block"; then
  echo "inv-admin-frontend healthcheck must not depend on localhost IPv6 resolution" >&2
  exit 1
fi
if ! grep -Fq -- '- "8080"' <<<"$frontend_block"; then
  echo "inv-admin-frontend must expose the port it actually listens on: 8080" >&2
  exit 1
fi

redis_block="$(service_block redis)"
if ! grep -Fq -- '--maxmemory 384mb' <<<"$redis_block"; then
  echo "redis maxmemory must leave runtime overhead below the 512M container limit" >&2
  exit 1
fi
if grep -Fq 'http://localhost:8081/health' <<<"$device_block"; then
  echo "inv-device-server container healthcheck must not gate startup on MQTT readiness" >&2
  exit 1
fi

for ingress_service in api-gateway inv-admin-frontend nginx; do
  ingress_block="$(service_block "$ingress_service")"
  if grep -Fq 'condition: service_healthy' <<<"$ingress_block"; then
    echo "$ingress_service must remain startable when an upstream readiness check is degraded" >&2
    exit 1
  fi
done

nginx_block="$(service_block nginx)"
if ! grep -Fq 'http://127.0.0.1:8082/livez' <<<"$nginx_block"; then
  echo "nginx container healthcheck must use the local-only liveness endpoint /livez" >&2
  exit 1
fi
if ! grep -Fq 'listen 127.0.0.1:8082;' "$nginx_file" || ! grep -Fq 'location = /livez' "$nginx_file"; then
  echo "nginx config must define the local-only liveness endpoint /livez" >&2
  exit 1
fi
if ! grep -Fq './configs/nginx-security-headers.conf:/etc/nginx/snippets/security-headers.conf:ro' <<<"$nginx_block"; then
  echo "nginx must mount the shared security-header snippet" >&2
  exit 1
fi
if ! grep -Fq 'location ^~ /assets/' "$nginx_file"; then
  echo "nginx immutable caching must be limited to Vite hashed /assets/" >&2
  exit 1
fi
if ! grep -Fq 'public, max-age=86400, must-revalidate' "$nginx_file"; then
  echo "fixed-name static assets must use a short revalidating cache policy" >&2
  exit 1
fi
if (( $(grep -Fc 'include /etc/nginx/snippets/security-headers.conf;' "$nginx_file" || true) < 9 )); then
  echo "nginx cache locations must preserve shared security headers" >&2
  exit 1
fi
if ! grep -A14 -F 'server_name sim.jiuxiaoyw.online;' "$nginx_file" | grep -Fq '/etc/letsencrypt/live/sim.jiuxiaoyw.online/fullchain.pem'; then
  echo "sim vhost must serve the certificate that contains sim.jiuxiaoyw.online" >&2
  exit 1
fi
if (( $(grep -Fc 'location /.well-known/acme-challenge/' "$nginx_file" || true) < 6 )); then
  echo "every HTTP certificate vhost must expose the ACME webroot challenge" >&2
  exit 1
fi

gateway_block="$(service_block api-gateway)"
if grep -Fq 'depends_on:' <<<"$gateway_block"; then
  echo "api-gateway must start independently of backend container readiness" >&2
  exit 1
fi

for required_marker in \
    'deploy.previous' \
    'capture_diagnostics()' \
    'docker compose -f docker-compose.prod.yml --env-file .env.prod ps -a' \
    'docker compose -f docker-compose.prod.yml --env-file .env.prod logs --tail 200' \
    '恢复上一版部署配置' \
    '.deploy-candidate.' \
    'test -s "$backup_dir/.env.prod"' \
    'trap on_deploy_error ERR' \
    'rollback_release "unexpected error"' \
    'concurrency:' \
    'group: production-deploy' \
    'nginx -s reload'; do
    if ! grep -Fq "$required_marker" "$workflow_file"; then
      echo "CD workflow is missing recovery guard: $required_marker" >&2
      exit 1
    fi
done

readiness_calls="$(grep -Ec '^[[:space:]]+report_external_readiness[[:space:]]*$' "$workflow_file" || true)"
if (( readiness_calls < 2 )); then
  echo "CD workflow must report external readiness after candidate and rollback success" >&2
  exit 1
fi
if ! grep -Eq '^[[:space:]]+if rollback_release "candidate health check failed" && health_check; then[[:space:]]*$' "$workflow_file"; then
  echo "candidate health failure must invoke the shared rollback path" >&2
  exit 1
fi

rollback_block="$(awk '
  /^[[:space:]]+rollback_release\(\) \{/ { in_block = 1 }
  /^[[:space:]]+on_deploy_error\(\) \{/ { in_block = 0 }
  in_block { print }
' "$workflow_file")"
restore_line="$(grep -nF 'cp -a "$previous_dir/docker-compose.prod.yml"' <<<"$rollback_block" | head -n1 | cut -d: -f1)"
tag_line="$(grep -nF "sed -i '/^IMAGE_TAG=/d' .env.prod" <<<"$rollback_block" | head -n1 | cut -d: -f1)"
if [[ -z "$restore_line" || -z "$tag_line" ]] || (( restore_line >= tag_line )); then
  echo "rollback must restore the previous configuration before rewriting IMAGE_TAG" >&2
  exit 1
fi

echo "production compose contains Kafka and mqtt-kafka-bridge"
