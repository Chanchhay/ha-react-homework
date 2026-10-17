#!/usr/bin/env bash
# Run on host or any VM: bash scripts/check-health.sh [--all]
set -Eeuo pipefail

usage() { printf 'Usage: %s [--all]\n' "$0"; }
log() { printf '[check-health] %s\n' "$*"; }

case "${1:-}" in
  '') include_all=false ;;
  --all) include_all=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 64; }
command -v curl >/dev/null 2>&1 || { log 'ERROR: curl is required'; exit 1; }

targets=(
  'WEB-01|http://192.168.56.20:3000/health'
  'WEB-02|http://192.168.56.21:3000/health'
)
if "$include_all"; then
  targets+=(
    'LB-01|http://192.168.56.10/health'
    'LB-02|http://192.168.56.11/health'
    'VIP|http://192.168.56.100/health'
  )
fi

passed=0
failed=0
for target in "${targets[@]}"; do
  IFS='|' read -r name url <<< "$target"
  if code="$(curl --silent --show-error --output /dev/null \
      --write-out '%{http_code}' --connect-timeout 2 --max-time 5 "$url" 2>/dev/null)"; then
    if [[ "$code" == 200 ]]; then
      printf 'UP   %-7s HTTP %s  %s\n' "$name" "$code" "$url"
      ((passed+=1))
    else
      printf 'DOWN %-7s HTTP %s  %s\n' "$name" "$code" "$url"
      ((failed+=1))
    fi
  else
    printf 'DOWN %-7s connection failed  %s\n' "$name" "$url"
    ((failed+=1))
  fi
done

log "Passed: $passed, Failed: $failed"
(( failed == 0 )) || exit 1
