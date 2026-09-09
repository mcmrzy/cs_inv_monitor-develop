#!/usr/bin/env bash

set -euo pipefail

if (( EUID != 0 )); then
  echo "run as root: sudo $0" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
unit_dir="$script_dir/systemd"

for unit in inv-certbot-renew.service inv-certbot-renew.timer; do
  if [[ ! -s "$unit_dir/$unit" ]]; then
    echo "missing systemd unit: $unit_dir/$unit" >&2
    exit 1
  fi
  install -m 0644 "$unit_dir/$unit" "/etc/systemd/system/$unit"
done

systemctl daemon-reload
systemctl enable --now inv-certbot-renew.timer
systemctl start inv-certbot-renew.service
systemctl is-active --quiet inv-certbot-renew.timer

echo "certbot renewal timer installed and initial renewal check completed"
