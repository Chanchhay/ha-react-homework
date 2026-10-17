#!/usr/bin/env bash
# Run inside WEB-01 or WEB-02: sudo bash /vagrant/scripts/service-manager.sh restart
set -Eeuo pipefail

SERVICE='react-app.service'
usage() { printf 'Usage: %s {start|stop|restart|status}\n' "$0"; }
fail() { printf '[service-manager] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 1 ]] || { usage >&2; exit 64; }
action="$1"
case "$action" in
  start|stop|restart|status) ;;
  *) usage >&2; exit 64 ;;
esac

command -v systemctl >/dev/null 2>&1 || fail 'systemctl not found; run inside a systemd Linux VM'

if [[ "$action" == status ]]; then
  systemctl status "$SERVICE" --no-pager
  exit $?
fi

[[ ${EUID} -eq 0 ]] || fail "Use sudo for $action"
systemctl "$action" "$SERVICE" || fail "systemctl $action failed"

if [[ "$action" == stop ]]; then
  if systemctl is-active --quiet "$SERVICE"; then
    fail "$SERVICE is still running"
  fi
  printf '[service-manager] %s stopped successfully\n' "$SERVICE"
else
  if systemctl is-active --quiet "$SERVICE"; then
    printf '[service-manager] %s is active after %s\n' "$SERVICE" "$action"
  else
    fail "$SERVICE is not active after $action"
  fi
fi
