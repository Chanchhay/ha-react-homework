#!/usr/bin/env bash
# Host: bash scripts/deploy-react.sh
# Internal VM step (invoked automatically): sudo bash /vagrant/scripts/deploy-react.sh --install
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
HOST_APP_DIR="$ROOT_DIR/react-app"
VM_SOURCE_DIR="/vagrant/react-app"
VM_APP_DIR="/opt/react-app"
APP_USER="reactapp"

log() { printf '[deploy-react] %s\n' "$*"; }
fail() { printf '[deploy-react] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'fail "Command failed at line $LINENO"' ERR

usage() {
  printf 'Usage: %s [--install]\n' "$0"
  printf 'Without arguments: build on host and deploy to WEB-01, then WEB-02.\n'
}

require_file() { [[ -f "$1" ]] || fail "Required file missing: $1"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Command not found: $1"; }

install_on_vm() {
  [[ ${EUID} -eq 0 ]] || fail "The VM install step must be run with sudo"
  require_cmd node
  require_cmd npm
  require_cmd systemctl
  id "$APP_USER" >/dev/null 2>&1 || fail "Run setup-web.sh on this VM first"
  [[ -d "$VM_SOURCE_DIR/dist" ]] || fail "Missing production dist/: run the host deployment build first"
  require_file "$VM_SOURCE_DIR/dist/index.html"
  require_file "$VM_SOURCE_DIR/server.mjs"
  require_file "$VM_SOURCE_DIR/package.json"
  require_file "$VM_SOURCE_DIR/package-lock.json"
  require_file "$ROOT_DIR/systemd/react-app.service"

  local server_id server_ip
  case "$(hostname -s)" in
    web-01) server_id="WEB-01"; server_ip="192.168.56.20" ;;
    web-02) server_id="WEB-02"; server_ip="192.168.56.21" ;;
    *) fail "Only run --install on web-01 or web-02 (current: $(hostname -s))" ;;
  esac

  log "Installing the build on $server_id ($server_ip)"
  # One backend may have a short interruption; the other remains available.
  if systemctl cat react-app.service >/dev/null 2>&1; then
    systemctl stop react-app.service
  fi

  install -d -m 755 -o "$APP_USER" -g "$APP_USER" "$VM_APP_DIR"
  rm -rf -- "$VM_APP_DIR/dist"
  cp -R -- "$VM_SOURCE_DIR/dist" "$VM_APP_DIR/dist"
  install -m 644 "$VM_SOURCE_DIR/server.mjs" "$VM_APP_DIR/server.mjs"
  install -m 644 "$VM_SOURCE_DIR/package.json" "$VM_APP_DIR/package.json"
  install -m 644 "$VM_SOURCE_DIR/package-lock.json" "$VM_APP_DIR/package-lock.json"
  chown -R "$APP_USER:$APP_USER" "$VM_APP_DIR"

  log "Installing locked production dependencies"
  ( cd "$VM_APP_DIR" && runuser -u "$APP_USER" -- npm ci --omit=dev --no-audit --no-fund )

  # Derive environment values from the VM identity; don't bake identity into React.
  sed \
    -e "s/^Environment=SERVER_ID=.*/Environment=SERVER_ID=$server_id/" \
    -e "s/^Environment=WEB_IP=.*/Environment=WEB_IP=$server_ip/" \
    "$ROOT_DIR/systemd/react-app.service" \
    > /tmp/ha-react-app.service
  install -m 644 /tmp/ha-react-app.service /etc/systemd/system/react-app.service
  rm -f /tmp/ha-react-app.service

  systemctl daemon-reload
  systemctl enable react-app.service >/dev/null
  systemctl restart react-app.service

  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl --fail --silent --show-error --max-time 2 \
      http://127.0.0.1:3000/health >/dev/null 2>&1; then
      log "$server_id deployed successfully; /health returns HTTP 200"
      return 0
    fi
    sleep 1
  done
  systemctl status react-app.service --no-pager || true
  fail "$server_id did not become healthy. Check: journalctl -u react-app -n 50"
}

build_and_deploy_from_host() {
  require_cmd npm
  require_cmd vagrant
  require_file "$ROOT_DIR/Vagrantfile"
  require_file "$HOST_APP_DIR/package.json"
  require_file "$HOST_APP_DIR/package-lock.json"
  require_file "$HOST_APP_DIR/server.mjs"
  require_file "$ROOT_DIR/systemd/react-app.service"

  log "Building production React app ONCE on the host"
  ( cd "$HOST_APP_DIR" && npm ci && npm run build )
  require_file "$HOST_APP_DIR/dist/index.html"

  local vm
  for vm in web-01 web-02; do
    log "Deploying to $vm using Vagrant SSH"
    ( cd "$ROOT_DIR" && vagrant ssh "$vm" \
      -c 'sudo bash /vagrant/scripts/deploy-react.sh --install' )
  done
  log "Deployment complete for both web servers"
}

case "${1:-}" in
  '') build_and_deploy_from_host ;;
  --install) [[ $# -eq 1 ]] || { usage; exit 64; }; install_on_vm ;;
  -h|--help) usage ;;
  *) usage >&2; exit 64 ;;
esac
