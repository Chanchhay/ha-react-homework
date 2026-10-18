#!/usr/bin/env bash
# Run as root on LB VM: drain|ready|wait-empty|wait-up|check-up web01|web02
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Use sudo' >&2; exit 1; }
[[ $# -eq 2 ]] || { echo 'Usage: lb-control.sh ACTION web01|web02' >&2; exit 64; }
action="$1"; backend="$2"
case "$backend" in web01|web02) ;; *) echo 'Invalid backend' >&2; exit 64 ;; esac
case "$action" in drain|ready|wait-empty|wait-up|check-up) ;; *) echo 'Invalid action' >&2; exit 64 ;; esac
sock=/run/haproxy/admin.sock
[[ -S "$sock" ]] || { echo 'Runtime API not enabled; run bootstrap-bonus' >&2; exit 1; }
api() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$sock"; }
stat_row() {
  api 'show stat' | awk -F, -v backend="$backend" '
     $1 == "react_servers" && $2 == backend {print $5 "," $18; found=1; exit}
     END {if (!found) exit 1}'
}
server_status() { local row; row="$(stat_row)"; printf '%s\n' "${row#*,}"; }
case "$action" in
  drain)
    response="$(api "set server react_servers/$backend state drain")"
    [[ -z "$response" ]] || { echo "HAProxy rejected drain: $response" >&2; exit 1; }
    status="$(server_status)"
    [[ "$status" == DRAIN* ]] || { echo "Expected DRAIN, got $status" >&2; exit 1; }
    ;;
  ready)
    response="$(api "set server react_servers/$backend state ready")"
    [[ -z "$response" ]] || { echo "HAProxy rejected ready: $response" >&2; exit 1; }
    ;;
  check-up)
    status="$(server_status)"
    [[ "$status" == UP* ]] || { echo "Backend $backend is not UP ($status)" >&2; exit 1; }
    ;;
  wait-empty)
    for ((i=0;i<30;i++)); do
      row="$(stat_row)"; sessions="${row%%,*}"
      [[ "$sessions" == 0 ]] && exit 0
      sleep 1
    done
    echo "Timed out draining $backend (remaining sessions=$sessions)" >&2; exit 1
    ;;
  wait-up)
    for ((i=0;i<30;i++)); do
      status="$(server_status)"
      [[ "$status" == UP* ]] && exit 0
      sleep 1
    done
    echo "Backend $backend failed to return UP ($status)" >&2; exit 1
    ;;
esac
