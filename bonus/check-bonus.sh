#!/usr/bin/env bash
# Run on host. Checks bonus install without exposing monitoring credentials.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f Vagrantfile ]] || { echo 'Run from the ha-react-homework repository' >&2; exit 1; }
command -v vagrant >/dev/null || { echo 'Vagrant not found' >&2; exit 1; }
command -v curl >/dev/null || { echo 'curl not found' >&2; exit 1; }

echo '[bonus-check] Verifying all base HTTP endpoints'
bash scripts/check-health.sh --all

expected=''
for vm in web-01 web-02; do
  echo "[bonus-check] Checking $vm release and service"
  current="$(vagrant ssh "$vm" -c 'readlink /opt/react-app/current')"
  [[ "$current" == releases/* ]] || { echo "$vm is not using a versioned release: $current" >&2; exit 1; }
  vagrant ssh "$vm" -c 'sudo systemctl is-active --quiet react-app' >/dev/null
  if [[ -n "$expected" && "$current" != "$expected" ]]; then
    echo "Mixed releases: expected $expected, $vm uses $current" >&2
    exit 1
  fi
  expected="$current"
  echo "[bonus-check] $vm -> $current"
done

for lb in lb-01 lb-02; do
  case "$lb" in lb-01) ip=192.168.56.10 ;; lb-02) ip=192.168.56.11 ;; esac
  echo "[bonus-check] Checking $lb admin socket and protected stats"
  vagrant ssh "$lb" -c 'sudo test -S /run/haproxy/admin.sock' >/dev/null
  status="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://$ip:8404/haproxy-stats")"
  [[ "$status" == 401 ]] || { echo "$lb stats should require login (expected 401, got $status)" >&2; exit 1; }
done

echo "[bonus-check] OK — VIP healthy, both backends on $expected, runtime sockets and stats auth present"
