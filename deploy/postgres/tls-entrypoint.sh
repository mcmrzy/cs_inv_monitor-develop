#!/bin/sh
set -eu

tls_dir="${POSTGRES_TLS_DIR:-/var/lib/postgresql/tls}"
cert_file="$tls_dir/server.crt"
key_file="$tls_dir/server.key"

# DB_SSL_MODE=require encrypts the private Docker-network connection but does
# not perform CA identity verification. Generate a persistent self-signed
# server certificate on container start; operators can mount CA-issued files
# at POSTGRES_TLS_DIR without changing the image. Keep certificates outside
# PGDATA so a fresh database directory remains empty for initdb.
if [ ! -s "$cert_file" ] || [ ! -s "$key_file" ]; then
    install -d -m 0700 -o postgres -g postgres "$tls_dir"
    openssl req -new -x509 -nodes -days 825 \
        -subj "/CN=postgres" \
        -addext "subjectAltName=DNS:postgres,DNS:localhost,IP:127.0.0.1" \
        -keyout "$key_file" \
        -out "$cert_file"
    chown postgres:postgres "$cert_file" "$key_file"
    chmod 0644 "$cert_file"
    chmod 0600 "$key_file"
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
